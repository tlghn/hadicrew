// HADİ — Kurucu paneli › Kuryeler (K2; sunucu functions/src/courier_apply.ts › reviewOps, courier_orders.ts › cases/payouts).
// Başvurular: belge başına kontrol listesi, onayla / reddet / düzeltme iste — GEREKÇE ZORUNLU (başvurana iletilir, kayda geçer);
//   otomatik ön kontrol yalnızca ipucu, karar yönetimde. Belgeleri açmak "Verime erişimler" günlüğüne yazılır (adli sicil dahil).
// Yenilemeler: süresi biten belgelerin yenisi. Uyuşmazlıklar: üyeye ulaşılamadı (kanıt), şikâyet (YZ özeti/önerisi; karar insanda),
//   kuryesiz kalan sipariş. Ödemeler: kurye TL ödeme talepleri. Ayarlar (yalnızca ana kurucu): config/courier + belge listesi.
import 'package:flutter/material.dart';
import 'package:hadi/panel_ui/crew_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hadi/core/app_lock.dart';
import 'package:hadi/core/money.dart';
import 'package:hadi/data/courier_service.dart';
import 'package:hadi/data/models.dart';
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/theme/hadi_icons.dart';
import 'package:hadi/widgets/auto_marquee_text.dart';
import 'package:hadi/widgets/hadi_sheet.dart';
import 'package:hadi/widgets/reason_dialog.dart';
import 'package:hadi/widgets/skeleton.dart';
import 'package:hadi/features/courier/courier_widgets.dart';
import 'package:hadi/core/ui_gate.dart';
import '../../app/crew_counts.dart' show CountTab, CrewCounts;

class CourierAdminTab extends StatelessWidget {
  const CourierAdminTab({super.key, this.embedded = true});
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final body = DefaultTabController(
      length: 5,
      child: Column(children: [
        // Sekme rozetleri: kenar menüdeki "Kuryeler" sayısının hangi sekmede olduğunu gösterir (crew_dash.ts › QUEUES).
        const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
          CountTab(text: 'Başvurular', keys: ['courierApps']),
          Tab(text: 'Yenilemeler'),
          CountTab(text: 'Uyuşmazlıklar', keys: ['courierCases']),
          CountTab(text: 'Ödemeler', keys: ['courierPayouts']),
          Tab(text: 'Ayarlar'),
        ]),
        const Expanded(child: TabBarView(children: [_Apps(status: 'pending'), _Apps(status: 'renewals'), _Cases(), _Payouts(), _Settings()])),
      ]),
    );
    return embedded ? body : Scaffold(appBar: AppBar(title: const Text('Kuryeler', maxLines: 1, overflow: TextOverflow.ellipsis)), body: CrewMaxWidth(maxWidth: 1000, padded: false, child: body));
  }
}

Future<Map<String, dynamic>?> _call(BuildContext context, String op, [Map<String, Object?> d = const {}]) async {
  try {
    return await CourierService.instance.call(op, d, 60);
  } on AppFailure catch (e) {
    if (context.mounted) courierToast(context, e.message);
    return null;
  }
}

// ---------------------------------------------------------------- başvurular

class _Apps extends StatefulWidget {
  const _Apps({required this.status});
  final String status;

  @override
  State<_Apps> createState() => _AppsState();
}

class _AppsState extends State<_Apps> {
  List<Map<String, dynamic>>? _items;
  String _status = 'pending';

  @override
  void initState() {
    super.initState();
    _status = widget.status;
    _load();
  }

  Future<void> _load() async {
    final r = await _call(context, 'reviewList', {'status': _status});
    final n = (r?['items'] as List?)?.length;
    if (_status == 'pending' && n != null) CrewCounts.instance.reconcile('courierApps', n, complete: n < 60);
    if (mounted) setState(() => _items = [for (final x in (r?['items'] as List?) ?? const []) if (x is Map) x.map((k, v) => MapEntry('$k', v))]);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        if (widget.status != 'renewals')
          Wrap(spacing: 6, children: [
            for (final s in const [('pending', 'Bekleyen'), ('needs_fix', 'Düzeltmede'), ('approved', 'Onaylı'), ('rejected', 'Reddedilen'), ('closed', 'Kapanan')])
              ChoiceChip(label: Text(s.$2), selected: _status == s.$1, onSelected: (_) {
                setState(() {
                  _status = s.$1;
                  _items = null;
                });
                _load();
              }),
          ]),
        const SizedBox(height: 8),
        if (items == null) ...[const ListTileSkeleton(), const ListTileSkeleton()],
        if (items != null && items.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text('Kayıt yok.', style: TextStyle(color: HadiColors.ink2))),
        for (final a in items ?? const <Map<String, dynamic>>[])
          Card(
            child: ListTile(
              leading: const Text('🛵', style: TextStyle(fontSize: 22)),
              title: AutoMarqueeText('${a['name'] ?? a['uid']}', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text([
                kCourierVehicles.where((v) => v.$1 == a['vehicle']).firstOrNull?.$2 ?? '${a['vehicle']}',
                '${(a['regions'] as List?)?.length ?? 0} bölge',
                if ((a['precheck'] as List?)?.isNotEmpty == true) '${(a['precheck'] as List).length} ön kontrol notu',
                if (a['submittedAt'] is num) courierTime(DateTime.fromMillisecondsSinceEpoch((a['submittedAt'] as num).toInt())),
              ].join(' · ')),
              trailing: const HadiIcon(Icons.chevron_right_rounded),
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _Review(uid: '${a['uid']}')));
                await _load();
              },
            ),
          ),
      ]),
    );
  }
}

class _Review extends StatefulWidget {
  const _Review({required this.uid});
  final String uid;

  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  Map<String, dynamic>? _a;
  final Map<String, String> _check = {};
  /// Süre takibi gereken belgelerin numarası (onayda yalnızca maskeli saklanır; görüntüler karar sonrası silinir).
  final Map<String, TextEditingController> _no = {};
  bool _busy = false;

  static const _identityDocs = {'kimlik_on', 'kimlik_arka', 'ozcekim'};

  @override
  void dispose() {
    for (final c in _no.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _call(context, 'reviewGet', {'uid': widget.uid});
    if (!mounted) return;
    if (r == null) return Navigator.of(context).pop();
    setState(() {
      _a = r;
      for (final e in ((r['checklist'] as Map?) ?? const {}).entries) {
        _check['${e.key}'] = '${e.value}';
      }
    });
  }

  Future<void> _decide(String action) async {
    final fixDocs = action == 'fix' ? [for (final e in _check.entries) if (e.value == 'bad') e.key] : <String>[];
    final reason = await askReason(
      context,
      title: switch (action) { 'approve' => 'Onay gerekçesi', 'reject' => 'Ret gerekçesi', _ => 'Düzeltme isteği' },
      message: action == 'fix' ? 'Başvurana iletilir; ${fixDocs.isEmpty ? 'kontrol listesinde "sorunlu" işaretli belge yok' : '${fixDocs.length} belge düzeltme için işaretli'}. Süre dolarsa başvuru kendiliğinden kapanır.' : 'Başvurana iletilir ve kayda geçer.',
      confirm: switch (action) { 'approve' => 'Onayla', 'reject' => 'Reddet', _ => 'Gönder' },
      danger: action == 'reject',
      hint: 'Örn. "Sigorta poliçesinin bitiş tarihi okunmuyor; net bir kopya yükle."',
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    final r = await _call(context, 'decide', {
      'uid': widget.uid, 'action': action, 'reason': reason, 'checklist': _check, 'fixDocs': fixDocs,
      if (action == 'approve') 'numbers': {for (final e in _no.entries) if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim()},
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) {
      courierToast(context, 'Kaydedildi.');
      Navigator.of(context).pop();
    }
  }

  Future<void> _renew(String docId, bool ok) async {
    final reason = await askReason(context, title: ok ? 'Yenilemeyi onayla' : 'Yenilemeyi reddet', confirm: ok ? 'Onayla' : 'Reddet', danger: !ok,
        message: 'Karardan sonra belge görüntüsü silinir; onayda yalnızca maskeli belge no ve bitiş tarihi kalır.');
    if (reason == null || !mounted) return;
    String? number;
    if (ok && !_identityDocs.contains(docId)) {
      final c = TextEditingController();
      number = await uiOnce(context, () => showDialog<String>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Belge numarası'),
          content: TextField(controller: c, decoration: const InputDecoration(labelText: 'Belge no (isteğe bağlı; yalnızca son 3 hanesi saklanır)')),
          actions: [FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Tamam'))],
        ),
      ));
      if (!mounted) return;
    }
    final r = await _call(context, 'renewDecide', {'uid': widget.uid, 'docId': docId, 'ok': ok, 'reason': reason, if (number != null && number.isNotEmpty) 'number': number});
    if (r != null && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    final defs = [for (final d in (a?['docDefs'] as List?) ?? const []) if (d is Map) CourierDocDef.fromMap(d)];
    final urls = ((a?['urls'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', v as String?));
    final docs = ((a?['docs'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', v));
    final pre = [for (final p in (a?['precheck'] as List?) ?? const []) if (p is Map) p];
    final ren = ((a?['renewalsFull'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', v));
    final renUrls = ((a?['renewUrls'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', v as String?));
    final pending = a?['status'] == 'pending';
    return Scaffold(
      appBar: AppBar(title: Text(a == null ? 'Başvuru' : '${a['name']}', maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: a == null
          ? ListView(padding: const EdgeInsets.all(16), children: const [ListTileSkeleton(), ListTileSkeleton()])
          : ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom), children: [
              Text('Durum: ${kAppStatusLabel[a['status']] ?? a['status']} · kimlik ${a['idVerified'] == true ? 'doğrulanmış' : 'DOĞRULANMAMIŞ'}', style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('Araç: ${kCourierVehicles.where((v) => v.$1 == a['vehicle']).firstOrNull?.$2 ?? a['vehicle']} ${a['plate'] ?? ''}'),
              Text('Bölgeler: ${[for (final r in (a['regions'] as List?) ?? const []) if (r is Map) '${r['ilce'] ?? ''}${'${r['ilce'] ?? ''}'.isEmpty ? '' : '/'}${r['il']}'].join(', ')}'),
              Text('Doğum: ${a['birthDate'] ?? ''} · IBAN: ${a['iban'] ?? ''} (${a['ibanName'] ?? ''})'),
              if (pre.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: HadiColors.tint(HadiColors.heyecan.withValues(alpha: .1)), borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Otomatik ön kontrol (karar vermez)', style: TextStyle(fontWeight: FontWeight.w900)),
                    for (final p in pre) Text('${p['level'] == 'error' ? '⛔' : '⚠️'} ${p['text']}'),
                  ]),
                ),
              ],
              const SizedBox(height: 12),
              const Text('Belgeler ve kontrol listesi', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              for (final d in defs)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        HadiIcon(d.special ? Icons.lock_rounded : Icons.description_outlined, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: AutoMarqueeText('${d.label}${d.requiredNow ? '' : ' (isteğe bağlı)'}', style: const TextStyle(fontWeight: FontWeight.w800))),
                        // Görüntü yalnızca karar öncesinde açılır; karardan sonra silinir (yalnızca doğrulama özeti kalır).
                        if (docs[d.id] is Map && (docs[d.id] as Map)['verified'] == true)
                          Text('Doğrulandı${(docs[d.id] as Map)['numberMasked'] != null ? ' · ${(docs[d.id] as Map)['numberMasked']}' : ''}',
                              style: TextStyle(color: HadiColors.text(HadiColors.dostluk), fontWeight: FontWeight.w700, fontSize: 12.5))
                        else
                          TextButton(
                            onPressed: urls[d.id] == null ? null : () => AppLock.instance.external(() => launchUrl(Uri.parse(urls[d.id]!), mode: LaunchMode.externalApplication)),
                            child: Text(urls[d.id] == null ? 'Yok' : 'Aç'),
                          ),
                      ]),
                      if (pending && d.expires && !_identityDocs.contains(d.id))
                        TextField(
                          controller: _no.putIfAbsent(d.id, TextEditingController.new),
                          decoration: const InputDecoration(isDense: true, labelText: 'Belge no (onayda yalnızca son 3 hanesi saklanır)'),
                        ),
                      if (docs[d.id] is Map && ((docs[d.id] as Map)['expiresAt'] is num || (docs[d.id] as Map)['issuedAt'] is num))
                        Text([
                          if ((docs[d.id] as Map)['expiresAt'] is num) 'Bitiş ${courierTime(DateTime.fromMillisecondsSinceEpoch(((docs[d.id] as Map)['expiresAt'] as num).toInt())).split(' ').first}',
                          if ((docs[d.id] as Map)['issuedAt'] is num) 'Tarih ${courierTime(DateTime.fromMillisecondsSinceEpoch(((docs[d.id] as Map)['issuedAt'] as num).toInt())).split(' ').first}',
                        ].join(' · '), style: TextStyle(color: HadiColors.ink2, fontSize: 12.5)),
                      if (pending)
                        SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: const [ButtonSegment(value: 'ok', label: Text('Uygun')), ButtonSegment(value: 'bad', label: Text('Sorunlu')), ButtonSegment(value: 'na', label: Text('Gerekmez'))],
                          emptySelectionAllowed: true,
                          selected: {if (_check[d.id] != null) _check[d.id]!},
                          onSelectionChanged: (s) => setState(() => s.isEmpty ? _check.remove(d.id) : _check[d.id] = s.first),
                        ),
                      if (ren[d.id] is Map && (ren[d.id] as Map)['status'] == 'pending')
                        Wrap(spacing: 6, children: [
                          Text('Yenileme bekliyor', style: TextStyle(color: HadiColors.text(HadiColors.heyecan), fontWeight: FontWeight.w800)),
                          if (renUrls[d.id] != null) TextButton(onPressed: () => AppLock.instance.external(() => launchUrl(Uri.parse(renUrls[d.id]!), mode: LaunchMode.externalApplication)), child: const Text('Yeni belgeyi aç')),
                          TextButton(onPressed: () => _renew(d.id, false), child: const Text('Reddet')),
                          FilledButton(onPressed: () => _renew(d.id, true), child: const Text('Onayla')),
                        ]),
                    ]),
                  ),
                ),
              const SizedBox(height: 12),
              if (pending)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Onay ya da ret sonrasında bütün belge görüntüleri (kimlik/TCKN dahil) silinir; yalnızca "doğrulandı", tarih, '
                      'rolün ve süreli belgelerde maskeli no + bitiş tarihi kalır.', style: TextStyle(color: HadiColors.ink2, fontSize: 12.5)),
                ),
              if (pending)
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton(onPressed: _busy ? null : () => _decide('approve'), child: const Text('Onayla')),
                  OutlinedButton(onPressed: _busy ? null : () => _decide('fix'), child: const Text('Düzeltme iste')),
                  TextButton(style: TextButton.styleFrom(foregroundColor: HadiColors.text(HadiColors.error)), onPressed: _busy ? null : () => _decide('reject'), child: const Text('Reddet')),
                ]),
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Geçmiş', style: TextStyle(fontWeight: FontWeight.w800)),
                children: [
                  for (final h in (a['history'] as List?) ?? const [])
                    if (h is Map) ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text('${h['action']} · ${h['reason'] ?? ''}'), subtitle: Text(courierTime(h['at'] is num ? DateTime.fromMillisecondsSinceEpoch((h['at'] as num).toInt()) : null))),
                ],
              ),
            ]),
    );
  }
}

// ---------------------------------------------------------------- uyuşmazlıklar

class _Cases extends StatefulWidget {
  const _Cases();

  @override
  State<_Cases> createState() => _CasesState();
}

class _CasesState extends State<_Cases> {
  List<Map<String, dynamic>>? _items;
  String _status = 'open';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _call(context, 'cases', {'status': _status});
    final n = (r?['items'] as List?)?.length;
    if (_status == 'open' && n != null) CrewCounts.instance.reconcile('courierCases', n, complete: n < 60);
    if (mounted) setState(() => _items = [for (final x in (r?['items'] as List?) ?? const []) if (x is Map) x.map((k, v) => MapEntry('$k', v))]);
  }

  Future<void> _resolve(Map<String, dynamic> c, String action, String label) async {
    final note = await askReason(context, title: label, message: 'Gerekçe üye, işletme ve kuryeye iletilir.', confirm: 'Karar ver');
    if (note == null || !mounted) return;
    final r = await _call(context, 'caseResolve', {'caseId': c['id'], 'action': action, 'note': note});
    if (r != null && mounted) {
      courierToast(context, '${r['message'] ?? 'Sonuçlandı.'}');
      await _load();
    }
  }

  Future<void> _shots(String id) async {
    final r = await _call(context, 'caseShots', {'caseId': id});
    for (final u in (r?['urls'] as List?) ?? const []) {
      await AppLock.instance.external(() => launchUrl(Uri.parse('$u'), mode: LaunchMode.externalApplication));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        Wrap(spacing: 6, children: [
          for (final s in const [('open', 'Açık'), ('resolved', 'Sonuçlanan')])
            ChoiceChip(label: Text(s.$2), selected: _status == s.$1, onSelected: (_) {
              setState(() {
                  _status = s.$1;
                  _items = null;
                });
              _load();
            }),
        ]),
        if (items == null) ...[const ListTileSkeleton(), const ListTileSkeleton()],
        if (items != null && items.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text('Kayıt yok.', style: TextStyle(color: HadiColors.ink2))),
        for (final c in items ?? const <Map<String, dynamic>>[]) _caseCard(c),
      ]),
    );
  }

  Widget _caseCard(Map<String, dynamic> c) {
    final o = c['order'] is Map ? CourierOrder((c['order'] as Map).map((k, v) => MapEntry('$k', v))) : null;
    final ai = (c['ai'] as Map?) ?? const {};
    final ev = (c['evidence'] as Map?) ?? const {};
    final open = c['status'] == 'open';
    final type = '${c['type']}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: AutoMarqueeText('${switch (type) { 'unreachable' => 'Üyeye ulaşılamadı', 'complaint' => 'Şikâyet', _ => 'Kuryesiz sipariş' }} · ${o?.bizName ?? ''}', style: const TextStyle(fontWeight: FontWeight.w900))),
            if (o != null) CourierStatusChip(status: o.status),
          ]),
          if (o != null) Text('${o.items.length} kalem · ${elmasText(o.holdHp + o.courierHoldHp)} · kurye ${o.courierName ?? '—'}', style: TextStyle(color: HadiColors.ink2, fontSize: 12.5)),
          if ('${c['text'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${c['text']}')),
          if (type == 'unreachable')
            Text('Kanıt: ${ev['waitedMinutes'] ?? '?'} dk bekleme · ${ev['callAttempts'] ?? 0} ulaşma denemesi · adrese ${(ev['arrivedLoc'] as Map?)?['km'] ?? '?'} km', style: TextStyle(color: HadiColors.ink2, fontSize: 12.5)),
          if (ai.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: HadiColors.tint(HadiColors.iletisim.withValues(alpha: .08)), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ai['ai'] == true ? 'Yapay zekâ özeti (öneri; karar senin)' : 'Özet', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                Text('${ai['summary'] ?? ''}'),
                if ('${ai['suggestion'] ?? ''}'.isNotEmpty) Text('Öneri: ${ai['suggestion']}', style: TextStyle(color: HadiColors.ink2)),
              ]),
            ),
          if (((c['shots'] as num?) ?? 0) > 0) Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => _shots('${c['id']}'), child: Text('${c['shots']} ekran görüntüsünü aç'))),
          if (c['decision'] is Map) Text('Karar: ${(c['decision'] as Map)['action']} · ${(c['decision'] as Map)['note']}', style: TextStyle(color: HadiColors.ink2)),
          if (open)
            Wrap(spacing: 8, runSpacing: 6, children: switch (type) {
              'unreachable' => [
                  FilledButton(onPressed: () => _resolve(c, 'member_fault', 'Üye kusurlu (teslim sayılır)'), child: const Text('Üye kusurlu')),
                  OutlinedButton(onPressed: () => _resolve(c, 'courier_fault', 'Kurye kusurlu (iade, teminat işletmeye)'), child: const Text('Kurye kusurlu')),
                  TextButton(onPressed: () => _resolve(c, 'retry', 'Yeniden teslim denensin'), child: const Text('Yeniden dene')),
                ],
              'complaint' => [
                  FilledButton(onPressed: () => _resolve(c, 'member_right', 'Üye haklı (işletmeden iade)'), child: const Text('Üye haklı')),
                  OutlinedButton(onPressed: () => _resolve(c, 'reject', 'Şikâyeti reddet'), child: const Text('Reddet')),
                ],
              _ => [
                  FilledButton(onPressed: () => _resolve(c, 'refund', 'İptal ve tam iade'), child: const Text('İade et')),
                  OutlinedButton(onPressed: () => _resolve(c, 'retry', 'Yeniden kurye ara'), child: const Text('Yeniden ara')),
                ],
            }),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- ödemeler

class _Payouts extends StatefulWidget {
  const _Payouts();

  @override
  State<_Payouts> createState() => _PayoutsState();
}

class _PayoutsState extends State<_Payouts> {
  List<Map<String, dynamic>>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _call(context, 'payoutsPending');
    final n = (r?['items'] as List?)?.length;
    if (n != null) CrewCounts.instance.reconcile('courierPayouts', n, complete: n < 60);
    if (mounted) setState(() => _items = [for (final x in (r?['items'] as List?) ?? const []) if (x is Map) x.map((k, v) => MapEntry('$k', v))]);
  }

  Future<void> _paid(Map<String, dynamic> p) async {
    final c = TextEditingController();
    final ref = await uiOnce(context, () => showDialog<String>(
      context: context,
      builder: (dc) => AlertDialog(
        title: const Text('Ödendi olarak işaretle'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Havale/EFT referansı')),
        actions: [TextButton(onPressed: () => Navigator.pop(dc), child: const Text('Vazgeç')), FilledButton(onPressed: () => Navigator.pop(dc, c.text.trim()), child: const Text('Kaydet'))],
      ),
    ));
    if (ref == null || ref.length < 3 || !mounted) return;
    if (await _call(context, 'payoutPaid', {'id': p['id'], 'bankRef': ref}) != null) await _load();
  }

  Future<void> _reject(Map<String, dynamic> p) async {
    final reason = await askReason(context, title: 'Ödeme talebini reddet', danger: true, confirm: 'Reddet');
    if (reason == null || !mounted) return;
    if (await _call(context, 'payoutReject', {'id': p['id'], 'reason': reason}) != null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        if (items == null) ...[const ListTileSkeleton(), const ListTileSkeleton()],
        if (items != null && items.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text('Bekleyen ödeme talebi yok.', style: TextStyle(color: HadiColors.ink2))),
        for (final p in items ?? const <Map<String, dynamic>>[])
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AutoMarqueeText('${p['name'] ?? ''} · ${p['amountTl']} TL (${elmasText((p['amountHp'] as num?) ?? 0)})', style: const TextStyle(fontWeight: FontWeight.w900)),
                SelectableText('${p['iban'] ?? ''} · ${p['ibanName'] ?? ''}'),
                Wrap(spacing: 8, children: [
                  FilledButton(onPressed: () => _paid(p), child: const Text('Ödendi')),
                  OutlinedButton(onPressed: () => _reject(p), child: const Text('Reddet')),
                ]),
              ]),
            ),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- ayarlar

class _Settings extends StatefulWidget {
  const _Settings();

  @override
  State<_Settings> createState() => _SettingsState();
}

const _kNumFields = <(String, String)>[
  ('feeBaseTl', 'Taban ücret (TL)'),
  ('feePerKmTl', 'Km başı (TL)'),
  ('feeMinTl', 'En az ücret (TL)'),
  ('feeMaxTl', 'En çok ücret (TL)'),
  ('surgeMax', 'Yoğunluk çarpanı tavanı'),
  ('peakMultiplier', 'Yoğun saat çarpanı'),
  ('loadFactor', 'Yük katsayısı'),
  ('offerTimeoutSec', 'Teklif yanıt süresi (sn)'),
  ('queueMaxMinutes', 'Sırada en çok bekleme (dk)'),
  ('windowMinMinutes', 'Birleştirme penceresi en az (dk)'),
  ('windowMaxMinutes', 'Birleştirme penceresi en çok (dk)'),
  ('quota', 'Kurye kotası (aynı anda sipariş)'),
  ('maxDetourKm', 'Rotadan en çok sapma (km)'),
  ('matchRadiusKm', 'Eşleştirme yarıçapı (km)'),
  ('bizApproveMinutes', 'İşletme onay süresi (dk)'),
  ('fixDeadlineDays', 'Düzeltme süresi (gün)'),
  ('commissionPct', 'Platform komisyonu (%)'),
  ('ownCommissionPct', 'Kendi kuryelerinde komisyon (%)'),
  ('minAge', 'En küçük yaş'),
  ('docRetentionDays', 'Belge saklama (gün)'),
  ('maxLinks', 'Kurye başına en çok işletme'),
  ('cooldownMinOffers', 'Dinlendirme: en az teklif'),
  ('cooldownMinAcceptPct', 'Dinlendirme: en az kabul (%)'),
  ('cooldownMaxCancelPct', 'Dinlendirme: en çok iptal (%)'),
  ('cooldownMinutes', 'Dinlendirme süresi (dk)'),
  ('unreachableWaitMinutes', 'Ulaşılamadı: bekleme (dk)'),
  ('unreachableRadiusKm', 'Ulaşılamadı: adrese uzaklık (km)'),
  ('complaintHours', 'Şikâyet süresi (saat)'),
  ('newCourierRating', 'Yeni kurye puanı'),
];

class _SettingsState extends State<_Settings> {
  Map<String, dynamic>? _cfg;
  bool _canEdit = false;
  final Map<String, TextEditingController> _c = {};
  List<Map<String, dynamic>> _docs = [];
  final _src = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    _src.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await _call(context, 'configGet');
    if (r == null || !mounted) return;
    final cfg = ((r['config'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', v));
    setState(() {
      _cfg = cfg;
      _canEdit = r['canEdit'] == true;
      for (final f in _kNumFields) {
        (_c[f.$1] ??= TextEditingController()).text = '${cfg[f.$1] ?? ''}';
      }
      _docs = [for (final d in (cfg['documents'] as List?) ?? const []) if (d is Map) d.map((k, v) => MapEntry('$k', v))];
      _src.text = '${cfg['srcRequiredFrom'] ?? ''}';
    });
  }

  Future<void> _save() async {
    final reason = await askReason(context, title: 'Kurye ayarlarını kaydet', message: 'Değişiklik kayda geçer (önce/sonra).');
    if (reason == null || !mounted) return;
    final patch = <String, Object?>{
      for (final f in _kNumFields) if (num.tryParse(_c[f.$1]!.text.replaceAll(',', '.')) != null) f.$1: num.parse(_c[f.$1]!.text.replaceAll(',', '.')),
      'srcRequiredFrom': _src.text.trim(),
      'documents': _docs,
    };
    final r = await _call(context, 'configSet', {'config': patch, 'reason': reason});
    if (r != null && mounted) {
      courierToast(context, 'Kaydedildi.');
      await _load();
    }
  }

  Future<void> _editDoc([int? i]) async {
    final d = i == null ? <String, dynamic>{'id': '', 'label': '', 'hint': '', 'vehicles': <String>[], 'required': true, 'expires': false, 'special': false, 'maxAgeDays': null, 'requiredFrom': null} : Map<String, dynamic>.from(_docs[i]);
    final id = TextEditingController(text: '${d['id'] ?? ''}'), label = TextEditingController(text: '${d['label'] ?? ''}'), hint = TextEditingController(text: '${d['hint'] ?? ''}');
    final age = TextEditingController(text: d['maxAgeDays'] == null ? '' : '${d['maxAgeDays']}'), from = TextEditingController(text: '${d['requiredFrom'] ?? ''}');
    final veh = <String>{for (final v in (d['vehicles'] as List?) ?? const []) '$v'};
    var req = d['required'] != false, exp = d['expires'] == true, spec = d['special'] == true;
    final ok = await showHadiSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sc) => StatefulBuilder(
        builder: (sc, set) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(sc).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: id, enabled: i == null, decoration: const InputDecoration(labelText: 'Kimlik (küçük harf, alt çizgi)')),
            TextField(controller: label, decoration: const InputDecoration(labelText: 'Ad')),
            TextField(controller: hint, decoration: const InputDecoration(labelText: 'Açıklama')),
            Wrap(spacing: 6, children: [
              for (final v in kCourierVehicles)
                FilterChip(label: Text(v.$2), selected: veh.contains(v.$1), onSelected: (s) => set(() => s ? veh.add(v.$1) : veh.remove(v.$1))),
            ]),
            Text('Araç seçilmezse tüm araç türleri.', style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: req, onChanged: (v) => set(() => req = v), title: const Text('Zorunlu')),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: exp, onChanged: (v) => set(() => exp = v), title: const Text('Geçerlilik tarihi var (bitince müsait değil)')),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: spec, onChanged: (v) => set(() => spec = v), title: const Text('Özel nitelikli veri (ayrı rıza, YZ yok)')),
            TextField(controller: age, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Belge en çok kaç günlük olabilir (boş: sınır yok)')),
            TextField(controller: from, decoration: const InputDecoration(labelText: 'Şu tarihten itibaren zorunlu (YYYY-AA-GG ya da srcRequiredFrom)')),
            const SizedBox(height: 10),
            FilledButton(onPressed: () => Navigator.pop(sc, true), child: const Text('Tamam')),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    final nd = {
      'id': id.text.trim().toLowerCase(),
      'label': label.text.trim(),
      'hint': hint.text.trim(),
      'vehicles': veh.toList(),
      'required': req,
      'expires': exp,
      'special': spec,
      'maxAgeDays': int.tryParse(age.text.trim()),
      'requiredFrom': from.text.trim().isEmpty ? null : from.text.trim(),
    };
    if ('${nd['id']}'.isEmpty || '${nd['label']}'.isEmpty) return;
    setState(() => i == null ? _docs.add(nd) : _docs[i] = nd);
  }

  @override
  Widget build(BuildContext context) {
    if (_cfg == null) return ListView(padding: const EdgeInsets.all(16), children: const [ListTileSkeleton(), ListTileSkeleton()]);
    return CrewListView(maxWidth: CrewWidth.form, children: [
      if (!_canEdit) Text('Ayarları yalnızca ana kurucu değiştirebilir.', style: TextStyle(color: HadiColors.ink2)),
      for (final f in _kNumFields)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: TextField(controller: _c[f.$1], enabled: _canEdit, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: f.$2, isDense: true)),
        ),
      TextField(controller: _src, enabled: _canEdit, decoration: const InputDecoration(labelText: 'SRC zorunluluk tarihi (YYYY-AA-GG)', isDense: true)),
      const SizedBox(height: 16),
      Row(children: [
        const Expanded(child: Text('Belge listesi', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
        if (_canEdit) TextButton.icon(onPressed: () => _editDoc(), icon: const HadiIcon(Icons.add_rounded), label: const Text('Belge ekle')),
      ]),
      for (var i = 0; i < _docs.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: HadiIcon(_docs[i]['special'] == true ? Icons.lock_rounded : Icons.description_outlined),
          title: Text('${_docs[i]['label']}', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text([
            _docs[i]['required'] == false ? 'isteğe bağlı' : 'zorunlu',
            if ((_docs[i]['vehicles'] as List?)?.isNotEmpty == true) (_docs[i]['vehicles'] as List).join('/'),
            if (_docs[i]['expires'] == true) 'süreli',
            if (_docs[i]['requiredFrom'] != null) '${_docs[i]['requiredFrom']}',
          ].join(' · ')),
          trailing: _canEdit
              ? Wrap(children: [
                  IconButton(onPressed: () => _editDoc(i), icon: const HadiIcon(Icons.edit_rounded)),
                  IconButton(onPressed: () => setState(() => _docs.removeAt(i)), icon: const HadiIcon(Icons.delete_outline_rounded)),
                ])
              : null,
        ),
      const SizedBox(height: 12),
      if (_canEdit) FilledButton(onPressed: _save, child: const Text('Kaydet')),
    ]);
  }
}
