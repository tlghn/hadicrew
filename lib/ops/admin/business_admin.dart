// HADİ — Yetkili: işletmeci hesabı başvuruları, işletme etkinlikleri, fatura karşılığı ödeme talepleri ve ayarlar.
// Kurucular ya da `business.review` yetkisi; ayarlar (komisyon, Elmas→TL kuru) yalnızca ana kurucu (sunucu requirePrimary).
// Sunucu: functions/src/business.ts.
import 'package:flutter/material.dart';
import 'package:hadi/panel_ui/crew_ui.dart' show CrewMaxWidth;
import 'package:hadi/data/company_info.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hadi/core/money.dart';
import 'package:hadi/data/business_service.dart';
import 'package:hadi/data/models.dart';
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/core/app_lock.dart';
import 'package:hadi/widgets/skeleton.dart';
import 'package:hadi/features/fun/_placeholders.dart';
import '../../app/crew_counts.dart' show CountTab, CrewCounts;
import 'commerce_config_admin.dart';
import 'package:hadi/core/ui_gate.dart';

String _when(DateTime? d) => d == null
    ? ''
    : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

Widget _empty(String text) => ListView(children: [
      Padding(padding: const EdgeInsets.all(40), child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: HadiColors.ink2))),
    ]);

Future<String?> _ask(BuildContext context, {required String title, required String label, String? hint, String action = 'Tamam', bool danger = false}) async {
  final c = TextEditingController();
  final ok = await uiOnce(context, () => showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(scrollable: true, 
      title: Text(title),
      content: TextField(controller: c, maxLines: 3, autofocus: true, decoration: InputDecoration(labelText: label, hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: HadiColors.fillForWhite(HadiColors.error), foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(d, true),
          child: Text(action),
        ),
      ],
    ),
  ));
  return ok == true ? c.text.trim() : null;
}

class BusinessAdminTab extends StatelessWidget {
  const BusinessAdminTab({super.key, this.embedded = true});
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final body = DefaultTabController(
      length: 5,
      child: Column(children: [
        // Sekme rozetleri: kenar menüdeki "İşletmeler" sayısının hangi sekmede olduğunu gösterir (crew_dash.ts › QUEUES).
        const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
          CountTab(text: 'Başvurular', keys: ['businessApps']),
          CountTab(text: 'Etkinlikler', keys: ['businessEvents']),
          CountTab(text: 'Ödemeler', keys: ['businessPayouts']),
          CountTab(text: 'Anlaşmazlıklar', keys: ['businessDisputes']),
          Tab(text: 'Ayarlar'),
        ]),
        const Expanded(
          child: TabBarView(children: [_Applications(), _Events(), _Payouts(), _Disputes(), _Settings()]),
        ),
      ]),
    );
    return embedded ? body : Scaffold(appBar: AppBar(title: const Text('İşletmeler', maxLines: 1, overflow: TextOverflow.ellipsis)), body: CrewMaxWidth(maxWidth: 1000, padded: false, child: body));
  }
}

mixin _Runner<T extends StatefulWidget> on State<T> {
  String? busy;
  void snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> run(String key, Future<void> Function() f, String done, Future<void> Function() reload) async {
    setState(() => busy = key);
    try {
      await f();
      if (done.isNotEmpty) snack(done);
      await reload();
    } on AppFailure catch (e) {
      snack(e.message);
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }
}

// ============================================================================ başvurular

class _Applications extends StatefulWidget {
  const _Applications();
  @override
  State<_Applications> createState() => _ApplicationsState();
}

class _ApplicationsState extends State<_Applications> with _Runner {
  List<BusinessReviewItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await BusinessService.instance.reviewList();
      CrewCounts.instance.reconcile('businessApps', r.items.length, complete: r.items.length < 50);
      if (mounted) setState(() {
        _items = r.items;
        _error = null;
      });
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _docs(BusinessReviewItem r) async {
    // Pencere hemen açılır; bağlantılar gelene kadar satırlar iskelet olarak görünür.
    final load = BusinessService.instance.reviewDocs(r.uid).catchError((Object e) {
      if (e is AppFailure && mounted) snack(e.message);
      return <String, String?>{};
    });
    await uiOnce(context, () => showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Belgeler (15 dk geçerli bağlantı)'),
        scrollable: true,
        content: FutureBuilder<Map<String, String?>>(
          future: load,
          builder: (c, snap) {
            final docs = snap.data;
            return Column(mainAxisSize: MainAxisSize.min, children: [
              for (final info in BusinessDocInfo.all)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: docs == null
                      ? const Skeleton(width: 24, height: 24, circle: true)
                      : Icon(docs[info.id] == null ? Icons.error_outline_rounded : Icons.description_rounded,
                          color: docs[info.id] == null ? HadiColors.error : HadiColors.aktivite),
                  title: Text(info.label),
                  onTap: docs?[info.id] == null ? null : () => AppLock.instance.external(() => launchUrl(Uri.parse(docs![info.id]!), mode: LaunchMode.externalApplication)),
                ),
            ]);
          },
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Kapat'))],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return RefreshIndicator(
      onRefresh: _load,
      child: items == null
          ? (_error != null ? _empty(_error!) : const RowsSkeleton())
          : items.isEmpty
              ? _empty('Bekleyen işletme başvurusu yok.')
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final r = items[i];
                    final l = r.legal;
                    final b = busy == r.uid;
                    String v(String k) => '${l[k] ?? ''}';
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(v('tradeName'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          Text('${BusinessTypeInfo.labelOf(r.type)} · başvuran ${r.name}', style: TextStyle(color: HadiColors.ink2)),
                          Text('Gönderim: ${_when(r.submittedAt)} · komisyon %${r.commissionPct}', style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
                          const SizedBox(height: 8),
                          SelectableText(
                            'Unvan: ${v('legalName')}\nVergi no: ${v('taxNo')} · ${v('taxOffice')}${v('mersis').isEmpty ? '' : '\nMERSİS: ${v('mersis')}'}\n'
                            'Yetkili: ${v('authorizedName')}\nAdres: ${v('address')}, ${v('district')} ${v('city')}\nTelefon: ${v('publicPhone')} · Web: ${v('website')}\nIBAN: ${v('iban')}',
                            style: const TextStyle(height: 1.4),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Kontrol: vergi levhasını GİB "vergi levhası doğrulama"dan, sicil kaydını Ticaret Sicil Gazetesi\'nden, ruhsatı belediyeden doğrula. Unvan, vergi no ve yetkili adı belgelerle aynı olmalı.',
                            style: TextStyle(fontSize: 12, color: HadiColors.ink3),
                          ),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            OutlinedButton.icon(onPressed: () => _docs(r), icon: const Icon(Icons.folder_open_rounded), label: Text('Belgeler (${r.docs.length})')),
                            FilledButton(
                              onPressed: b ? null : () => run(r.uid, () => BusinessService.instance.approve(r.uid), 'İşletme hesabı onaylandı.', _load),
                              child: const Text('Onayla'),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(foregroundColor: HadiColors.text(HadiColors.error)),
                              onPressed: b
                                  ? null
                                  : () async {
                                      final why = await _ask(context, title: 'Başvuruyu reddet', label: 'Gerekçe (işletmeye gösterilir)', action: 'Reddet', danger: true);
                                      if (why == null || why.isEmpty) return;
                                      await run(r.uid, () => BusinessService.instance.reject(r.uid, why), 'Başvuru reddedildi.', _load);
                                    },
                              child: const Text('Reddet'),
                            ),
                          ]),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }
}

// ============================================================================ etkinlikler

class _Events extends StatefulWidget {
  const _Events();
  @override
  State<_Events> createState() => _EventsState();
}

class _EventsState extends State<_Events> with _Runner {
  List<BusinessEventItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await BusinessService.instance.pendingEvents();
      CrewCounts.instance.reconcile('businessEvents', r.length, complete: r.length < 50);
      if (mounted) setState(() {
        _items = r;
        _error = null;
      });
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return RefreshIndicator(
      onRefresh: _load,
      child: items == null
          ? (_error != null ? _empty(_error!) : const RowsSkeleton())
          : items.isEmpty
              ? _empty('Onay bekleyen işletme etkinliği yok.')
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final e = items[i];
                    final x = e.input;
                    final b = busy == e.id;
                    final inc = (x['includedItems'] as List?) ?? const [];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(e.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          Text('${e.businessName} · ${_when(e.startAt)} · ${e.priceHp > 0 ? elmasText(e.priceHp) : 'Ücretsiz'}${x['premiumPriceHp'] is num ? ' (Premium ${elmasText(x['premiumPriceHp'] as num)})' : ''} · ${e.capacity} kişi',
                              style: TextStyle(color: HadiColors.ink2)),
                          const SizedBox(height: 8),
                          Text('${x['description'] ?? ''}', maxLines: 6, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 6),
                          Text('Dahil: ${x['includes'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('Dahil değil: ${x['excludes'] ?? ''}'),
                          if (inc.isNotEmpty) Text('Menüden: ${inc.map((i) => '${(i as Map)['qty']} × ${i['name']}').join(', ')}'),
                          if ('${x['discounts'] ?? ''}'.isNotEmpty) Text('İndirim: ${x['discounts']}'),
                          Text('Yer: ${x['venueName'] ?? ''}, ${x['address'] ?? ''} ${x['city'] ?? ''}', style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, children: [
                            FilledButton(
                              onPressed: b ? null : () => run(e.id, () => BusinessService.instance.approveEvent(e.id), 'Etkinlik yayımlandı.', _load),
                              child: const Text('Onayla ve yayımla'),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(foregroundColor: HadiColors.text(HadiColors.error)),
                              onPressed: b
                                  ? null
                                  : () async {
                                      final why = await _ask(context, title: 'Etkinliği reddet', label: 'Gerekçe', hint: 'Ör. fiyat kapsamı belirsiz, ek ücret ima ediliyor', action: 'Reddet', danger: true);
                                      if (why == null || why.isEmpty) return;
                                      await run(e.id, () => BusinessService.instance.rejectEvent(e.id, why), 'Etkinlik reddedildi.', _load);
                                    },
                              child: const Text('Reddet'),
                            ),
                          ]),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }
}

// ============================================================================ ödemeler

class _Payouts extends StatefulWidget {
  const _Payouts();
  @override
  State<_Payouts> createState() => _PayoutsState();
}

class _PayoutsState extends State<_Payouts> with _Runner {
  List<BusinessPayoutItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await BusinessService.instance.pendingPayouts();
      CrewCounts.instance.reconcile('businessPayouts', r.length, complete: r.length < 50);
      if (mounted) setState(() {
        _items = r;
        _error = null;
      });
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Talep olmadan yapılan ödemeyi fatura bilgisiyle kaydeder (bakiyeden Elmas + komisyon düşülür).
  Future<void> _record() async {
    final uid = TextEditingController(), tl = TextEditingController(), no = TextEditingController(), ref = TextEditingController();
    final date = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));
    final ok = await uiOnce(context, () => showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(scrollable: true, 
        title: const Text('Ödeme kaydet'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('HADİ\'nin işletmeye yaptığı havaleyi fatura bilgisiyle kaydet. İşletmenin Elmas bakiyesinden fatura tutarının Elmas karşılığı ve anlaşılan komisyon düşülür.',
                style: TextStyle(fontSize: 12.5, color: HadiColors.ink2)),
            const SizedBox(height: 10),
            TextField(controller: uid, decoration: const InputDecoration(labelText: 'İşletme hesabı (uid)')),
            const SizedBox(height: 8),
            TextField(controller: tl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Fatura tutarı (TL)')),
            const SizedBox(height: 8),
            TextField(controller: no, decoration: const InputDecoration(labelText: 'Fatura no')),
            const SizedBox(height: 8),
            TextField(controller: date, decoration: const InputDecoration(labelText: 'Fatura tarihi (YYYY-AA-GG)')),
            const SizedBox(height: 8),
            TextField(controller: ref, decoration: const InputDecoration(labelText: 'Havale/EFT referansı')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Kaydet')),
        ],
      ),
    ));
    if (ok != true) return;
    final amount = double.tryParse(tl.text.replaceAll(',', '.').trim()) ?? 0;
    await run('record', () async {
      final r = await BusinessService.instance.recordPayout(uid: uid.text.trim(), amountTl: amount, invoiceNo: no.text.trim(), invoiceDate: date.text.trim(), bankRef: ref.text.trim());
      snack('Kaydedildi: ${elmasText(r.baseHp)} + komisyon ${elmasText(r.commissionHp)} düşüldü.');
    }, '', _load);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(onPressed: busy != null ? null : _record, icon: const Icon(Icons.receipt_long_rounded), label: const Text('Ödeme kaydet (fatura)')),
        ),
      ),
      Expanded(child: _list(context)),
    ]);
  }

  Widget _list(BuildContext context) {
    final items = _items;
    return RefreshIndicator(
      onRefresh: _load,
      child: items == null
          ? (_error != null ? _empty(_error!) : const RowsSkeleton())
          : items.isEmpty
              ? _empty('Bekleyen ödeme talebi yok.')
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final p = items[i];
                    final b = busy == p.id;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p.businessName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          Text('${formatTl(p.amountTl)} · ${elmasText(p.baseHp)} + %${p.commissionPct.toStringAsFixed(p.commissionPct == p.commissionPct.roundToDouble() ? 0 : 1)} komisyon ${elmasText(p.commissionHp)} = ${elmasText(p.amountHp)}',
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text('Fatura ${p.invoiceNo} · ${p.invoiceDate} · talep ${_when(p.createdAt)}', style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
                          SelectableText('IBAN: ${p.iban}'),
                          const SizedBox(height: 4),
                          Text('Faturanın ${CompanyInfo.instance.legalName} adına, bu tutarda kesildiğini kontrol et; havaleyi yaptıktan sonra referansla "Ödendi" işaretle. '
                              'Ödendi işaretlenince işletmenin Elmas bakiyesinden fatura tutarının Elmas karşılığı ve komisyon düşülür.',
                              style: TextStyle(fontSize: 12, color: HadiColors.ink3)),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            if (p.invoiceUrl != null)
                              OutlinedButton.icon(
                                onPressed: () => AppLock.instance.external(() => launchUrl(Uri.parse(p.invoiceUrl!), mode: LaunchMode.externalApplication)),
                                icon: const Icon(Icons.picture_as_pdf_rounded),
                                label: const Text('Faturayı aç'),
                              ),
                            FilledButton(
                              onPressed: b
                                  ? null
                                  : () async {
                                      final ref = await _ask(context, title: 'Ödendi olarak işaretle', label: 'Havale/EFT referansı', action: 'Ödendi');
                                      if (ref == null || ref.isEmpty) return;
                                      await run(p.id, () => BusinessService.instance.payoutPaid(p.id, ref), 'Ödeme kaydedildi.', _load);
                                    },
                              child: const Text('Ödendi'),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(foregroundColor: HadiColors.text(HadiColors.error)),
                              onPressed: b
                                  ? null
                                  : () async {
                                      final why = await _ask(context, title: 'Talebi reddet', label: 'Gerekçe', hint: 'Ör. fatura unvanı/tutarı hatalı', action: 'Reddet', danger: true);
                                      if (why == null || why.isEmpty) return;
                                      await run(p.id, () => BusinessService.instance.payoutReject(p.id, why), 'Talep reddedildi.', _load);
                                    },
                              child: const Text('Reddet'),
                            ),
                          ]),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }
}

// ============================================================================ ayarlar (ana kurucu)

// ============================================================================ sipariş anlaşmazlıkları + teslim onay süresi

/// Üyenin "teslim almadım / sorun var" dediği kayıtlar: ödeme blokede donuk; karar: işletmeye ver / üyeye iade / kısmi.
class _Disputes extends StatefulWidget {
  const _Disputes();
  @override
  State<_Disputes> createState() => _DisputesState();
}

class _DisputesState extends State<_Disputes> with _Runner {
  List<BizOrder>? _items;
  String? _error;
  int _minutes = 15;
  bool _canEdit = false;
  final _min = TextEditingController();
  final _ask = TextEditingController();
  final _ans = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _min.dispose();
    _ask.dispose();
    _ans.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await BusinessService.instance.orderDisputes();
      CrewCounts.instance.reconcile('businessDisputes', r.length, complete: r.length < 100);
      final c = await BusinessService.instance.orderConfig();
      if (!mounted) return;
      setState(() {
        _items = r;
        _minutes = c.minutes;
        _canEdit = c.canEdit;
        _min.text = '${c.minutes}';
        _ask.text = '${c.askHours}';
        _ans.text = '${c.answerHours}';
        _error = null;
      });
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _resolve(BizOrder o) async {
    var action = 'release';
    var pct = 50.0;
    final note = TextEditingController();
    final ok = await uiOnce(context, () => showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(scrollable: true, 
          title: Text('Karar · ${o.bizName}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${o.memberName}: ${o.dispute?['note'] ?? ''}', style: TextStyle(color: HadiColors.ink2)),
              const SizedBox(height: 10),
              RadioGroup<String>(
                groupValue: action,
                onChanged: (v) => set(() => action = v ?? action),
                child: const Column(children: [
                  RadioListTile(value: 'release', title: Text('İşletmeye ver (teslim edilmiş)')),
                  RadioListTile(value: 'refund', title: Text('Üyeye tam iade')),
                  RadioListTile(value: 'partial', title: Text('Kısmi')),
                ]),
              ),
              if (action == 'partial') ...[
                Text('İşletmeye: %${pct.round()} · üyeye: %${100 - pct.round()}'),
                Slider(value: pct, min: 1, max: 99, divisions: 98, onChanged: (v) => set(() => pct = v)),
              ],
              TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Gerekçe (iki tarafa da iletilir, en az 10 karakter)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Uygula')),
          ],
        ),
      ),
    ));
    if (ok != true) return;
    await run(o.id, () => BusinessService.instance.resolveOrder(o.id, action: action, pct: pct.round(), note: note.text.trim()), 'Karar uygulandı.', _load);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) return _error != null ? _empty(_error!) : const RowsSkeleton();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: HadiColors.mist, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Teslim onay süresi', style: TextStyle(fontWeight: FontWeight.w900)),
            Text('İşletme "teslim edildi" dedikten sonra üye bu süre içinde yanıt vermezse teslim alındı sayılır ve blokedeki Elmas işletmeye geçer. Şu an: $_minutes dk.',
                style: TextStyle(color: HadiColors.ink2, fontSize: 12.5)),
            if (_canEdit)
              Row(children: [
                SizedBox(width: 110, child: TextField(controller: _min, keyboardType: TextInputType.number, decoration: const InputDecoration(suffixText: 'dk', isDense: true))),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: busy != null
                      ? null
                      : () => run(
                          'cfg',
                          () => BusinessService.instance.setOrderConfig(
                            int.tryParse(_min.text.trim()) ?? 15,
                            askHours: int.tryParse(_ask.text.trim()),
                            answerHours: int.tryParse(_ans.text.trim()),
                          ),
                          'Kaydedildi.',
                          _load),
                  child: const Text('Kaydet'),
                ),
              ]),
            const SizedBox(height: 10),
            const Text('Teslim edilmeyen kayıt', style: TextStyle(fontWeight: FontWeight.w900)),
            Text('İşletme onaylayıp "teslim edildi" demezse (randevuluysa randevu saatinden) bu süre sonra üyeye "Siparişin geldi mi?" sorulur; '
                '"gelmedi" derse ya da yanıt süresinde yanıt vermezse blokedeki Elmas üyeye iade edilir.',
                style: TextStyle(color: HadiColors.ink2, fontSize: 12.5)),
            if (_canEdit)
              Row(children: [
                SizedBox(width: 120, child: TextField(controller: _ask, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Sor', suffixText: 'saat', isDense: true))),
                const SizedBox(width: 10),
                SizedBox(width: 120, child: TextField(controller: _ans, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Yanıt', suffixText: 'saat', isDense: true))),
              ]),
          ]),
        ),
        const SizedBox(height: 14),
        // Kargo ve gel-al süreleri, kargo takip bağlantıları (K1 · commerce_pricing.ts › config/commerce).
        const CommerceConfigCard(),
        const SizedBox(height: 14),
        if (items.isEmpty) Padding(padding: EdgeInsets.all(24), child: Text('Bekleyen anlaşmazlık yok.', textAlign: TextAlign.center, style: TextStyle(color: HadiColors.ink2))),
        for (final o in items)
          Card(
            child: ListTile(
              title: Text('${o.bizName} · ${o.memberName}', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${o.kindLabel} · ${elmasText(o.holdHp)} blokede\n${o.dispute?['note'] ?? ''}\n${_when(o.createdAt)}', maxLines: 5),
              isThreeLine: true,
              trailing: FilledButton(onPressed: busy != null ? null : () => _resolve(o), child: const Text('Karar')),
            ),
          ),
      ]),
    );
  }
}

class _Settings extends StatefulWidget {
  const _Settings();
  @override
  State<_Settings> createState() => _SettingsState();
}

class _SettingsState extends State<_Settings> with _Runner {
  final _pct = TextEditingController();
  final _rate = TextEditingController();
  final _ovUid = TextEditingController();
  final _ovPct = TextEditingController();
  bool _primary = false;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_pct, _rate, _ovUid, _ovPct]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await BusinessService.instance.reviewList();
      if (!mounted) return;
      setState(() {
        _primary = r.isPrimary;
        _pct.text = '${r.commissionPct}';
        _rate.text = r.hpToTl > 0 ? '${r.hpToTl}' : '';
        _loaded = true;
        _error = null;
      });
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  double? _num(String s) => double.tryParse(s.replaceAll(',', '.').trim());

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return _error != null ? _empty(_error!) : const RowsSkeleton();
    final b = busy != null;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(_primary ? 'Bu ayarları yalnızca ana kurucu değiştirebilir.' : 'Görüntüleme: ayarları yalnızca ana kurucu değiştirebilir.',
          style: TextStyle(color: HadiColors.ink3)),
      const SizedBox(height: 12),
      TextField(
        controller: _pct,
        enabled: _primary,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Komisyon (%) — işletme cirosundan HADİ payı',
          helperText: '0–50; her ödemede fatura tutarıyla birlikte işletmenin Elmas bakiyesinden düşülür',
          helperMaxLines: 2,
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _rate,
        enabled: _primary,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: '1💎 = ? TL (Elmas kuru)',
          helperText: 'İşletme fiyat listelerindeki Elmas karşılıkları, rezervasyon/sipariş ödemeleri ve işletme ödemeleri bu kurla hesaplanır. Boş/0: Elmas ile ödeme ve ödeme talebi kapalı. (Üye yalnızca satın aldığı, iade edilebilir Elmas ile öder.)',
          helperMaxLines: 3,
        ),
      ),
      const SizedBox(height: 12),
      if (_primary)
        FilledButton(
          onPressed: b
              ? null
              : () {
                  final p = _num(_pct.text), r = _num(_rate.text.isEmpty ? '0' : _rate.text);
                  if (p == null || r == null) {
                    snack('Sayıları kontrol et.');
                    return;
                  }
                  run('cfg', () => BusinessService.instance.setConfig(commissionPct: p, hpToTl: r), 'Kaydedildi.', _load);
                },
          child: const Text('Kaydet'),
        ),
      const Divider(height: 36),
      const Text('İşletmeye özel komisyon', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
      const SizedBox(height: 6),
      TextField(controller: _ovUid, enabled: _primary, decoration: const InputDecoration(labelText: 'İşletme hesabının kullanıcı kimliği (uid)')),
      TextField(controller: _ovPct, enabled: _primary, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Komisyon (%)')),
      const SizedBox(height: 8),
      if (_primary)
        Wrap(spacing: 8, children: [
          OutlinedButton(
            onPressed: b
                ? null
                : () {
                    final p = _num(_ovPct.text);
                    if (_ovUid.text.trim().isEmpty || p == null) {
                      snack('Kimlik ve oran gir.');
                      return;
                    }
                    run('ov', () => BusinessService.instance.setConfig(overrideUid: _ovUid.text.trim(), overridePct: p), 'Özel oran kaydedildi.', _load);
                  },
            child: const Text('Özel oranı kaydet'),
          ),
          TextButton(
            onPressed: b || _ovUid.text.trim().isEmpty
                ? null
                : () => run('ov', () => BusinessService.instance.setConfig(overrideUid: _ovUid.text.trim(), clearOverride: true), 'Özel oran kaldırıldı.', _load),
            child: const Text('Kaldır'),
          ),
        ]),
    ]);
  }
}
