// HADİ Crew › Test bulguları — SALT-OKUNUR (27 Ekim 2026).
// Kurucu (01:51): "Crew sadece kullanıcının bulgu açıklamasını, ekran görüntüsünü (mümkünse) görmeli, ve bulguya eklenen notlar
// görünmeli ama yapay zekâ ve claude yazıları olmadan. Başka hiçbir işlem yapamamalı."
//
// Sunucu: functions/src/field_test.ts › `feedback` › ftCrewList / ftCrewGet (yalnız kurucu/yönetici/moderatör). Yanıtta YALNIZCA
// durum, açıklama (+ sesli not dökümü), ekran görüntüsü (10 dk imzalı adres; gizli ekranda yok) ve insan notları vardır — YZ ön
// değerlendirmesi, Claude değerlendirmesi, kurucu onay/red kararı, test edenin kimliği, bağlam, derece, Akçe, rozet, zaman
// çizelgesi sunucudan gelmez. Bu ekranda hiçbir işlem (durum, onay/red, not, silme, dışa aktarma) yoktur; tam yetki yalnız
// Kurucu Paneli › Saha testi'nde (ana kurucuya bağlantı gösterilir).
import 'package:flutter/material.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/data/hadi_call.dart';
import 'package:hadi/features/field_test/my_findings.dart' show kFtResolutionTr, ftChip, ftResolutionColor;
import 'package:hadi/theme/hadi_colors.dart';
import 'package:url_launcher/url_launcher.dart';

/// Kurucu Paneli › Saha testi (tam görünüm; yalnız ana kurucuya gösterilir).
const kFounderFieldTestUrl = 'https://founder.hadisosyal.com/saha-testi';

typedef FieldTestCrewLoader = Future<Map<String, Object?>> Function(String? id);

Future<Map<String, Object?>> _defaultLoader(String? id) =>
    hadiCall('feedback', id == null ? {'op': 'ftCrewList'} : {'op': 'ftCrewGet', 'id': id});

String _text(Map<String, Object?> x) {
  final d = '${x['description'] ?? ''}'.trim();
  return d.isNotEmpty ? d : '${x['voiceTranscript'] ?? ''}'.trim();
}

String _status(Map<String, Object?> x) => '${x['status'] ?? 'yeni'}';

class FieldTestCrewScreen extends StatefulWidget {
  const FieldTestCrewScreen({super.key, this.loader, this.showFounderLink});

  @visibleForTesting
  final FieldTestCrewLoader? loader;

  /// Testler için; null ise oturumdan (ana kurucu).
  @visibleForTesting
  final bool? showFounderLink;

  @override
  State<FieldTestCrewScreen> createState() => _FieldTestCrewScreenState();
}

class _FieldTestCrewScreenState extends State<FieldTestCrewScreen> {
  List<Map<String, Object?>>? _items;
  String? _error;
  String _filter = '';

  FieldTestCrewLoader get _load => widget.loader ?? _defaultLoader;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final r = await _load(null);
      if (!mounted) return;
      setState(() {
        _items = [for (final x in asList(r['items'])) asMap(x)];
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is CallFailure ? e.message : 'Bulgular yüklenemedi.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final founder = widget.showFounderLink ?? context.dependOnInheritedWidgetOfExactType<SessionScope>()?.notifier?.isPrimary ?? false;
    final items = _items;
    final shown = items == null ? null : [for (final x in items) if (_filter.isEmpty || _status(x) == _filter) x];
    final statuses = {for (final x in items ?? const <Map<String, Object?>>[]) _status(x)};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test bulguları'),
        actions: [IconButton(tooltip: 'Yenile', onPressed: _reload, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          _Banner(founder: founder),
          const SizedBox(height: 10),
          if (statuses.length > 1)
            Wrap(spacing: 6, runSpacing: 6, children: [
              ChoiceChip(label: const Text('Tümü'), selected: _filter.isEmpty, onSelected: (_) => setState(() => _filter = '')),
              for (final s in statuses)
                ChoiceChip(label: Text(kFtResolutionTr[s] ?? s), selected: _filter == s, onSelected: (_) => setState(() => _filter = s)),
            ]),
          const SizedBox(height: 8),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: HadiColors.error)))
          else if (shown == null)
            const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
          else if (shown.isEmpty)
            Padding(padding: const EdgeInsets.all(32), child: Text('Bulgu yok.', textAlign: TextAlign.center, style: TextStyle(color: HadiColors.ink2)))
          else
            for (final x in shown) _row(x),
        ]),
      ),
    );
  }

  Widget _row(Map<String, Object?> x) {
    final s = _status(x);
    final t = _text(x);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        key: ValueKey('ft-crew-${x['id']}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FieldTestCrewDetail(id: '${x['id']}', loader: _load))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              ftChip(kFtResolutionTr[s] ?? s, ftResolutionColor(s)),
              const Spacer(),
              if (x['hasShot'] == true) Icon(Icons.image_outlined, size: 18, color: HadiColors.ink3),
            ]),
            const SizedBox(height: 8),
            Text(t.isEmpty ? '(açıklama yok)' : t, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.35)),
          ]),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.founder});
  final bool founder;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: HadiColors.mist, borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.visibility_outlined, size: 18, color: HadiColors.ink2),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Salt okunur: bulgunun açıklaması, ekran görüntüsü, ekip notları ve durumu.',
                  style: TextStyle(color: HadiColors.ink2, fontSize: 13, height: 1.35)),
              if (founder)
                TextButton.icon(
                  key: const ValueKey('ft-crew-founder-link'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                  onPressed: () => launchUrl(Uri.parse(kFounderFieldTestUrl), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Tam görünüm için Kurucu Paneli'),
                ),
            ]),
          ),
        ]),
      );
}

class FieldTestCrewDetail extends StatefulWidget {
  const FieldTestCrewDetail({super.key, required this.id, this.loader});
  final String id;
  final FieldTestCrewLoader? loader;

  @override
  State<FieldTestCrewDetail> createState() => _FieldTestCrewDetailState();
}

class _FieldTestCrewDetailState extends State<FieldTestCrewDetail> {
  Map<String, Object?>? _item;
  String? _shotUrl, _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await (widget.loader ?? _defaultLoader)(widget.id);
      if (!mounted) return;
      setState(() {
        _item = asMap(r['item']);
        _shotUrl = r['shotUrl'] is String ? r['shotUrl'] as String : null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is CallFailure ? e.message : 'Bulgu yüklenemedi.');
    }
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text(s, style: TextStyle(color: HadiColors.ink3, fontSize: 12, fontWeight: FontWeight.w800)),
      );

  @override
  Widget build(BuildContext context) {
    final x = _item;
    return Scaffold(
      appBar: AppBar(title: const Text('Test bulgusu')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: HadiColors.error))))
          : x == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
                  _label('Durum'),
                  Align(alignment: Alignment.centerLeft, child: ftChip(kFtResolutionTr[_status(x)] ?? _status(x), ftResolutionColor(_status(x)))),
                  _label('Açıklama'),
                  SelectableText('${x['description'] ?? ''}'.trim().isEmpty ? '(yazılı açıklama yok)' : '${x['description']}', style: const TextStyle(height: 1.4)),
                  if ('${x['voiceTranscript'] ?? ''}'.trim().isNotEmpty) ...[
                    _label('Sesli not (döküm)'),
                    SelectableText('${x['voiceTranscript']}', style: const TextStyle(height: 1.4)),
                  ],
                  _label('Ekran görüntüsü'),
                  if (_shotUrl != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        key: const ValueKey('ft-crew-shot'),
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (c) => Dialog(
                            insetPadding: const EdgeInsets.all(12),
                            clipBehavior: Clip.antiAlias,
                            child: GestureDetector(onTap: () => Navigator.pop(c), child: InteractiveViewer(child: Image.network(_shotUrl!, fit: BoxFit.contain))),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(_shotUrl!, width: 160, height: 290, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 160, height: 290)),
                        ),
                      ),
                    )
                  else
                    Text(x['secure'] == true ? 'Gizli ekran — görüntü alınmadı.' : 'Ekran görüntüsü yok.', style: TextStyle(color: HadiColors.ink3)),
                  _label('Notlar'),
                  ...() {
                    final notes = [for (final n in asList(x['notes'])) '${asMap(n)['text'] ?? ''}'.trim()].where((t) => t.isNotEmpty).toList();
                    if (notes.isEmpty) return [Text('Henüz not yok.', style: TextStyle(color: HadiColors.ink3))];
                    return [
                      for (final n in notes)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: HadiColors.mist, borderRadius: BorderRadius.circular(10)),
                          child: SelectableText(n, style: const TextStyle(height: 1.35)),
                        ),
                    ];
                  }(),
                ]),
    );
  }
}
