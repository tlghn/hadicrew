import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'package:hadi/data/ai_video_service.dart';
import 'package:hadi/data/models.dart' show AppFailure;
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/common.dart';
import 'package:hadi/widgets/toast.dart';

import 'package:hadi/widgets/net_fallback.dart';
import 'package:hadi/core/app_lock.dart';
import 'package:hadi/features/fun/_placeholders.dart';
import 'package:hadi/widgets/skeleton.dart';
import 'package:hadi/core/ui_gate.dart';
/// Kurucu paneli › AI video (ve /yonetim/ai-video: kurucu ya da "aivideo.manage" yetkisi).
/// Şablon videoları ekler, açar/kapatır, siler; sağlayıcı ayarlarını düzenler (functions/src/ai_video.ts).
/// Fiyat: Fiyatlar sekmesinde "AI video" (ai_video). Sağlayıcı anahtarı (fal.ai; yedek Replicate): API anahtarları
/// sekmesi (ana kurucu). Şablonlar yüklenebilir ya da Vertex AI Veo ile hayali kişilerle üretilebilir.
class AiVideoAdminTab extends StatefulWidget {
  const AiVideoAdminTab({super.key, this.embedded = true});
  final bool embedded;

  @override
  State<AiVideoAdminTab> createState() => _AiVideoAdminTabState();
}

class _AiVideoAdminTabState extends State<AiVideoAdminTab> {
  final _svc = AiVideoService.instance;
  List<AiVideoTemplate>? _items;
  Map? _cfg;
  String? _error;
  String? _busy;

  final _falModel = TextEditingController();
  final _model = TextEditingController();
  final _version = TextEditingController();
  final _imageKey = TextEditingController();
  final _videoKey = TextEditingController();
  final _maxPerDay = TextEditingController();
  final _timeout = TextEditingController();
  bool _enabled = true;
  String _provider = 'fal';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_falModel, _model, _version, _imageKey, _videoKey, _maxPerDay, _timeout]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([_svc.adminTemplates(), _svc.adminConfig()]);
      if (!mounted) return;
      final cfg = r[1] as Map;
      setState(() {
        _items = r[0] as List<AiVideoTemplate>;
        _cfg = cfg;
        _error = null;
        _enabled = cfg['enabled'] != false;
        _provider = cfg['provider'] == 'replicate' ? 'replicate' : 'fal';
        _falModel.text = '${cfg['falModel'] ?? 'fal-ai/pixverse/swap'}';
        _model.text = '${cfg['model'] ?? ''}';
        _version.text = '${cfg['version'] ?? ''}';
        _imageKey.text = '${cfg['imageKey'] ?? 'swap_image'}';
        _videoKey.text = '${cfg['videoKey'] ?? 'target_video'}';
        _maxPerDay.text = '${cfg['maxPerDay'] ?? 5}';
        _timeout.text = '${cfg['timeoutMin'] ?? 30}';
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is AppFailure ? e.message : '$e');
    }
  }

  Future<void> _run(String what, Future<void> Function() fn, {String? ok}) async {
    setState(() => _busy = what);
    try {
      await fn();
      if (mounted && ok != null) showToast(context, ok);
      await _load();
    } catch (e) {
      if (mounted) showToast(context, e is AppFailure ? e.message : '$e', duration: const Duration(seconds: 3));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _saveConfig() => _run('cfg', () async {
        await _svc.setConfig({
          'enabled': _enabled,
          'provider': _provider,
          'falModel': _falModel.text.trim(),
          'model': _model.text.trim(),
          'version': _version.text.trim(),
          'imageKey': _imageKey.text.trim(),
          'videoKey': _videoKey.text.trim(),
          'maxPerDay': int.tryParse(_maxPerDay.text.trim()) ?? 5,
          'timeoutMin': int.tryParse(_timeout.text.trim()) ?? 30,
        });
      }, ok: 'Kaydedildi');

  Future<void> _addOrEdit([AiVideoTemplate? t]) async {
    final r = await uiOnce(context, () => showDialog<_TplResult>(context: context, builder: (_) => _TemplateDialog(initial: t)));
    if (r == null) return;
    await _run('tpl', () async {
      String? videoPath, thumbPath;
      var dur = t?.durationSec ?? 0;
      if (r.videoFile != null) {
        final c = VideoPlayerController.file(File(r.videoFile!));
        try {
          await c.initialize();
          dur = (c.value.duration.inMilliseconds / 1000).round();
        } catch (_) {
          throw const AppFailure('Video açılamadı.');
        } finally {
          await c.dispose();
        }
        if (dur > 60) throw const AppFailure('Şablon en fazla 60 saniye olabilir.');
        videoPath = await _svc.uploadTemplateFile(r.videoFile!, video: true);
        final dir = await getTemporaryDirectory();
        final th = await VideoThumbnail.thumbnailFile(video: r.videoFile!, thumbnailPath: dir.path, imageFormat: ImageFormat.JPEG, maxWidth: 480, quality: 75);
        if (th != null) thumbPath = await _svc.uploadTemplateFile(th, video: false);
      }
      await _svc.templateUpsert(id: t?.id, title: r.title, videoPath: videoPath, thumbPath: thumbPath, durationSec: dur, enabled: r.enabled, order: r.order);
    }, ok: t == null ? 'Şablon eklendi' : 'Şablon güncellendi');
  }

  /// Vertex AI Veo ile hayali kişili şablon üretir (başlangıç istemlerinden seçilir ya da düzenlenir).
  Future<void> _generate() async {
    Map? p;
    try {
      p = await _svc.veoPrompts();
    } catch (e) {
      if (mounted) showToast(context, e is AppFailure ? e.message : '$e');
      return;
    }
    if (!mounted) return;
    final starters = [for (final x in (p['items'] as List? ?? const [])) (title: '${(x as Map)['title']}', prompt: '${x['prompt']}')];
    final r = await showDialog<({String title, String prompt})>(
      context: context,
      builder: (_) => _VeoDialog(starters: starters, estUsd: (p!['estUsd'] as num?)?.toDouble() ?? 0.64, model: '${p['model'] ?? ''}'),
    );
    if (r == null) return;
    await _run('gen', () => _svc.templateGenerate(r.title, r.prompt),
        ok: 'Üretim başladı (birkaç dakika sürer). Hazır olunca izleyip açabilirsin.');
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final cfg = _cfg;
    final body = _error != null && items == null
        ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
        : items == null
            ? const RowsSkeleton()
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  const InfoNote(
                    icon: Icons.gavel_rounded,
                    color: HadiColors.heyecan,
                    text: 'Kural: Şablon videolarında gerçek, tanınabilir bir kişi ya da ünlü BULUNMAMALI (lisanslı, kendi çektiğimiz '
                        'veya izinli içerik). Üyeler yalnızca kimlikle doğrulanmış kendi yüzlerini kullanabilir; çıktılar '
                        '"AI ile üretildi" etiketiyle gösterilir.',
                  ),
                  const SizedBox(height: 16),
                  Text('Şablonlar', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final t in items)
                    Card(
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 44,
                            height: 64,
                            child: t.thumbUrl == null ? ColoredBox(color: HadiColors.mist, child: Icon(Icons.movie_rounded)) : Image.network(t.thumbUrl!, fit: BoxFit.cover, errorBuilder: NetImageFallback.builder),
                          ),
                        ),
                        title: Text(t.title),
                        subtitle: Text(switch (t.genStatus) {
                          'generating' => 'Veo ile üretiliyor…',
                          'failed' => 'Veo üretimi başarısız: ${t.genError ?? '-'}',
                          _ => '${t.durationSec} sn · sıra ${t.order}${t.source == 'veo' ? ' · Veo' : ''}${t.enabled ? '' : ' · kapalı'}',
                        }),
                        onTap: _busy == null ? () => _addOrEdit(t) : null,
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (t.previewUrl != null)
                            IconButton(
                              tooltip: 'İzle',
                              icon: const Icon(Icons.play_circle_outline_rounded),
                              onPressed: () => uiOnce(context, () => showDialog<void>(context: context, builder: (_) => _PreviewDialog(url: t.previewUrl!))),
                            ),
                          Switch(
                            value: t.enabled,
                            onChanged: _busy != null || t.videoPath.isEmpty
                                ? null
                                : (v) => _run('tpl', () => _svc.templateUpsert(id: t.id, title: t.title, durationSec: t.durationSec, enabled: v, order: t.order)),
                          ),
                          IconButton(
                            tooltip: 'Sil',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: _busy != null
                                ? null
                                : () async {
                                    final ok = await uiOnce(context, () => showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: const Text('Şablon silinsin mi?'),
                                        content: Text('"${t.title}" silinir. Üyelerin önceden ürettiği videolar etkilenmez.'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
                                          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sil')),
                                        ],
                                      ),
                                    ));
                                    if (ok == true) await _run('tpl', () => _svc.templateDelete(t.id), ok: 'Silindi');
                                  },
                          ),
                        ]),
                      ),
                    ),
                  if (items.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Henüz şablon yok.')),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy == null ? () => _addOrEdit() : null,
                    icon: _busy == 'tpl' ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_rounded),
                    label: const Text('Şablon ekle (video, en fazla 60 sn)'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy == null ? _generate : null,
                    icon: _busy == 'gen' ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_rounded),
                    label: const Text('Veo ile şablon üret (hayali kişi, ≈ 0,64 \$)'),
                  ),
                  const SizedBox(height: 28),
                  Text('Sağlayıcı ayarları', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Fiyat: Fiyatlar sekmesinde "AI video" (şu an ${cfg?['price'] ?? '-'}💎, Premium ${cfg?['premiumPrice'] ?? '-'}💎; yalnızca Elmas, kurucular da öder). '
                    '${_provider == 'fal' ? 'fal.ai anahtarı: ${cfg?['falKey'] == true ? 'girildi ✓' : 'GİRİLMEDİ — yönetim girmeli (API anahtarları › fal.ai)'}' : 'Replicate belirteci: ${cfg?['replicateKey'] == true ? 'girildi ✓' : 'GİRİLMEDİ — yönetim girmeli (API anahtarları › Replicate)'}'}. '
                    'Video başına maliyet (fal.ai pixverse/swap, 720p): ≤5 sn ≈ 0,20 \$, 5–10 sn ≈ 0,40 \$.',
                    style: TextStyle(color: HadiColors.ink2, height: 1.4),
                  ),
                  SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('AI video açık'), value: _enabled, onChanged: (v) => setState(() => _enabled = v)),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'fal', label: FittedBox(fit: BoxFit.scaleDown, child: Text('fal.ai (önerilen)', maxLines: 1))),
                      ButtonSegment(value: 'replicate', label: FittedBox(fit: BoxFit.scaleDown, child: Text('Replicate', maxLines: 1))),
                    ],
                    selected: {_provider},
                    onSelectionChanged: (v) => setState(() => _provider = v.first),
                  ),
                  const SizedBox(height: 8),
                  if (_provider == 'fal')
                    TextField(controller: _falModel, decoration: const InputDecoration(labelText: 'fal.ai modeli', helperText: 'Varsayılan fal-ai/pixverse/swap (ticari kullanım serbest).'))
                  else ...[
                    TextField(controller: _model, decoration: const InputDecoration(labelText: 'Replicate modeli (sahip/ad)', helperText: 'inswapper/roop tabanlı modeller ticari kullanıma KAPALI; lisansı kontrol et.')),
                    const SizedBox(height: 8),
                    TextField(controller: _version, decoration: const InputDecoration(labelText: 'Sürüm kimliği (isteğe bağlı)', helperText: 'Topluluk modellerinde gerekir; resmi modellerde boş bırak.')),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: TextField(controller: _imageKey, decoration: const InputDecoration(labelText: 'Yüz girdisi adı'))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: _videoKey, decoration: const InputDecoration(labelText: 'Video girdisi adı'))),
                    ]),
                  ],
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextField(controller: _maxPerDay, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Üye başına günlük'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: _timeout, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Zaman aşımı (dk)'))),
                  ]),
                  const SizedBox(height: 16),
                  PrimaryButton(label: 'Ayarları kaydet', loading: _busy == 'cfg', onPressed: _busy == null ? _saveConfig : null),
                  const SizedBox(height: 32),
                ]),
              );
    return widget.embedded ? body : Scaffold(appBar: AppBar(title: const Text('AI video şablonları', maxLines: 1, overflow: TextOverflow.ellipsis)), body: body);
  }
}

class _TplResult {
  const _TplResult(this.title, this.videoFile, this.enabled, this.order);
  final String title;
  final String? videoFile;
  final bool enabled;
  final num order;
}

class _TemplateDialog extends StatefulWidget {
  const _TemplateDialog({this.initial});
  final AiVideoTemplate? initial;

  @override
  State<_TemplateDialog> createState() => _TemplateDialogState();
}

class _TemplateDialogState extends State<_TemplateDialog> {
  late final _title = TextEditingController(text: widget.initial?.title ?? '');
  late final _order = TextEditingController(text: '${widget.initial?.order ?? 0}');
  late bool _enabled = widget.initial?.enabled ?? false;
  String? _file;
  bool _noPeople = false;

  @override
  void dispose() {
    _title.dispose();
    _order.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final r = await AppLock.instance.external(() => FilePicker.platform.pickFiles(type: FileType.video));
    final p = r?.files.single.path;
    if (p != null) setState(() => _file = p);
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.initial == null;
    final canSave = _title.text.trim().length >= 2 && (!isNew || _file != null) && (_file == null || _noPeople);
    return AlertDialog(scrollable: true, 
      title: Text(isNew ? 'Şablon ekle' : 'Şablonu düzenle'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _title, maxLength: 60, decoration: const InputDecoration(labelText: 'Ad'), onChanged: (_) => setState(() {})),
          TextField(controller: _order, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Sıra')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.video_file_outlined),
            label: Text(_file != null ? 'Video seçildi ✓' : isNew ? 'Video seç' : 'Videoyu değiştir'),
          ),
          if (_file != null)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _noPeople,
              onChanged: (v) => setState(() => _noPeople = v == true),
              title: const Text('Bu videoda gerçek, tanınabilir bir kişi ya da ünlü yok ve kullanım hakkımız var.', style: TextStyle(fontSize: 13)),
            ),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Üyelere açık'), value: _enabled, onChanged: (v) => setState(() => _enabled = v)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: canSave ? () => Navigator.pop(context, _TplResult(_title.text.trim(), _file, _enabled, num.tryParse(_order.text.trim()) ?? 0)) : null,
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}

/// Veo şablon üretimi: başlangıç istemlerinden biri seçilir, istem düzenlenebilir.
class _VeoDialog extends StatefulWidget {
  const _VeoDialog({required this.starters, required this.estUsd, required this.model});
  final List<({String title, String prompt})> starters;
  final double estUsd;
  final String model;

  @override
  State<_VeoDialog> createState() => _VeoDialogState();
}

class _VeoDialogState extends State<_VeoDialog> {
  late final _title = TextEditingController(text: widget.starters.isEmpty ? '' : widget.starters.first.title);
  late final _prompt = TextEditingController(text: widget.starters.isEmpty ? '' : widget.starters.first.prompt);

  @override
  void dispose() {
    _title.dispose();
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _title.text.trim().length >= 2 && _prompt.text.trim().length >= 20;
    return AlertDialog(scrollable: true, 
      title: const Text('Veo ile şablon üret'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in widget.starters)
              ActionChip(
                label: Text(s.title),
                onPressed: () => setState(() {
                  _title.text = s.title;
                  _prompt.text = s.prompt;
                }),
              ),
          ]),
          const SizedBox(height: 8),
          TextField(controller: _title, maxLength: 60, decoration: const InputDecoration(labelText: 'Şablon adı'), onChanged: (_) => setState(() {})),
          TextField(
            controller: _prompt,
            minLines: 4,
            maxLines: 8,
            maxLength: 1500,
            decoration: const InputDecoration(labelText: 'İstem (İngilizce önerilir)', helperText: 'Sunucu her isteme "hayali yetişkin, ünlüye benzemeyen, yazı/logo yok, yüz açık" kurallarını ekler.', helperMaxLines: 3),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 6),
          Text('Model: ${widget.model} · 8 sn, 9:16, 720p, sessiz · tahmini maliyet ≈ ${widget.estUsd.toStringAsFixed(2)} \$. '
              'Üretilen şablon KAPALI gelir; izleyip uygunsa açarsın.',
              style: TextStyle(fontSize: 12, color: HadiColors.ink2)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: ok ? () => Navigator.pop(context, (title: _title.text.trim(), prompt: _prompt.text.trim())) : null,
          child: const Text('Üret'),
        ),
      ],
    );
  }
}

/// Şablonu açmadan önce izlemek için (özellikle Veo ile üretilenler).
class _PreviewDialog extends StatefulWidget {
  const _PreviewDialog({required this.url});
  final String url;

  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool _ready = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _c
        ..setLooping(true)
        ..play();
    }).catchError((Object e) {
      if (mounted) setState(() => _err = 'Video açılamadı.');
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: _ready ? _c.value.aspectRatio : 9 / 16,
        child: _err != null
            ? Center(child: Text(_err!))
            : _ready
                ? VideoPlayer(_c)
                : const Skeleton(dark: true),
      ),
    );
  }
}
