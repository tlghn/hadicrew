// HADİ — Saha testi: Test bulguları (YALNIZ Kurucu paneli › Saha testi; 27 Ekim 2026'dan beri Crew'da yok — kurucu: "test
// bulguları crew'da olmasın, sadece kurucuda olmalı". Dosya hadi_crew paketinde kalır çünkü Kurucu paneli buradan içe aktarır). Sunucu: functions/src/field_test.ts
// (`feedback` callable › ftList / ftGet / ftUpdate / ftExport; ayar ftConfigGet / ftConfigSet yalnızca ana kurucu).
//
//   FieldTestFindingsScreen   liste (durum · tür · önem · test eden süzgeçleri), çoklu seçim → JSON kopyala / indir,
//                             ayrıntı (ekran görüntüsü, döküm, bağlam, durum, kurucu notu, "JSON kopyala").
//   FieldTestConfigCard       Saha testi açık/kapalı, kitle (Test Ekibi / seçilen üyeler / tüm üyeler), alıcılar
//                             (yalnız ana kurucu / tüm kurucular). Her değişiklik gerekçeli (askReason) ve kayıtlı.
// JSON biçimi (hadi.field_test.v1) doğrudan bir yapay zekâya ("şunu düzelt") verilecek şekilde tasarlandı.
// 26 Ekim 2026: değerlendirme (derece, herkese açık yorum, başlık, sürüm, tür, özellik ödülü, spam/kopya) ftUpdate ile
// test edene bildirim olarak gider; akışta ön değerlendirme (yapay zekâ), Claude ve kurucu yorumları; kazanılan Akçe.
// Ayar kartında Akçe ödül tutarları ve toplam harcanan Akçe.
// 26 Ekim 2026 kurucu onayı: "Onay bekleyenler" süzgeci (sayılı; bekleyen varsa liste onunla açılır), ayrıntıda Claude'un
// önerisi + Onayla / Reddet (hadi › features/field_test/founder_approval.dart; karar yalnızca ana kurucuda, ftDecide).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:hadi/core/ui_gate.dart';
import 'package:hadi/features/field_test/founder_approval.dart' show FieldTestApprovalPanel;
import 'package:hadi/data/hadi_call.dart';
import 'package:hadi/data/member_models.dart' show MemberProfile;
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/hadi_sheet.dart';
import 'package:hadi/widgets/reason_dialog.dart' show askReason;
import 'package:hadi/widgets/toast.dart';

import 'hp_economy_admin.dart' show trTimestamp;
import 'roles_admin.dart' show pickMemberForRole;

const kFtStatus = {'onay_bekliyor': 'Onay bekleyenler', 'yeni': 'Yeni', 'inceleniyor': 'İnceleniyor', 'kabul_edildi': 'Kabul edildi', 'duzeltildi': 'Düzeltildi', 'canlida': 'Canlıda', 'kapandi': 'Kapandı'};
/// Değerlendirme durumları (bulgu durumu + kapanış türleri; field_test.ts › RV_STATUSES).
const kFtResolution = {
  'inceleniyor': 'İnceleniyor', 'onay_bekliyor': 'Kurucu onayında', 'kabul_edildi': 'Kabul edildi', 'duzeltildi': 'Düzeltildi', 'canlida': 'Canlıda', 'kapandi': 'Kapandı',
  'tekrar_edilemedi': 'Tekrarlanamadı', 'tasarim_karari': 'Tasarım kararı', 'reddedildi': 'Uygun görülmedi',
};
/// Kurucunun formdan seçebileceği durumlar ("Kurucu onayında"yı yalnızca Claude önerir; karar Onayla / Reddet ile).
final kFtResolutionPick = {for (final e in kFtResolution.entries) if (e.key != 'onay_bekliyor') e.key: e.value};
const kFtRating = {'dusuk': 'Düşük', 'orta': 'Orta', 'yuksek': 'Yüksek', 'kritik': 'Kritik'};
const kFtKind = {'bug': 'Hata', 'feature': 'Özellik', 'design': 'Tasarım', 'text': 'Metin'};
const kFtBonus = {'yok': 'Ödülsüz', 'iyi': 'İyi (+25)', 'harika': 'Harika (+50)'};
const kFtBy = {'ai_triage': 'Ön değerlendirme (yapay zekâ)', 'claude': 'Claude', 'founder': 'Kurucu'};
const kFtCat = {'hata': 'Hata', 'tasarim': 'Tasarım', 'metin': 'Metin/yazım', 'oneri': 'Öneri', 'ozellik': 'Yeni özellik', 'performans': 'Performans'};
const kFtSev = {'dusuk': 'Düşük', 'orta': 'Orta', 'yuksek': 'Yüksek', 'engelleyici': 'Engelleyici'};

Color _sevColor(String s) => switch (s) {
      'engelleyici' || 'kritik' => HadiColors.error,
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

  /// Bir bulguya odaklanma isteği (Kurucu paneli › /test-bulgulari/onay?id=… bağlantısı): liste "Onay bekleyenler" ile
  /// açılır ve bulgunun ayrıntısı gösterilir. Ekran henüz kurulmadıysa kurulunca karşılanır.
  static final ValueNotifier<String?> focusRequest = ValueNotifier<String?>(null);

  static void focus(String id) {
    if (id.isEmpty) return;
    focusRequest.value = null;
    focusRequest.value = id;
  }

  @override
  State<FieldTestFindingsScreen> createState() => _FieldTestFindingsScreenState();
}

class _FieldTestFindingsScreenState extends State<FieldTestFindingsScreen> with AutomaticKeepAliveClientMixin {
  String _status = 'yeni', _cat = '', _sev = '', _tester = '';
  /// İlk yüklemede onay bekleyen varsa liste "Onay bekleyenler" ile açılır (süzgeç elle değişmediyse).
  bool _autoApprovals = true;
  List<Map<String, Object?>>? _items;
  Map<String, Object?> _counts = const {};
  final Set<String> _sel = {};
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    FieldTestFindingsScreen.focusRequest.addListener(_onFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reload();
      _onFocus();
    });
  }

  @override
  void dispose() {
    FieldTestFindingsScreen.focusRequest.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    final id = FieldTestFindingsScreen.focusRequest.value;
    if (id == null || !mounted) return;
    FieldTestFindingsScreen.focusRequest.value = null; // bir kez
    setState(() {
      _status = 'onay_bekliyor';
      _autoApprovals = false;
    });
    _reload();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open(id);
    });
  }

  Future<void> _reload() async {
    try {
      final r = await hadiCall('feedback', {'op': 'ftList', 'status': _status, 'category': _cat, 'severity': _sev, 'tester': _tester});
      if (!mounted) return;
      if (_autoApprovals) {
        _autoApprovals = false;
        if (_status != 'onay_bekliyor' && asInt(asMap(r['counts'])['onay_bekliyor']) > 0) {
          setState(() => _status = 'onay_bekliyor');
          await _reload();
          return;
        }
      }
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
          avatar: e.key == 'onay_bekliyor' && asInt(_counts[e.key]) > 0 ? const Icon(Icons.gavel_rounded, size: 16, color: HadiColors.gold) : null,
          label: Text('${e.value} · ${_counts[e.key] ?? 0}'),
          onSelected: (_) {
            setState(() {
              _status = e.key;
              _autoApprovals = false;
            });
            _reload();
          },
        ),
      ChoiceChip(selected: _status == '', label: const Text('Tümü'), onSelected: (_) {
        setState(() {
          _status = '';
          _autoApprovals = false;
        });
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
                  _pill(kFtResolution['${x['resolution']}'] ?? kFtStatus['${x['status']}'] ?? '${x['status']}', x['status'] == 'onay_bekliyor' ? HadiColors.gold : HadiColors.ink3),
                  if ('${x['rating'] ?? ''}'.isNotEmpty) _pill('Derece: ${kFtRating['${x['rating']}'] ?? x['rating']}', _sevColor('${x['rating']}')),
                  if (x['kind'] == 'feature') _pill('Özellik', HadiColors.iletisim),
                  if (asInt(x['akceTotal']) > 0) _pill('+${asInt(x['akceTotal'])} Akçe', HadiColors.gold),
                  if (x['reviewPending'] == true) const Icon(Icons.hourglass_top_rounded, size: 16),
                  if (x['reviewError'] != null) const Icon(Icons.error_outline_rounded, size: 16, color: HadiColors.error),
                  if (x['secure'] == true) const Icon(Icons.lock_rounded, size: 16),
                  if (x['hasShot'] == true) const Icon(Icons.image_outlined, size: 16),
                  if (x['hasAudio'] == true) const Icon(Icons.mic_none_rounded, size: 16),
                ]),
                const SizedBox(height: 6),
                if ('${x['title'] ?? ''}'.isNotEmpty) Text('${x['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
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
  // Değerlendirme formu (herkese açık; test edene bildirim gider).
  final _comment = TextEditingController();
  final _title = TextEditingController();
  final _fix = TextEditingController();
  String _rvStatus = '', _rating = '', _kind = '', _bonus = '';
  bool _spam = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    _comment.dispose();
    _title.dispose();
    _fix.dispose();
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
        _title.text = '${_item!['title'] ?? ''}';
        _fix.text = '${_item!['fixVersion'] ?? ''}';
        _rvStatus = '${_item!['resolution'] ?? ''}';
        _rating = '${_item!['rating'] ?? ''}';
        _kind = '${_item!['kind'] ?? ''}';
        _bonus = '${_item!['bonus'] ?? ''}';
        _spam = _item!['spam'] == true;
        _comment.clear();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is CallFailure ? e.message : 'Yüklenemedi.');
    }
  }

  Future<void> _update() async {
    final r = await uiBusy('ft_update_${widget.id}', () => hadiCall('feedback', {'op': 'ftUpdate', 'id': widget.id, 'founderNote': _note.text.trim()}));
    if (r == null || !mounted) return;
    widget.onChanged?.call();
    showToast(context, 'Not kaydedildi (yalnızca kurucular görür).');
    _load();
  }

  /// Değerlendirmeyi kaydeder (by: founder) → test edene "Bulgun güncellendi" + hak edilen Akçe/rozet/duyuru.
  Future<void> _review() async {
    final x = _item ?? const {};
    final body = <String, Object?>{
      'op': 'ftUpdate', 'id': widget.id,
      if (_rvStatus.isNotEmpty && _rvStatus != x['resolution']) 'status': _rvStatus,
      if (_rating.isNotEmpty && _rating != x['rating']) 'rating': _rating,
      if (_kind.isNotEmpty && _kind != x['kind']) 'kind': _kind,
      if (_bonus.isNotEmpty && _bonus != x['bonus']) 'bonus': _bonus,
      if (_spam != (x['spam'] == true)) 'spam': _spam,
      if (_comment.text.trim().isNotEmpty) 'comment': _comment.text.trim(),
      if (_title.text.trim() != '${x['title'] ?? ''}' && _title.text.trim().isNotEmpty) 'title': _title.text.trim(),
      if (_fix.text.trim() != '${x['fixVersion'] ?? ''}' && _fix.text.trim().isNotEmpty) 'fixVersion': _fix.text.trim(),
    };
    if (body.length <= 2) {
      showToast(context, 'Değişiklik yok.');
      return;
    }
    try {
      final r = await uiBusy('ft_review_${widget.id}', () => hadiCall('feedback', body));
      if (r == null || !mounted) return;
      widget.onChanged?.call();
      final akce = asInt(r['akce']);
      showToast(context, akce > 0 ? 'Değerlendirme gönderildi; üye +$akce Akçe kazandı.' : 'Değerlendirme gönderildi; üyeye bildirim gitti.');
      _load();
    } catch (e) {
      if (mounted) showToast(context, e is CallFailure ? e.message : 'Kaydedilemedi.');
    }
  }

  /// Görüntü ve sesi kalıcı siler (ör. yanlışlıkla sohbet içeriği yakalanmış). Gerekçe zorunlu, denetim kaydına yazılır.
  Future<void> _deleteMedia() async {
    final reason = await askReason(context, title: 'Bu bulgunun ekran görüntüsü ve sesi kalıcı olarak silinsin mi?', hint: 'Neden? Örn. "Görüntüde birebir sohbet içeriği var."');
    if (reason == null || !mounted) return;
    try {
      final r = await uiBusy('ft_media_${widget.id}', () => hadiCall('feedback', {'op': 'ftMediaDelete', 'id': widget.id, 'reason': reason}));
      if (r == null || !mounted) return;
      widget.onChanged?.call();
      showToast(context, 'Görüntü ve ses silindi.');
      _load();
    } catch (e) {
      if (mounted) showToast(context, e is CallFailure ? e.message : 'Silinemedi.');
    }
  }

  Widget _choices(String label, Map<String, String> m, String value, ValueChanged<String> on) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in m.entries) ChoiceChip(selected: value == e.key, label: Text(e.value), onSelected: (_) => setState(() => on(e.key))),
          ]),
        ]),
      );

  List<Widget> _timeline(Map<String, Object?> x) {
    final reviews = [for (final r in asList(x['reviews'])) asMap(r)].reversed.toList();
    return [
      if (x['reviewError'] != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Claude değerlendirmesi reddedildi: ${x['reviewError']}', style: const TextStyle(color: HadiColors.error, fontWeight: FontWeight.w700)),
        ),
      if (x['reviewPending'] == true) Text('Claude değerlendirmesi uygulanmayı bekliyor (dakikada bir).', style: TextStyle(color: HadiColors.ink3)),
      if (x['decisionPending'] == true) Text('Kurucu kararı verildi; Claude\'un okuması bekleniyor.', style: TextStyle(color: HadiColors.ink3)),
      if (reviews.isEmpty) Text('Henüz değerlendirme yok${x['triageStatus'] == 'pending' ? ' (ön değerlendirme sırada)' : ''}.', style: TextStyle(color: HadiColors.ink3)),
      for (final r in reviews)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(kFtBy['${r['by']}'] ?? '${r['by']}', style: const TextStyle(fontWeight: FontWeight.w800)),
              if ('${r['status'] ?? ''}'.isNotEmpty) _pill(kFtResolution['${r['status']}'] ?? '${r['status']}', HadiColors.ink3),
              if ('${r['rating'] ?? ''}'.isNotEmpty) _pill(kFtRating['${r['rating']}'] ?? '${r['rating']}', _sevColor('${r['rating']}')),
              if ('${r['fixVersion'] ?? ''}'.isNotEmpty) _pill('${r['fixVersion']}', HadiColors.dostluk),
              Text(trTimestamp(asInt(r['at'])), style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
            ]),
            if ('${r['text'] ?? ''}'.isNotEmpty) SelectableText('${r['text']}', style: const TextStyle(height: 1.35)),
          ]),
        ),
      if (asMap(x['akce']).isNotEmpty)
        Text('Akçe: ${[for (final e in asMap(x['akce']).entries) '${e.key} ${asInt(e.value)}'].join(' · ')} (toplam ${asInt(x['akceTotal'])})',
            style: TextStyle(color: HadiColors.ink2, fontSize: 12.5)),
      if (x['announced'] != null)
        Text('Duyuru: ${x['announced']}${x['announceName'] == false ? ' (üye adını istemedi)' : ''}', style: TextStyle(color: HadiColors.ink2, fontSize: 12.5)),
    ];
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
                    if (_shotUrl != null || _audioUrl != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _deleteMedia,
                          style: TextButton.styleFrom(foregroundColor: HadiColors.error),
                          icon: const Icon(Icons.delete_forever_rounded),
                          label: const Text('Görüntüyü/sesi sil'),
                        ),
                      ),
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
                    // Kurucu onayı: Claude'un önerisi + Onayla / Reddet (karar yalnız ana kurucuda; bulgu yukarıda zaten var).
                    if (x['proposal'] != null) ...[
                      const Divider(height: 24),
                      FieldTestApprovalPanel(
                        id: widget.id,
                        initial: {'item': x, 'shotUrl': _shotUrl},
                        showFinding: false,
                        onDone: () {
                          widget.onChanged?.call();
                          _load();
                        },
                      ),
                      const Divider(height: 24),
                    ],
                    const SizedBox(height: 8),
                    Text('Değerlendirme akışı', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    ..._timeline(x),
                    const Divider(height: 24),
                    Text('Değerlendir (üye görür, bildirim gider)', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                    _choices('Durum', kFtResolutionPick, _rvStatus, (v) => _rvStatus = v),
                    _choices('Derece', kFtRating, _rating, (v) => _rating = v),
                    _choices('Tür', kFtKind, _kind, (v) => _kind = v),
                    if (_kind == 'feature') _choices('Özellik ödülü (canlıya alınınca bir kez)', kFtBonus, _bonus, (v) => _bonus = v),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _spam,
                      onChanged: (v) => setState(() => _spam = v),
                      title: const Text('Spam / anlamsız (Akçe verilmez)'),
                    ),
                    TextField(controller: _comment, minLines: 2, maxLines: 6, maxLength: 1500, decoration: const InputDecoration(labelText: 'Üyeye yorum (Türkçe, herkese açık değil; yalnız üye görür)')),
                    TextField(controller: _title, maxLength: 80, decoration: const InputDecoration(labelText: 'Kısa başlık (duyuruda kullanılır)')),
                    TextField(controller: _fix, maxLength: 40, decoration: const InputDecoration(labelText: 'Düzeltildiği / yayına alındığı sürüm (ör. v1.4.2)')),
                    FilledButton.icon(onPressed: _review, icon: const Icon(Icons.send_rounded), label: const Text('Değerlendirmeyi gönder')),
                    const Divider(height: 24),
                    TextField(controller: _note, minLines: 1, maxLines: 4, maxLength: 2000, decoration: const InputDecoration(labelText: 'Kurucu notu (gizli; üye görmez)')),
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

  Future<void> _editReward(String key, String label) async {
    final cur = asInt(asMap(_cfg?['rewards'])[key]);
    final ctl = TextEditingController(text: '$cur');
    final v = await uiOnce(context, () => showDialog<int>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(label),
            content: TextField(controller: ctl, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(suffixText: 'Akçe')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
              FilledButton(onPressed: () => Navigator.pop(c, int.tryParse(ctl.text.trim())), child: const Text('Kaydet')),
            ],
          ),
        ));
    ctl.dispose();
    if (v == null || v < 0 || v == cur || !mounted) return;
    await _save({'rewards': {...asMap(_cfg?['rewards']), key: v}}, '$label: $cur → $v Akçe');
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
                    Text('Açık bulgu: ${c['open'] ?? 0} · Son 24 saat: ${c['today'] ?? 0} · Verilen Akçe: ${asInt(c['akceSpent'])}', style: TextStyle(color: HadiColors.ink3, fontSize: 12.5)),
                    if (c['rewardsHidden'] == true)
                      const Text('Hizmetler\'de "Saha testi: Akçe, rozet ve duyurular" kapalı: ödül verilmez.', style: TextStyle(color: HadiColors.error, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Text('Akçe ödülleri', style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final (k, label) in const [('submit', 'Geçerli rapor'), ('accept', 'Kabul'), ('live', 'Canlıya alındı'), ('bonusGood', 'İyi özellik'), ('bonusGreat', 'Harika özellik'), ('dailySubmitCap', 'Günlük ödüllü rapor')])
                        ActionChip(
                          label: Text('$label: ${asInt(asMap(c['rewards'])[k])}'),
                          onPressed: () => _editReward(k, label),
                        ),
                    ]),
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
