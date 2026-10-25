// HADİ — Saha testi: Test bulguları (Crew › Destek ve Kurucu paneli › Saha testi). Sunucu: functions/src/field_test.ts
// (`feedback` callable › ftList / ftGet / ftUpdate / ftExport; ayar ftConfigGet / ftConfigSet yalnızca ana kurucu).
//
//   FieldTestFindingsScreen   liste (durum · tür · önem · test eden süzgeçleri), çoklu seçim → JSON kopyala / indir,
//                             ayrıntı (ekran görüntüsü, döküm, bağlam, durum, kurucu notu, "JSON kopyala").
//   FieldTestConfigCard       Saha testi açık/kapalı, kitle (Test Ekibi / seçilen üyeler / tüm üyeler), alıcılar
//                             (yalnız ana kurucu / tüm kurucular). Her değişiklik gerekçeli (askReason) ve kayıtlı.
// JSON biçimi (hadi.field_test.v1) doğrudan bir yapay zekâya ("şunu düzelt") verilecek şekilde tasarlandı.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:hadi/core/ui_gate.dart';
import 'package:hadi/data/hadi_call.dart';
import 'package:hadi/data/member_models.dart' show MemberProfile;
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/hadi_sheet.dart';
import 'package:hadi/widgets/reason_dialog.dart' show askReason;
import 'package:hadi/widgets/toast.dart';

import 'hp_economy_admin.dart' show trTimestamp;
import 'roles_admin.dart' show pickMemberForRole;

const kFtStatus = {'yeni': 'Yeni', 'inceleniyor': 'İnceleniyor', 'duzeltildi': 'Düzeltildi', 'kapandi': 'Kapandı'};
const kFtCat = {'hata': 'Hata', 'tasarim': 'Tasarım', 'metin': 'Metin/yazım', 'oneri': 'Öneri', 'performans': 'Performans'};
const kFtSev = {'dusuk': 'Düşük', 'orta': 'Orta', 'yuksek': 'Yüksek', 'engelleyici': 'Engelleyici'};

Color _sevColor(String s) => switch (s) {
      'engelleyici' => HadiColors.error,
      'yuksek' => HadiColors.heyecan,
      'orta' => HadiColors.aktivite,
      _ => HadiColors.dostluk,
    };

const _pretty = JsonEncoder.withIndent('  ');

Future<void> _copyJson(BuildContext context, Object json, String what) async {
  await Clipboard.setData(ClipboardData(text: _pretty.convert(json)));
  if (context.mounted) showToast(context, '$what JSON olarak kopyalandı.');
}

Future<void> _shareJson(BuildContext context, Object json) async {
  try {
    final name = 'hadi-test-bulgulari-${DateTime.now().toIso8601String().substring(0, 16).replaceAll(':', '')}.json';
    await SharePlus.instance.share(ShareParams(files: [XFile.fromData(utf8.encode(_pretty.convert(json)), mimeType: 'application/json', name: name)], subject: 'HADİ test bulguları'));
  } catch (_) {
    if (context.mounted) showToast(context, 'Dosya paylaşılamadı; JSON kopyala ile devam edebilirsin.');
  }
}

// ------------------------------------------------------------------ liste

class FieldTestFindingsScreen extends StatefulWidget {
  const FieldTestFindingsScreen({super.key, this.header});

  /// Listenin üstünde gösterilir (Kurucu paneli: ayar kartı).
  final Widget? header;

  @override
  State<FieldTestFindingsScreen> createState() => _FieldTestFindingsScreenState();
}

class _FieldTestFindingsScreenState extends State<FieldTestFindingsScreen> with AutomaticKeepAliveClientMixin {
  String _status = 'yeni', _cat = '', _sev = '', _tester = '';
  List<Map<String, Object?>>? _items;
  Map<String, Object?> _counts = const {};
  final Set<String> _sel = {};
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    try {
      final r = await hadiCall('feedback', {'op': 'ftList', 'status': _status, 'category': _cat, 'severity': _sev, 'tester': _tester});
      if (!mounted) return;
      setState(() {
        _items = [for (final x in asList(r['items'])) asMap(x)];
        _counts = asMap(r['counts']);
        _sel.removeWhere((id) => !_items!.any((x) => x['id'] == id));
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is CallFailure ? e.message : 'Yüklenemedi.');
    }
  }

  Future<void> _export({required bool share}) async {
    if (_sel.isEmpty) return;
    final r = await uiBusy('ft_export', () => hadiCall('feedback', {'op': 'ftExport', 'ids': _sel.toList()}));
    if (r == null || !mounted) return;
    if (share) {
      await _shareJson(context, r['json'] ?? const {});
    } else {
      await _copyJson(context, r['json'] ?? const {}, '${_sel.length} bulgu');
    }
  }

  Future<void> _open(String id) async {
    await showHadiSheet<void>(context: context, showDragHandle: true, builder: (_) => FieldTestDetail(id: id, onChanged: _reload));
  }

  Widget _filters() {
    final testers = <String, String>{for (final x in _items ?? const <Map<String, Object?>>[]) '${x['uid']}': '${x['name']}'};
    DropdownMenuItem<String> it(String v, String l) => DropdownMenuItem(value: v, child: Text(l));
    return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (final e in kFtStatus.entries)
        ChoiceChip(
          selected: _status == e.key,
          label: Text('${e.value} · ${_counts[e.key] ?? 0}'),
          onSelected: (_) {
            setState(() => _status = e.key);
            _reload();
          },
        ),
      ChoiceChip(selected: _status == '', label: const Text('Tümü'), onSelected: (_) {
        setState(() => _status = '');
        _reload();
      }),
      DropdownButton<String>(value: _cat, items: [it('', 'Her tür'), for (final e in kFtCat.entries) it(e.key, e.value)], onChanged: (v) {
        setState(() => _cat = v ?? '');
        _reload();
      }),
      DropdownButton<String>(value: _sev, items: [it('', 'Her önem'), for (final e in kFtSev.entries) it(e.key, e.value)], onChanged: (v) {
        setState(() => _sev = v ?? '');
        _reload();
      }),
      DropdownButton<String>(
        value: testers.containsKey(_tester) || _tester.isEmpty ? _tester : '',
        items: [it('', 'Herkes'), for (final e in testers.entries) it(e.key, e.value.isEmpty ? e.key.substring(0, 6) : e.value)],
        onChanged: (v) {
          setState(() => _tester = v ?? '');
          _reload();
        },
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final items = _items;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
        ?widget.header,
        Row(children: [
          const Icon(Icons.bug_report_rounded, color: HadiColors.iletisim),
          const SizedBox(width: 8),
          Expanded(child: Text('Test bulguları', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
          IconButton(tooltip: 'Yenile', onPressed: _reload, icon: const Icon(Icons.refresh_rounded)),
        ]),
        const SizedBox(height: 6),
        _filters(),
        const SizedBox(height: 8),
        if (_sel.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('${_sel.length} seçili', style: const TextStyle(fontWeight: FontWeight.w800)),
                FilledButton.tonalIcon(onPressed: () => _export(share: false), icon: const Icon(Icons.copy_rounded), label: const Text('Seçilenleri JSON kopyala')),
                OutlinedButton.icon(onPressed: () => _export(share: true), icon: const Icon(Icons.download_rounded), label: const Text('JSON indir / paylaş')),
                TextButton(onPressed: () => setState(_sel.clear), child: const Text('Seçimi temizle')),
              ]),
            ),
          ),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: HadiColors.error)))
        else if (items == null)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else if (items.isEmpty)
          Padding(padding: const EdgeInsets.all(24), child: Text('Bu süzgeçte bulgu yok.', textAlign: TextAlign.center, style: TextStyle(color: HadiColors.ink3)))
        else ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _sel.length == items.length ? _sel.clear() : _sel.addAll(items.map((x) => '${x['id']}'))),
              child: Text(_sel.length == items.length ? 'Hiçbirini seçme' : 'Hepsini seç (${items.length})'),
            ),
          ),
          for (final x in items) _row(x),
        ],
      ]),
    );
  }

  Widget _row(Map<String, Object?> x) {
    final id = '${x['id']}';
    final sev = '${x['severity']}';
    final text = '${x['description']}'.isNotEmpty ? '${x['description']}' : '${x['voiceTranscript']}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Checkbox(value: _sel.contains(id), onChanged: (v) => setState(() => v == true ? _sel.add(id) : _sel.remove(id))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  _pill(kFtSev[sev] ?? sev, _sevColor(sev)),
                  _pill(kFtCat['${x['category']}'] ?? '${x['category']}', HadiColors.iletisim),
                  _pill(kFtStatus['${x['status']}'] ?? '${x['status']}', HadiColors.ink3),
                  if (x['secure'] == true) const Icon(Icons.lock_rounded, size: 16),
                  if (x['hasShot'] == true) const Icon(Icons.image_outlined, size: 16),
                  if (x['hasAudio'] == true) const Icon(Icons.mic_none_rounded, size: 16),
                ]),
                const SizedBox(height: 6),
                Text(text.isEmpty ? '(açıklama yok)' : text, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.3)),
                const SizedBox(height: 4),
                Text('${x['name']} · ${x['route']} · ${x['platform']} ${x['appVersion']} · ${trTimestamp(asInt(x['createdAt']))}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

Widget _pill(String t, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: .13), borderRadius: BorderRadius.circular(20)),
      child: Text(t, style: TextStyle(color: HadiColors.readableOn(c, HadiColors.card, 4.5), fontWeight: FontWeight.w800, fontSize: 12)),
    );

// ------------------------------------------------------------------ ayrıntı

class FieldTestDetail extends StatefulWidget {
  const FieldTestDetail({super.key, required this.id, this.onChanged});
  final String id;

  /// Durum ya da not değişince (liste yenilensin).
  final VoidCallback? onChanged;

  @override
  State<FieldTestDetail> createState() => _FieldTestDetailState();
}

class _FieldTestDetailState extends State<FieldTestDetail> {
  Map<String, Object?>? _item, _json;
  String? _shotUrl, _audioUrl, _error;
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await hadiCall('feedback', {'op': 'ftGet', 'id': widget.id});
      if (!mounted) return;
      setState(() {
        _item = asMap(r['item']);
        _json = asMap(r['json']);
        _shotUrl = r['shotUrl'] as String?;
        _audioUrl = r['audioUrl'] as String?;
        _note.text = '${_item!['founderNote'] ?? ''}';
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is CallFailure ? e.message : 'Yüklenemedi.');
    }
  }

  Future<void> _update({String? status}) async {
    final r = await uiBusy('ft_update_${widget.id}', () => hadiCall('feedback', {'op': 'ftUpdate', 'id': widget.id, 'status': ?status, 'founderNote': _note.text.trim()}));
    if (r == null || !mounted) return;
    widget.onChanged?.call();
    showToast(context, status == null ? 'Not kaydedildi.' : 'Durum: ${kFtStatus[status]}');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final x = _item;
    final t = Theme.of(context).textTheme;
    return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: _error != null
            ? Text(_error!, style: const TextStyle(color: HadiColors.error))
            : x == null
                ? const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                    Row(children: [
                      Expanded(child: Text('${kFtCat['${x['category']}']} · ${kFtSev['${x['severity']}']}', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
                      IconButton(tooltip: 'Kapat', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                    ]),
                    Text('${x['name']} · ${trTimestamp(asInt(x['createdAt']))}', style: TextStyle(color: HadiColors.ink2)),
                    const SizedBox(height: 12),
                    if (_shotUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: InteractiveViewer(child: Image.network(_shotUrl!, height: 420, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Text('Görüntü açılamadı.'))),
                      )
                    else
                      Text(x['secure'] == true ? 'Gizli ekran: görüntü alınmadı.' : 'Ekran görüntüsü yok (ya da saklama süresi doldu).', style: TextStyle(color: HadiColors.ink3)),
                    const SizedBox(height: 12),
                    _section('Açıklama', '${x['description']}'),
                    _section('Sesli not dökümü', '${x['voiceTranscript']}'.isEmpty && x['transcriptStatus'] == 'pending' ? 'Yazıya dökülüyor…' : '${x['voiceTranscript']}'),
                    if (_audioUrl != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => Clipboard.setData(ClipboardData(text: _audioUrl!)).then((_) => context.mounted ? showToast(context, 'Ses bağlantısı kopyalandı (1 gün geçerli).') : null),
                          icon: const Icon(Icons.link_rounded),
                          label: const Text('Ses kaydının bağlantısını kopyala'),
                        ),
                      ),
                    _section('Bağlam', _pretty.convert(x['context'] ?? const {}), mono: true),
                    const SizedBox(height: 8),
                    Text('Durum', style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      for (final e in kFtStatus.entries)
                        ChoiceChip(selected: x['status'] == e.key, label: Text(e.value), onSelected: (_) => _update(status: e.key)),
                    ]),
                    const SizedBox(height: 10),
                    TextField(controller: _note, minLines: 1, maxLines: 4, maxLength: 2000, decoration: const InputDecoration(labelText: 'Kurucu notu')),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      OutlinedButton.icon(onPressed: () => _update(), icon: const Icon(Icons.save_outlined), label: const Text('Notu kaydet')),
                      FilledButton.icon(onPressed: () => _copyJson(context, _json ?? const {}, 'Bulgu'), icon: const Icon(Icons.data_object_rounded), label: const Text('JSON kopyala')),
                    ]),
                  ]),
    );
  }

  Widget _section(String title, String body, {bool mono = false}) {
    if (body.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        SelectableText(body, style: TextStyle(height: 1.35, fontFamily: mono ? 'monospace' : null, fontSize: mono ? 12 : null)),
      ]),
    );
  }
}

// ------------------------------------------------------------------ ayar (yalnızca ana kurucu)

class FieldTestConfigCard extends StatefulWidget {
  const FieldTestConfigCard({super.key});

  @override
  State<FieldTestConfigCard> createState() => _FieldTestConfigCardState();
}

class _FieldTestConfigCardState extends State<FieldTestConfigCard> {
  Map<String, Object?>? _cfg;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await hadiCall('feedback', {'op': 'ftConfigGet'});
      if (mounted) setState(() => _cfg = r);
    } catch (e) {
      if (mounted) setState(() => _error = e is CallFailure ? e.message : 'Yüklenemedi.');
    }
  }

  List<Map<String, Object?>> get _uids => [for (final u in asList(_cfg?['uids'])) asMap(u)];

  Future<void> _save(Map<String, Object?> patch, String title) async {
    final reason = await askReason(context, title: title, hint: 'Neden? Örn. "Cuma akşamı 8 kişilik grupla etkinlik akışını test ediyoruz."');
    if (reason == null || !mounted) return;
    final c = _cfg ?? const {};
    final body = {
      'op': 'ftConfigSet', 'on': c['on'] == true, 'audience': c['audience'] ?? 'team', 'recipients': c['recipients'] ?? 'primary',
      'uids': [for (final u in _uids) u['uid']], ...patch, 'reason': reason,
    };
    try {
      final r = await uiBusy('ft_config', () => hadiCall('feedback', body));
      if (r == null || !mounted) return;
      setState(() => _cfg = {..._cfg ?? {}, ...r});
      showToast(context, 'Saha testi ayarı kaydedildi.');
    } catch (e) {
      if (mounted) showToast(context, e is CallFailure ? e.message : 'Kaydedilemedi.');
    }
  }

  Future<void> _addMember() async {
    final MemberProfile? m = await pickMemberForRole(context, title: 'Saha testine üye ekle');
    if (m == null || !mounted) return;
    if (_uids.any((u) => u['uid'] == m.uid)) return;
    await _save({'uids': [for (final u in _uids) u['uid'], m.uid]}, '${m.publicName} saha testine eklensin mi?');
  }

  @override
  Widget build(BuildContext context) {
    final c = _cfg;
    final t = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _error != null
            ? Text(_error!, style: const TextStyle(color: HadiColors.error))
            : c == null
                ? const Center(child: CircularProgressIndicator())
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Text('🧪', style: TextStyle(fontSize: 22)),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Saha testi', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                      Switch.adaptive(value: c['on'] == true, onChanged: (v) => _save({'on': v}, v ? 'Saha testi açılsın mı?' : 'Saha testi kapatılsın mı?')),
                    ]),
                    Text(
                      'Açıkken kitledeki üyelerin ekranında yüzen bir test balonu belirir: dokununca ekran görüntüsü alınır, açıklama ve '
                      'sesli not eklenip "Test bulguları"na gönderilir. Sohbet ve korumalı ekranlarda görüntü alınmaz.',
                      style: TextStyle(color: HadiColors.ink2, height: 1.35),
                    ),
                    if (c['serviceHidden'] == true)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('Hizmetler\'de "Saha testi" kapalı: balon kimsede görünmez.', style: TextStyle(color: HadiColors.error, fontWeight: FontWeight.w700)),
                      ),
                    const SizedBox(height: 6),
                    Text('Açık bulgu: ${c['open'] ?? 0} · Son 24 saat: ${c['today'] ?? 0}', style: TextStyle(color: HadiColors.ink3, fontSize: 12.5)),
                    const SizedBox(height: 12),
                    Text('Kimde görünsün?', style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      for (final (id, label) in const [('team', 'Test Ekibi'), ('list', 'Seçilen üyeler'), ('all', 'Tüm üyeler')])
                        ChoiceChip(selected: c['audience'] == id, label: Text(label), onSelected: (_) => c['audience'] == id ? null : _save({'audience': id}, 'Kitle: $label')),
                    ]),
                    if (c['audience'] == 'list') ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final u in _uids)
                          InputChip(
                            label: Text('${u['name']}'.isEmpty ? '${u['uid']}' : '${u['name']}'),
                            onDeleted: () => _save({'uids': [for (final x in _uids) if (x['uid'] != u['uid']) x['uid']]}, '${u['name']} saha testinden çıkarılsın mı?'),
                          ),
                        ActionChip(avatar: const Icon(Icons.person_add_alt_1_rounded, size: 18), label: const Text('Üye ekle'), onPressed: _addMember),
                      ]),
                    ],
                    const SizedBox(height: 12),
                    Text('Bulgular kime gitsin?', style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      for (final (id, label) in const [('primary', 'Yalnız ana kurucu'), ('founders', 'Tüm kurucular')])
                        ChoiceChip(selected: c['recipients'] == id, label: Text(label), onSelected: (_) => c['recipients'] == id ? null : _save({'recipients': id}, 'Alıcı: $label')),
                    ]),
                    const SizedBox(height: 4),
                    Text('"Tüm kurucular" seçiliyse kurucular bulguları HADİ Crew › Test bulguları\'nda da görür.', style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
                  ]),
      ),
    );
  }
}
