import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:hadi/panel_ui/crew_ui.dart';
import 'package:go_router/go_router.dart';

import 'package:hadi/core/format.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/data/firebase_services.dart' show kFunctionsRegion;
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/hadi_sheet.dart';
import 'package:hadi/data/callables.dart';
import 'package:hadi/features/fun/_placeholders.dart';

/// Yapay zekâ güvenliği: görsellere/metinlere gizlenmiş, denetim yapay zekâsını yanıltmaya yönelik talimat
/// (prompt injection) girişimleri. Kayıtları sunucu yazar (functions/src/ai_guard.ts → ai_injection_flags);
/// bu ekran `aiSecurity` callable'ı ile listeler ve karar verir. Ana kurucu kurucu panelinden, yetkili ekip
/// (reports.review) Şikayetler ekranından açar.
class AiSecurityAdminTab extends StatefulWidget {
  const AiSecurityAdminTab({super.key, this.embedded = true});

  /// false: kendi Scaffold'u ile tam sayfa (Şikayetler › AI güvenliği, bildirim bağlantısı).
  final bool embedded;

  @override
  State<AiSecurityAdminTab> createState() => _AiSecurityAdminTabState();
}

class _Flag {
  _Flag(Map<String, Object?> m)
      : id = '${m['id'] ?? ''}',
        kind = '${m['kind'] ?? 'image'}',
        source = '${m['source'] ?? ''}',
        collection = '${m['collection'] ?? ''}',
        uid = m['uid'] as String?,
        userName = '${m['userName'] ?? ''}',
        evidence = '${m['evidence'] ?? ''}',
        matches = [for (final x in (m['matches'] as List? ?? const [])) '$x'],
        action = '${m['action'] ?? 'flagged'}',
        status = '${m['status'] ?? 'open'}',
        repeat = (m['repeat'] as num?)?.toInt() ?? 0,
        at = m['at'] is num ? DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()) : null,
        thumb = m['thumb'] as String?,
        link = '${m['link'] ?? ''}',
        decision = m['decision'] as String?,
        resolvedByName = m['resolvedByName'] as String?;

  final String id, kind, source, collection, userName, evidence, action, status, link;
  final String? uid, thumb, decision, resolvedByName;
  final List<String> matches;
  final int repeat;
  final DateTime? at;
}

const _sourceText = {
  'post': 'Gönderi',
  'post_ad_scan': 'Gönderi (reklam taraması)',
  'story': 'Story',
  'story_game_result': 'Story (oyun sonucu)',
  'avatar': 'Profil fotoğrafı',
  'profile_photo': 'Profil fotoğrafları',
  'hotornot': 'Hot or Not',
  'chat_image': 'Sohbet fotoğrafı',
  'snap': 'Snap',
  'cert': 'Belge',
  'event_album': 'Etkinlik albümü',
  'event_cover': 'Etkinlik kapağı',
  'chain': 'Hikâye zinciri',
  'application': 'Üyelik başvurusu',
  'candidate_profile': 'Aday profili',
  'ai_photo_input': 'Yapay zekâ fotoğraf düzenleme',
  'live_video': 'Canlı yayın (görüntü)',
  'live_audio': 'Canlı yayın (ses/sohbet)',
};

const _decisionText = {'approve': 'Onaylandı (yanlış alarm)', 'remove': 'Kaldırıldı', 'warn': 'Kullanıcı uyarıldı'};

class _AiSecurityAdminTabState extends State<AiSecurityAdminTab> {
  List<_Flag>? _items;
  String? _error;
  bool _onlyOpen = true;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  static Map<String, Object?> _map(Object? v) => v is Map ? v.map((k, x) => MapEntry('$k', x)) : <String, Object?>{};

  Future<Map<String, Object?>> _call(Map<String, Object?> data) async {
    if (SessionScope.read(context).services.isDemo) return {'ok': true, 'items': const <Object?>[]};
    try {
      final r = await FirebaseFunctions.instanceFor(region: kFunctionsRegion).hadiCallable('aiSecurity').call(data);
      return _map(r.data);
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? 'İşlem tamamlanamadı.');
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await _call({'op': 'list', 'status': _onlyOpen ? 'open' : 'all', 'limit': 80});
      if (!mounted) return;
      setState(() => _items = [for (final x in (d['items'] as List? ?? const [])) _Flag(_map(x))]);
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _resolve(_Flag f, String decision) async {
    final note = TextEditingController();
    final ok = await showHadiSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_decisionText[decision] ?? decision, style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            switch (decision) {
              'approve' => 'İçerik yeniden yayına girer; aynı dosya bir daha takılmaz. Üyeye "sorun bulunmadı" bildirimi gider.',
              'remove' => 'İçerik gizli kalır / kaldırılır, karantinadaki dosya silinir. Üyeye bildirim gider.',
              _ => 'Üyeye denetimi yanıltma girişimi hakkında uyarı gider. Kayıt açık kalır.',
            },
            style: Theme.of(ctx).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          TextField(controller: note, maxLength: 300, decoration: const InputDecoration(hintText: 'Not (isteğe bağlı)')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaydet')),
        ]),
      ),
    );
    final text = note.text.trim();
    note.dispose();
    if (ok != true || !mounted) return;
    setState(() => _busy.add(f.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _call({'op': 'resolve', 'id': f.id, 'decision': decision, 'note': text});
      messenger.showSnackBar(const SnackBar(content: Text('Karar kaydedildi.')));
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _busy.remove(f.id));
    }
  }

  Widget _card(_Flag f) {
    final t = Theme.of(context).textTheme;
    final open = f.status == 'open';
    final busy = _busy.contains(f.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 64,
                height: 64,
                child: f.thumb != null && f.thumb!.isNotEmpty
                    ? Image.network(f.thumb!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined))
                    : ColoredBox(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: Icon(f.kind == 'image' ? Icons.image_outlined : Icons.notes_rounded),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_sourceText[f.source] ?? f.source, style: t.titleMedium),
                Text(
                  [
                    if (f.at != null) dateTimeLong(f.at!),
                    f.kind == 'image' ? 'görsel' : 'metin',
                    f.action == 'blocked' ? 'yayımlanmadı' : 'gizlendi',
                    if (f.repeat > 0) '+${f.repeat} tekrar',
                  ].join(' · '),
                  style: t.bodySmall,
                ),
                if (f.userName.isNotEmpty || f.uid != null)
                  InkWell(
                    onTap: f.uid == null ? null : () => context.push('/uye/${f.uid}'),
                    child: Text(f.userName.isNotEmpty ? f.userName : 'Üye', style: t.bodyMedium?.copyWith(color: HadiColors.text(HadiColors.aktivite))),
                  ),
              ]),
            ),
            if (!open)
              Chip(label: Text(_decisionText[f.decision] ?? 'Kapandı'), visualDensity: VisualDensity.compact),
          ]),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(f.evidence.isEmpty ? '(kanıt yok)' : f.evidence, style: t.bodySmall?.copyWith(fontFamily: 'monospace')),
          ),
          if (f.matches.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final m in f.matches.take(8)) Chip(label: Text(m, style: t.labelSmall), visualDensity: VisualDensity.compact),
            ]),
          ],
          if (f.link.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.push(f.link),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('İçeriği aç'),
              ),
            ),
          if (f.resolvedByName != null && !open) Text('Karar: ${f.resolvedByName}', style: t.bodySmall),
          if (open) ...[
            const SizedBox(height: 8),
            if (busy)
              const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: LinearProgressIndicator(minHeight: 3))
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: () => _resolve(f, 'approve'),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Onayla'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: HadiColors.fillForWhite(HadiColors.error), foregroundColor: Colors.white),
                  onPressed: () => _resolve(f, 'remove'),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Kaldır'),
                ),
                if (f.uid != null)
                  FilledButton.tonalIcon(
                    onPressed: () => _resolve(f, 'warn'),
                    icon: const Icon(Icons.report_gmailerrorred_rounded),
                    label: const Text('Kullanıcıyı uyar'),
                  ),
              ]),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final body = RefreshIndicator(
      onRefresh: _load,
      child: CrewListView(maxWidth: 960, children: [
        Text(
          'Görsellere ya da metinlere gizlenmiş, denetim yapay zekâsını yönlendirmeye çalışan talimatlar. '
          'Yapay zekâ bunlara uymaz; şüpheli içerik yayımlanmadan incelemeye alınır.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Row(children: [
          FilterChip(
            label: const Text('Yalnızca açık'),
            selected: _onlyOpen,
            onSelected: (v) {
              setState(() {
                _onlyOpen = v;
                _items = null;
              });
              _load();
            },
          ),
          const Spacer(),
          IconButton(tooltip: 'Yenile', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ]),
        const SizedBox(height: 8),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(24), child: Text('Yüklenemedi: $_error', textAlign: TextAlign.center))
        else if (items == null)
          const RowsSkeleton(count: 4, shrink: true)
        else if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Kayıt yok. 🛡️', textAlign: TextAlign.center)),
          )
        else
          for (final f in items) _card(f),
      ]),
    );
    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text('AI güvenliği', maxLines: 1, overflow: TextOverflow.ellipsis)), body: body);
  }
}
