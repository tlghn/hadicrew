
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hadi/core/money.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/data/firebase_services.dart' show kFunctionsRegion;
import 'package:hadi/data/models.dart';
import 'package:hadi/data/service_pricing.dart' show newRequestId;
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/common.dart';
import 'package:hadi/widgets/hadi_sheet.dart';
import 'package:hadi/data/callables.dart';
import 'package:hadi/core/ui_gate.dart';

/// Elmas 💎 / Akçe 🪙 ekonomisi yönetimi (`economyAdmin`, functions/src/economy.ts):
/// hoş geldin hediyesi (`config/economy.welcomeHp` → Akçe × kur, `welcomePurchasedHp` → Elmas) ve üyeye Elmas/Akçe
/// yükleme / düşme. Kurucular için hiçbir şey ücretsiz değildir (20 Ekim 2026). Kuruculara yalnızca ana kurucu yükler
/// (her zaman Elmas); geçici kuruculara haftalık Elmas limiti tanımlanabilir (Kurucular sekmesi › Elmas).
class HpEconomyApi {
  const HpEconomyApi(this.demo);
  final bool demo;

  Future<Map<String, Object?>> _call(Map<String, Object?> data) async {
    if (demo) {
      return switch (data['op']) {
        'get' => {'welcomeHp': 1000, 'welcomePurchasedHp': 100, 'referralRewardPct': 5, 'defaults': {'welcomeHp': 1000, 'welcomePurchasedHp': 100, 'referralRewardPct': 5}, 'canEdit': true, 'canEditWelcome': true},
        'history' => {'items': const []},
        'creditLog' => {'items': const [], 'nextCursor': null, 'total': {'sum': 0, 'count': 0}},
        'creditLogCsv' => {'csv': '\ufeffTarih;Üye;Birim;Tutar\r\n', 'count': 0, 'sum': 0},
        'grant' => {'ok': true, 'balance': 0, 'amount': data['amount'], 'cat': data['cat'], 'breakdown': const {'purchased': 0, 'test': 0, 'promo': 0, 'collected': 0, 'akce': 0}},
        'balance' => {'breakdown': const {'purchased': 0, 'test': 0, 'promo': 0, 'collected': 5942, 'akce': 0}},
        'convert' => {'ok': true, 'converted': 5942, 'breakdown': const {'purchased': 0, 'test': 5942, 'promo': 0, 'collected': 0, 'akce': 0}},
        'promoBudget' => {'on': false, 'cap': 0, 'granted': 0, 'paid': 0, 'remaining': 0, 'month': '', 'canEdit': true},
        _ => {'ok': true, ...data},
      };
    }
    try {
      final r = await FirebaseFunctions.instanceFor(region: kFunctionsRegion)
          .hadiCallable('economyAdmin', options: HttpsCallableOptions(timeout: const Duration(seconds: 120)))
          .call(data);
      final d = r.data;
      return d is Map ? d.map((k, v) => MapEntry('$k', v as Object?)) : const {};
    } on FirebaseFunctionsException catch (e) {
      throw AppFailure(e.message ?? 'İşlem tamamlanamadı (${e.code}).');
    }
  }

  Future<Map<String, Object?>> get() => _call({'op': 'get'});
  /// Hoş geldin hediyesi (yalnızca ana kurucu): [gift] Elmas karşılığı Akçe (üyeye gift × kur 🪙), [purchased] Elmas 💎.
  Future<void> setWelcome(int gift, int purchased) => _call({'op': 'set', 'welcomeHp': gift, 'welcomePurchasedHp': purchased});
  /// İlk kayıt hediyesi (21 Ekim 2026; yalnızca ana kurucu, gerekçeli): üç ayrı tutar.
  /// [paidElmas] Elmas — satın alınmış sayılır ([paidFunding] 'test' | 'promo'), [bonusElmas] Elmas — toplanan, [akce] Akçe.
  Future<Map<String, Object?>> setWelcome3({required int paidElmas, required String paidFunding, required int bonusElmas, required int akce, required String reason}) =>
      _call({'op': 'set', 'welcome': {'paidElmas': paidElmas, 'paidFunding': paidFunding, 'bonusElmas': bonusElmas, 'akce': akce}, 'reason': reason});
  /// Üyenin Elmas kategorileri: { breakdown: { purchased, test, promo, collected, locked, akce } }.
  Future<Map<String, Object?>> balance(String uid) => _call({'op': 'balance', 'uid': uid});
  /// Toplanan (bonus) Elmas'ı "satın alınmış sayılır" partisine çevir ([amount] null = tamamı).
  Future<Map<String, Object?>> convert(String uid, String funding, String reason, {int? amount}) =>
      _call({'op': 'convert', 'uid': uid, 'funding': funding, 'reason': reason, 'amount': ?amount});
  /// Promosyon bütçesi: { on, cap, granted, paid, remaining, month, warning, canEdit }.
  Future<Map<String, Object?>> promoBudget() => _call({'op': 'promoBudget'});
  Future<void> setPromoBudget(int monthlyCapElmas, String reason) => _call({'op': 'setPromoBudget', 'monthlyCapElmas': monthlyCapElmas, 'reason': reason});
  /// Davet ödülü yüzdesi (yalnızca ana kurucu).
  Future<void> setReferralPct(double pct) => _call({'op': 'set', 'referralRewardPct': pct});
  /// [cur]: 'elmas' ya da 'akce' (zorunlu; kuruculara sunucu her zaman Elmas uygular). Eski sunucu için `wallet` de
  /// gönderilir (elmas → purchased, akce → gift).
  /// [cat] (21 Ekim 2026): 'elmas_test' | 'elmas_promo' | 'elmas' (toplanan) | 'akce'.
  Future<Map<String, Object?>> grant(String uid, int amount, String reason, {required String cur, String? cat}) => _call({
        'op': 'grant',
        'uid': uid,
        'amount': amount,
        'reason': reason,
        'cur': cur,
        'cat': ?cat,
        'currency': cur,
        'wallet': cur == 'akce' ? 'gift' : 'purchased',
        'requestId': newRequestId(),
      });
  /// Ana kurucu: kurucunun Elmas durumu (bakiye, kalan kurucu yüklemesi, haftalık limit, sonraki yükleme).
  Future<Map<String, Object?>> founderHp(String uid) => _call({'op': 'founderHp', 'uid': uid});
  /// Ana kurucu: geçici kurucunun haftalık Elmas limiti (0 = kapalı); her pazartesi 00:00 (TR) yüklenir.
  Future<Map<String, Object?>> setFounderLimit(String uid, int weeklyLimit, String reason) =>
      _call({'op': 'setFounderLimit', 'uid': uid, 'weeklyLimit': weeklyLimit, 'reason': reason});
  Future<List<Map<String, Object?>>> history({String? uid, int limit = 50}) async {
    final r = await _call({'op': 'history', 'limit': limit, if (uid != null) 'uid': uid});
    final items = r['items'];
    return items is List ? [for (final x in items) if (x is Map) x.map((k, v) => MapEntry('$k', v as Object?))] : const [];
  }

  /// Satın almasız Elmas/Akçe yüklemeleri (hp_credit_log): { items, nextCursor, total? }.
  Future<Map<String, Object?>> creditLog(CreditLogFilter f, {String? cursor, int limit = 50}) =>
      _call({'op': 'creditLog', 'limit': limit, ...f.toMap(), if (cursor != null) 'cursor': cursor});
  Future<Map<String, Object?>> creditLogCsv(CreditLogFilter f) => _call({'op': 'creditLogCsv', ...f.toMap()});
}

/// Satın almasız yüklemeler filtresi (tarihler Türkiye saatiyle gün başı/sonu).
class CreditLogFilter {
  const CreditLogFilter({this.from, this.to, this.kind, this.uid, this.memberName});
  final DateTime? from, to; // yalnızca gün (yerel tarih bileşenleri)
  final String? kind, uid, memberName;

  static int _trMs(DateTime d, {bool end = false}) =>
      DateTime.utc(d.year, d.month, d.day, end ? 23 : 0, end ? 59 : 0, end ? 59 : 0, end ? 999 : 0).millisecondsSinceEpoch - 3 * 3600 * 1000;

  Map<String, Object?> toMap() => {
        if (from != null) 'from': _trMs(from!),
        if (to != null) 'to': _trMs(to!, end: true),
        if (kind != null) 'kind': kind,
        if (uid != null) 'uid': uid,
      };

  CreditLogFilter copyWith({DateTime? from, DateTime? to, String? kind, String? uid, String? memberName, bool clearDates = false, bool clearKind = false, bool clearMember = false}) =>
      CreditLogFilter(
        from: clearDates ? null : (from ?? this.from),
        to: clearDates ? null : (to ?? this.to),
        kind: clearKind ? null : (kind ?? this.kind),
        uid: clearMember ? null : (uid ?? this.uid),
        memberName: clearMember ? null : (memberName ?? this.memberName),
      );
}

const kCreditKinds = <String, String>{
  'admin_grant': 'Yönetim yüklemesi',
  'welcome': 'Hoş geldin',
  'founder_gift': 'Kurucu hediyesi',
  'gift_income': 'Hediye geliri',
  'tournament_prize': 'Turnuva ödülü',
  'bank_interest': 'Banka bonusu (eski)',
  'refund': 'İade',
  'reward': 'Ödül/kazanç',
  'referral_reward': 'Davet ödülü',
  'campaign_bonus': 'Web kampanya bonusu',
  'other': 'Diğer',
};

String _two(int n) => n.toString().padLeft(2, '0');

/// dd.MM.yyyy HH:mm:ss (Türkiye saati, UTC+3).
String trTimestamp(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).add(const Duration(hours: 3));
  return '${_two(t.day)}.${_two(t.month)}.${t.year} ${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
}

HpEconomyApi _api(BuildContext context) => HpEconomyApi(SessionScope.read(context).services.isDemo);

/// Bir üyeye Elmas/Akçe yükleme / düşme (kurucu paneli › Ekonomi ve kurucunun profil menüsündeki "Elmas/Akçe yükle").
/// Başarılı olursa true döner.
Future<bool?> showHpGrantSheet(BuildContext context, {required String uid, required String name}) => showHadiSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (_) => _GrantSheet(uid: uid, name: name),
    );

/// Yükleme kategorileri (21 Ekim 2026; functions/src/economy.ts › grant `cat`).
const kGrantCats = <(String, String, String)>[
  ('elmas_test', '💎 Elmas — satın alınmış sayılır (test)',
      'Satın alınan Elmas gereken her yerde (ücretli bilet, sipariş, kurye, bağış) geçer; üyeye iade edilmez ve işletmeye/kuryeye/kuruma ödemeye dönüşmez ("Test bakiyesinden — ödemeye dönüşmez").'),
  ('elmas_promo', '💎 Elmas — satın alınmış sayılır (promosyon, HADİ öder)',
      'Satın alınan Elmas gibi geçer; harcandığı işletmeye/kuryeye/kuruma HADİ TL öder (aylık promosyon bütçesinden). Yalnızca ana kurucu.'),
  ('elmas', '💎 Elmas — toplanan (bonus)', 'Platform hizmetlerinde geçer; iade edilmez ve TL\'ye dönen ödemelerde (bilet, sipariş, bağış) kullanılamaz.'),
  ('akce', '🪙 Akçe', 'Yalnızca Akçe kabul eden hizmetlerde (hediye, öne çıkarma…) harcanır.'),
];

/// Üyenin Elmas kategorileri + Akçe (sunucu currency.breakdownOf).
class WalletBreakdownView extends StatelessWidget {
  const WalletBreakdownView({super.key, required this.b});
  final Map<String, Object?> b;

  @override
  Widget build(BuildContext context) {
    int n(String k) => (b[k] as num?)?.toInt() ?? 0;
    final rows = <(String, String)>[
      ('Satın alınan', elmasText(n('purchased'))),
      ('Hediye-test (satın alınmış sayılır)', elmasText(n('test'))),
      ('Promosyon (HADİ öder)', elmasText(n('promo'))),
      ('Toplanan', elmasText(n('collected'))),
      if (n('locked') > 0) ('Kilitli Elmas', elmasText(n('locked'))),
      ('Akçe', akceText(n('akce'))),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: HadiColors.gold.withValues(alpha: .08), borderRadius: BorderRadius.circular(14), border: Border.all(color: HadiColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Üyenin bakiyesi (kategoriler)', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Expanded(child: Text(r.$1, style: TextStyle(color: HadiColors.ink2))),
              Text(r.$2, style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ),
      ]),
    );
  }
}

class _GrantSheet extends StatefulWidget {
  const _GrantSheet({required this.uid, required this.name});
  final String uid, name;

  @override
  State<_GrantSheet> createState() => _GrantSheetState();
}

class _GrantSheetState extends State<_GrantSheet> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  bool _debit = false, _busy = false, _done = false;
  /// Zorunlu kategori: 'elmas_test' | 'elmas_promo' | 'elmas' | 'akce' (bilinçli seçilsin diye varsayılan yok).
  String? _cat;
  String? _error;
  Map<String, Object?>? _breakdown;
  Map<String, Object?>? _promo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInfo());
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _loadInfo() async {
    final api = _api(context);
    try {
      final r = await api.balance(widget.uid);
      if (mounted && r['breakdown'] is Map) setState(() => _breakdown = (r['breakdown'] as Map).map((k, v) => MapEntry('$k', v as Object?)));
    } on AppFailure catch (_) {/* döküm gösterilmez */}
    try {
      final p = await api.promoBudget();
      if (mounted) setState(() => _promo = p);
    } on AppFailure catch (_) {/* promosyon seçeneği kapalı kalır */}
  }

  bool get _promoOn => _promo?['on'] == true && ((_promo?['remaining'] as num?)?.toInt() ?? 0) > 0;
  bool _catEnabled(String c) => _debit ? (c == 'elmas' || c == 'akce') : (c != 'elmas_promo' || _promoOn);

  String? _validReason() {
    final reason = _reason.text.trim();
    if (reason.length < 10) {
      setState(() => _error = 'En az 10 karakterlik bir gerekçe yaz; kim, ne zaman ve neden kayda geçer.');
      return null;
    }
    return reason;
  }

  Future<void> _submit() async {
    final n = int.tryParse(_amount.text.trim());
    if (n == null || n <= 0 || n > 100000) {
      setState(() => _error = 'Tutar 1–100000 arası tam sayı olmalı.');
      return;
    }
    final reason = _validReason();
    if (reason == null) return;
    final cat = _cat;
    if (cat == null || !_catEnabled(cat)) {
      setState(() => _error = 'Kategoriyi seç.');
      return;
    }
    final cur = cat == 'akce' ? 'akce' : 'elmas';
    final amount = _debit ? -n : n;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _api(context).grant(widget.uid, amount, reason, cur: cur, cat: cat);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final used = '${r['cur'] ?? cur}' == 'akce' ? 'akce' : 'elmas';
      String fmt(int v) => used == 'akce' ? akceText(v) : elmasText(v);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text('${widget.name}: ${amount > 0 ? '+' : ''}${fmt(amount)}${r['warning'] is String ? ' · ${r['warning']}' : ''}'),
      ));
      setState(() {
        _done = true;
        if (r['breakdown'] is Map) _breakdown = (r['breakdown'] as Map).map((k, v) => MapEntry('$k', v as Object?));
      });
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Tek seferlik düzeltme: üyenin toplanan (bonus) Elmas'ını "satın alınmış sayılır (test)" kategorisine çevirir.
  Future<void> _convert() async {
    final reason = _validReason();
    if (reason == null) return;
    final n = int.tryParse(_amount.text.trim());
    final collected = (_breakdown?['collected'] as num?)?.toInt() ?? 0;
    final amount = n != null && n > 0 ? n : null;
    final ok = await uiOnce(context, () => showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Kategoriyi çevir'),
        content: Text('${widget.name} üyesinin ${elmasText(amount ?? collected)} toplanan Elmas\'ı "satın alınmış sayılır (test)" olacak. '
            'Toplam Elmas değişmez. Bu Elmas ücretli hizmetlerde kullanılabilir ama hiçbir yoldan TL\'ye dönüşmez.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Çevir')),
        ],
      ),
    ));
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _api(context).convert(widget.uid, 'test', reason, amount: amount);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('${widget.name}: ${elmasText((r['converted'] as num?)?.toInt() ?? 0)} → satın alınmış sayılır (test)')));
      setState(() {
        _done = true;
        if (r['breakdown'] is Map) _breakdown = (r['breakdown'] as Map).map((k, v) => MapEntry('$k', v as Object?));
      });
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _catTile((String, String, String) c) {
    final enabled = _catEnabled(c.$1);
    final sel = _cat == c.$1;
    final promo = c.$1 == 'elmas_promo';
    final rem = (_promo?['remaining'] as num?)?.toInt();
    final sub = promo && !_debit
        ? (_promo?['on'] != true
            ? 'Kapalı: Hizmetler › "Promosyon Elmas\'ı (HADİ öder)" gizli.'
            : '${c.$3}\nBu ay kalan bütçe: ${rem == null ? '—' : elmasText(rem)}. ${_promo?['warning'] ?? 'Bu bakiye işletmelere HADİ tarafından TL olarak ödenir.'}')
        : c.$3;
    return ListTile(
      enabled: enabled,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(sel ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: sel ? HadiColors.iletisim : HadiColors.ink3),
      title: Text(c.$2, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(sub, style: TextStyle(fontSize: 12, height: 1.3, color: promo && sel ? HadiColors.text(HadiColors.error) : null)),
      onTap: enabled ? () => setState(() => _cat = c.$1) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final collected = (_breakdown?['collected'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Elmas / Akçe yükle', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(widget.name, style: TextStyle(color: HadiColors.ink2, fontWeight: FontWeight.w700)),
        if (_breakdown != null) ...[
          const SizedBox(height: 10),
          WalletBreakdownView(b: _breakdown!),
        ],
        if (_done) ...[
          const SizedBox(height: 12),
          PrimaryButton(label: 'Tamam', icon: Icons.check_rounded, onPressed: () => Navigator.pop(context, true)),
        ] else ...[
          const SizedBox(height: 14),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, icon: Icon(Icons.add_rounded), label: FittedBox(fit: BoxFit.scaleDown, child: Text('Yükle', maxLines: 1))),
              ButtonSegment(value: true, icon: Icon(Icons.remove_rounded), label: FittedBox(fit: BoxFit.scaleDown, child: Text('Düş', maxLines: 1))),
            ],
            selected: {_debit},
            onSelectionChanged: (s) => setState(() {
              _debit = s.first;
              if (_cat != null && !_catEnabled(_cat!)) _cat = null;
            }),
          ),
          const SizedBox(height: 12),
          const Text('Kategori (zorunlu)', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          for (final c in kGrantCats) _catTile(c),
          if (_debit)
            Text('Düşme önce toplanan, sonra satın alınmış sayılan, en son satın alınan Elmas\'tan yapılır.', style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
          const SizedBox(height: 8),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: 'Tutar', suffixText: _cat == 'akce' ? kAkce : _cat == null ? null : kElmas),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _reason,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Gerekçe (zorunlu, en az 10 karakter)', hintText: 'ör. Ücretli bilet akışını test etmesi için'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: TextStyle(color: HadiColors.text(HadiColors.error), fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 12),
          PrimaryButton(label: _debit ? 'Düş' : 'Yükle', icon: Icons.check_rounded, loading: _busy, onPressed: _submit),
          if (!_debit && collected > 0) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _convert,
              icon: const Icon(Icons.swap_horiz_rounded),
              label: Text('Toplanan Elmas\'ı "satın alınmış sayılır (test)"a çevir (${elmasText(collected)})', textAlign: TextAlign.center),
            ),
            const SizedBox(height: 4),
            Text('Tutar boşsa tamamı çevrilir. Gerekçe zorunlu; işlem kayda geçer. Kendi hesabında yalnızca ana kurucu yapabilir.',
                style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
          ],
        ],
      ])),
    );
  }
}
