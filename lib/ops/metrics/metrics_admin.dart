import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:hadi/core/money.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/data/firebase_services.dart' show kFunctionsRegion;
import 'package:hadi/data/models.dart';
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/common.dart';
import 'package:hadi_crew/ops/admin/hp_economy_admin.dart' show trTimestamp;
import 'package:hadi_crew/ops/admin/roles_admin.dart' show pickMemberForRole;
import 'live_cost_panel.dart';
import 'package:hadi/data/callables.dart';
import 'package:hadi/core/app_lock.dart';

/// Kurucu paneli › İstatistik (`metrics` callable, functions/src/metrics.ts) — YALNIZCA ana kurucu.
///
/// Genel bakış: üyeler (toplam, yeni, DAU/WAU/MAU), adaylar, Elmas/Akçe ekonomisi, içerik, mesajlaşma, etkinlikler,
/// canlı yayın, oyunlar, destek/şikayet, özellik kullanım sıralaması ve haftalık kohort.
/// Üye ayrıntısı: işletimsel sayılar + (YALNIZCA açık rıza verdiyse) kullanım analitiği. Her görüntüleme kayda geçer.

typedef _J = Map<String, Object?>;

_J _m(Object? v) => v is Map ? v.map((k, x) => MapEntry('$k', x as Object?)) : const {};
List<Object?> _l(Object? v) => v is List ? v : const [];
num? _n(Object? v) => v is num ? v : null;
int _i(Object? v) => v is num ? v.toInt() : 0;
String _two(int n) => n.toString().padLeft(2, '0');

/// Binlik ayraçlı sayı (1.234.567 / 12,5). null → "—".
String _fmt(num? v, {int dec = 0}) {
  if (v == null) return '—';
  final neg = v < 0;
  final s = dec > 0 ? v.abs().toStringAsFixed(dec) : v.abs().round().toString();
  final parts = s.split('.');
  final ip = parts[0];
  final b = StringBuffer();
  for (var i = 0; i < ip.length; i++) {
    if (i > 0 && (ip.length - i) % 3 == 0) b.write('.');
    b.write(ip[i]);
  }
  final frac = parts.length > 1 && parts[1].replaceAll('0', '').isNotEmpty ? ',${parts[1]}' : '';
  return '${neg ? '-' : ''}$b$frac';
}

/// "2026-10-16" → "16.10"
String _dd(String key) => key.length >= 10 ? '${key.substring(8, 10)}.${key.substring(5, 7)}' : key;

String _msDate(Object? v) => v is num ? trTimestamp(v.toInt()).substring(0, 16) : '—';

const _kRanges = <String, String>{'7d': '7 gün', '30d': '30 gün', '90d': '90 gün', 'all': 'Tümü'};

const _kMsgTypes = <String, String>{
  'text': 'Yazı', 'image': 'Fotoğraf', 'voice': 'Sesli mesaj', 'video': 'Video', 'gif': 'GIF', 'location': 'Konum',
  'live': 'Canlı konum', 'poll': 'Anket', 'post': 'Gönderi paylaşımı', 'toy': 'Oyuncak', 'game': 'Sohbet oyunu',
  'ss_request': 'Ekran görüntüsü isteği', 'invite': 'Davet', 'system': 'Sistem',
};

const _kLedgerTypes = <String, String>{
  'purchase': 'Satın alma', 'welcome': 'Hoş geldin', 'earned': 'Kazanç', 'admin_grant': 'Yönetim yüklemesi', 'admin_debit': 'Yönetim düşümü',
  'gift_sent': 'Gönderilen hediye', 'gift_received': 'Gelen hediye', 'gift_refund': 'Hediye iadesi', 'live_gift_income': 'Yayın hediye geliri',
  'event_ticket': 'Etkinlik bileti', 'event_refund': 'Bilet iadesi', 'service': 'Ücretli hizmet', 'service_refund': 'Hizmet iadesi',
  'promote': 'Tanıtım', 'promote_refund': 'Tanıtım iadesi', 'live_deposit': 'Yayın depozitosu', 'live_topup': 'Yayın uzatma',
  'live_boost': 'Yayın öne çıkarma', 'now_boost': 'Şimdi HADİ öne çıkarma', 'live_refund': 'Yayın iadesi', 'donation': 'Bağış',
  'bank_deposit': 'Bankaya yatırma', 'bank_withdraw': 'Bankadan çekme', 'bank_interest': 'Banka bonusu (eski)',
  'verified_week': 'Doğrulanmış hesap (hafta)',
  'convert': 'Akçe\'ye çevirme', 'market_buy': 'Akçe Market alımı', 'market_sell': 'Akçe Market satışı', 'market_fee': 'Market kesintisi',
  'purchase_refund': 'Satın alma iadesi', 'clawback': 'Ters ibraz', 'campaign_bonus': 'Kampanya bonusu', 'campaign_bonus_clawback': 'Kampanya bonusu geri alma', 'game': 'Oyun', 'game_reward': 'Oyun ödülü',
};

const _kCreditKinds = <String, String>{
  'admin_grant': 'Yönetim yüklemesi', 'welcome': 'Hoş geldin', 'founder_gift': 'Kurucu hediyesi', 'gift_income': 'Hediye geliri',
  'tournament_prize': 'Turnuva ödülü', 'bank_interest': 'Banka bonusu (eski)', 'refund': 'İade', 'reward': 'Ödül/kazanç', 'referral_reward': 'Davet ödülü', 'campaign_bonus': 'Web kampanya bonusu', 'other': 'Diğer',
};

const _kAnEvents = <String, String>{
  'app_open': 'Uygulama açılışı', 'app_bg': 'Arka plana alma', 'app_fg': 'Öne getirme', 'screen_view': 'Ekran görüntüleme',
  'screen_time': 'Ekran süresi', 'content_watch': 'İçerik izleme', 'post_impression': 'Gönderi gösterimi', 'post_open': 'Gönderi açma',
  'tap': 'Dokunma', 'search': 'Arama', 'share_open': 'Paylaşma', 'profile_view': 'Profil görüntüleme', 'error': 'Hata',
  'ad_impression': 'Reklam gösterimi', 'ad_click': 'Reklam tıklama', 'promo_impression': 'Tanıtım gösterimi', 'promo_click': 'Tanıtım tıklama',
};

// =============================================================================
// API
// =============================================================================

class _MetricsApi {
  const _MetricsApi(this.demo);
  final bool demo;

  Future<_J> _call(_J data) async {
    if (demo) return _demo(data);
    try {
      final r = await FirebaseFunctions.instanceFor(region: kFunctionsRegion)
          .hadiCallable('metrics', options: HttpsCallableOptions(timeout: const Duration(seconds: 540)))
          .call(data);
      return _m(r.data);
    } on FirebaseFunctionsException catch (e) {
      throw AppFailure(switch (e.code) {
        // Sunucu kodu yetkisizliği "permission-denied" ile bildirir; "unauthenticated" Cloud Run'ın isteği
        // fonksiyona hiç ulaştırmadığı anlamına gelir (herkese açık çağırma izni eksik ya da oturum süresi doldu).
        'unauthenticated' => 'İstatistik servisine ulaşılamadı: sunucuda bu fonksiyonun çağırma izni eksik '
            '(ilk kurulumu kota hatasıyla yarım kalmış). Bir sonraki DEPLOY izni otomatik onarır. '
            'Sorun sürerse çıkış yapıp yeniden giriş yap.',
        'not-found' => 'İstatistik servisi sunucuda bulunamadı (henüz deploy edilmemiş).',
        'permission-denied' => e.message ?? 'Bu ekran yalnızca ana kurucuya açık.',
        'deadline-exceeded' => 'İstatistik hesaplaması zaman aşımına uğradı. Daha kısa bir aralık seçip tekrar dene.',
        'unavailable' => 'Sunucuya şu an ulaşılamıyor. İnternet bağlantını kontrol edip tekrar dene.',
        _ => e.message ?? 'İstatistikler alınamadı (${e.code}).',
      });
    }
  }

  Future<_J> overview(String range, {bool fresh = false}) => _call({'op': 'overview', 'range': range, 'fresh': fresh});
  Future<_J> member(String uid, {bool fresh = false}) => _call({'op': 'member', 'uid': uid, 'fresh': fresh});
  Future<_J> backfill(int days) => _call({'op': 'backfill', 'days': days});

  static _J _demo(_J data) {
    final rnd = math.Random(7);
    if (data['op'] == 'backfill') return {'ok': true, 'done': 0, 'remaining': 0};
    if (data['op'] == 'member') {
      return {
        'uid': data['uid'],
        'profile': {'name': 'Demo Üye', 'username': 'demo', 'plan': 'premium', 'role': null, 'badges': ['kurucu'], 'joinedAt': DateTime.now().millisecondsSinceEpoch - 86400000 * 40, 'level': 4},
        'application': {'status': 'approved', 'identityVerified': true},
        'lastSeen': DateTime.now().millisecondsSinceEpoch - 3600000,
        'counts': {'posts': 12, 'stories': 4, 'messages': 340, 'comments': 25, 'likes': 80, 'eventsJoined': 3, 'games': 9, 'livesHosted': 1, 'tickets': 0, 'giftsSent': 2, 'reportsBy': 0, 'reportsAgainst': 0},
        'wallet': {'balance': 120, 'spentHp': 300, 'purchasedHp': 400, 'purchasedTl': 99.9, 'byType': const [], 'monthly': const [], 'services': const [], 'purchases': const [], 'creditByKind': const {}},
        'consent': {'analytics': false},
        'analytics': null,
        'cachedAt': DateTime.now().millisecondsSinceEpoch,
      };
    }
    final n = switch (data['range']) { '7d' => 7, '90d' => 90, 'all' => 120, _ => 30 };
    final now = DateTime.now();
    final days = [for (var i = n - 1; i >= 0; i--) now.subtract(Duration(days: i)).toIso8601String().substring(0, 10)];
    List<int> s(int base) => [for (var i = 0; i < n; i++) base + rnd.nextInt(base + 1)];
    return {
      'range': data['range'], 'days': n, 'missing': 0, 'generatedAt': now.millisecondsSinceEpoch, 'cachedAt': now.millisecondsSinceEpoch,
      'members': {'total': 1240, 'newInRange': 86, 'dau': 310, 'wau': 640, 'mau': 980, 'premium': 140, 'verified': 1100, 'consented': 720, 'founders': 3, 'admins': 4, 'moderators': 6},
      'candidates': {'pending': 18, 'approved': 1240, 'rejected': 90, 'avgDecisionHours': 9.5, 'inRange': {'submitted': 110, 'approved': 86, 'rejected': 7}},
      'hp': {'purchasedHp': 24000, 'purchasedTl': 5400.5, 'purchases': 140, 'spentHp': 19800, 'credits': 6000, 'circulating': 56000, 'holders': 900,
        'spentByType': [{'key': 'service', 'label': 'Ücretli hizmetler', 'hp': 8000}, {'key': 'gift_sent', 'label': 'Hediyeler', 'hp': 6000}, {'key': 'event_ticket', 'label': 'Etkinlik biletleri', 'hp': 5800}],
        'services': [{'key': 'ai_photo_edit', 'name': 'Yapay zekâ fotoğraf', 'n': 120, 'hp': 3600}],
        'creditByKind': {'welcome': 3000, 'reward': 2000, 'refund': 1000},
        'topSpenders': [{'uid': 'demo1', 'name': 'Ayşe Y.', 'username': 'ayse', 'hp': 1200}]},
      'content': {'posts': 420, 'reels': 60, 'replies': 300, 'stories': 210, 'comments': 1300},
      'messaging': {'total': 32000, 'byType': {'text': 28000, 'image': 2500, 'voice': 900, 'gif': 600}},
      'events': {'created': 12, 'joins': 340, 'revenueHp': 5800, 'held': 9, 'upcoming': 4, 'fillRate': 78.5},
      'live': {'streams': 40, 'minutes': 2200, 'giftsHp': 3100, 'liveNow': 1},
      'games': {'matches': 1800, 'byGame': {'okey101': 700, 'tavla': 500, 'batak': 600}, 'tournaments': 8, 'tournamentsOpen': 2},
      'support': {'tickets': 22, 'open': 3, 'inProgress': 1},
      'reports': {'inRange': 15, 'open': 2},
      'usage': {'sessions': 21000, 'avgSessionMin': 7.4, 'events': [{'key': 'screen_view', 'count': 120000}, {'key': 'app_open', 'count': 22000}]},
      'features': [{'label': 'Mesaj gönderme', 'count': 32000, 'source': 'işlem'}, {'label': 'feed', 'count': 21000, 'source': 'ekran'}, {'label': 'Oyun oynama', 'count': 1800, 'source': 'işlem'}],
      'series': {'days': days, 'newMembers': s(2), 'dau': s(250), 'appsIn': s(3), 'appsOk': s(2), 'appsNo': s(0), 'posts': s(12), 'stories': s(6), 'comments': s(40),
        'msgs': s(900), 'hpBought': s(600), 'hpSpent': s(500), 'credits': s(150), 'eventJoins': s(10), 'liveMin': s(60), 'matches': s(50), 'tickets': s(0), 'reports': s(0)},
      'cohorts': {'rows': [{'week': days.first, 'size': 20, 'retention': [100, 70, 55, 50]}]},
    };
  }
}

_MetricsApi _api(BuildContext context) => _MetricsApi(SessionScope.read(context).services.isDemo);

void _snack(BuildContext context, String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

/// CSV (Excel uyumlu: UTF-8 BOM, ";" ayraç) paylaşım sayfasıyla dışa aktarılır.
Future<void> _shareCsv(BuildContext anchor, String name, String subject, List<List<Object?>> rows) async {
  final box = anchor.findRenderObject() as RenderBox?;
  final origin = box == null || !box.hasSize ? null : box.localToGlobal(Offset.zero) & box.size;
  String cell(Object? v) {
    final s = v == null ? '' : '$v';
    return s.contains(RegExp('[;"\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  final csv = '﻿${rows.map((r) => r.map(cell).join(';')).join('\r\n')}\r\n';
  await AppLock.instance.external(() => SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(utf8.encode(csv), mimeType: 'text/csv', name: name)],
    subject: subject,
    sharePositionOrigin: origin,
  )));
}

String _stamp() {
  final n = DateTime.now();
  return '${n.year}${_two(n.month)}${_two(n.day)}-${_two(n.hour)}${_two(n.minute)}';
}

// =============================================================================
// Genel bakış
// =============================================================================

class MetricsAdminTab extends StatefulWidget {
  const MetricsAdminTab({super.key});

  @override
  State<MetricsAdminTab> createState() => _MetricsAdminTabState();
}

class _MetricsAdminTabState extends State<MetricsAdminTab> with AutomaticKeepAliveClientMixin {
  String _range = '30d';
  _J? _d;
  String? _error;
  bool _loading = true, _busy = false;
  int _seq = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool fresh = false}) async {
    final my = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await _api(context).overview(_range, fresh: fresh);
      if (mounted && my == _seq) setState(() => _d = d);
    } on AppFailure catch (e) {
      if (mounted && my == _seq) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && my == _seq) setState(() => _error = 'İstatistikler alınamadı.');
    } finally {
      if (mounted && my == _seq) setState(() => _loading = false);
    }
  }

  Future<void> _backfill() async {
    setState(() => _busy = true);
    try {
      final api = _api(context);
      var left = 1, total = 0, rounds = 0;
      while (left > 0 && rounds < 4 && mounted) {
        final r = await api.backfill(_range == '7d' ? 7 : _range == '30d' ? 30 : 120);
        total += _i(r['done']);
        left = _i(r['remaining']);
        rounds++;
      }
      if (mounted) _snack(context, '$total günün toplamı hesaplandı${left > 0 ? ' ($left gün kaldı; yeniden dene)' : ''}.');
      await _load(fresh: true);
    } on AppFailure catch (e) {
      if (mounted) _snack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openMember([String? uid, String? name]) async {
    var id = uid, label = name;
    if (id == null) {
      final m = await pickMemberForRole(context, title: 'Üye istatistikleri');
      if (m == null) return;
      id = m.uid;
      label = m.username == null || m.username!.isEmpty ? m.fullName : '${m.fullName} (@${m.username})';
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MemberMetricsScreen(uid: id!, title: label ?? 'Üye')));
  }

  Future<void> _export(BuildContext anchor) async {
    final d = _d;
    if (d == null) return;
    final rows = <List<Object?>>[
      ['HADİ İstatistik', _kRanges[_range], 'Oluşturulma', _msDate(d['generatedAt'])],
      [],
      ['Bölüm', 'Ölçü', 'Değer'],
    ];
    void sec(String name, Object? map) {
      for (final e in _m(map).entries) {
        if (e.value is num || e.value == null) rows.add([name, e.key, e.value]);
      }
    }

    sec('Üyeler', d['members']);
    sec('Adaylar', d['candidates']);
    sec('Adaylar (aralık)', _m(d['candidates'])['inRange']);
    sec('Elmas', d['hp']);
    sec('İçerik', d['content']);
    sec('Mesaj', d['messaging']);
    sec('Mesaj türleri', _m(d['messaging'])['byType']);
    sec('Etkinlik', d['events']);
    sec('Canlı yayın', d['live']);
    sec('Oyun', d['games']);
    sec('Oyunlar', _m(d['games'])['byGame']);
    sec('Destek', d['support']);
    sec('Şikayet', d['reports']);
    sec('Kullanım', d['usage']);
    final s = _m(d['series']);
    final keys = s.keys.where((k) => k != 'days').toList();
    rows
      ..add([])
      ..add(['Gün', ...keys]);
    final days = _l(s['days']);
    for (var i = 0; i < days.length; i++) {
      final row = <Object?>[days[i]];
      for (final k in keys) {
        final l = _l(s[k]);
        row.add(i < l.length ? l[i] : null);
      }
      rows.add(row);
    }
    rows
      ..add([])
      ..add(['Özellik', 'Kaynak', 'Kullanım']);
    for (final f in _l(d['features'])) {
      final m = _m(f);
      rows.add([m['label'], m['source'], m['count']]);
    }
    rows
      ..add([])
      ..add(['En çok harcayan', 'Kullanıcı adı', 'Elmas', 'uid']);
    for (final x in _l(_m(d['hp'])['topSpenders'])) {
      final m = _m(x);
      rows.add([m['name'], m['username'], m['hp'], m['uid']]);
    }
    rows
      ..add([])
      ..add(['Hizmet', 'Adet', 'Elmas']);
    for (final x in _l(_m(d['hp'])['services'])) {
      final m = _m(x);
      rows.add([m['name'], m['n'], m['hp']]);
    }
    try {
      await _shareCsv(anchor, 'hadi-istatistik-$_range-${_stamp()}.csv', 'HADİ · İstatistik (${_kRanges[_range]})', rows);
    } catch (_) {
      if (mounted) _snack(context, 'CSV paylaşılamadı.');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final d = _d;
    return RefreshIndicator(
      onRefresh: () => _load(fresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _toolbar(),
          if (_loading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 2)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: InfoNote(text: _error!, icon: Icons.error_outline_rounded, color: HadiColors.error)),
          if (d != null) ..._body(d),
          if (d == null && !_loading && _error == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Veri yok.'))),
          if (SessionScope.of(context).isPrimary) const LiveCostPanel(),
        ],
      ),
    );
  }

  Widget _toolbar() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            segments: [for (final e in _kRanges.entries) ButtonSegment(value: e.key, label: FittedBox(fit: BoxFit.scaleDown, child: Text(e.value, maxLines: 1)))],
            selected: {_range},
            showSelectedIcon: false,
            onSelectionChanged: (s) {
              setState(() => _range = s.first);
              _load();
            },
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonalIcon(onPressed: () => _openMember(), icon: const Icon(Icons.person_search_rounded), label: const Text('Üye istatistikleri')),
          Builder(builder: (b) => OutlinedButton.icon(onPressed: _d == null ? null : () => _export(b), icon: const Icon(Icons.download_rounded), label: const Text('CSV'))),
          OutlinedButton.icon(onPressed: _loading ? null : () => _load(fresh: true), icon: const Icon(Icons.refresh_rounded), label: const Text('Yenile')),
        ]),
      ]);

  List<Widget> _body(_J d) {
    final mem = _m(d['members']), cand = _m(d['candidates']), hp = _m(d['hp']), content = _m(d['content']);
    final msg = _m(d['messaging']), ev = _m(d['events']), live = _m(d['live']), games = _m(d['games']);
    final sup = _m(d['support']), rep = _m(d['reports']), usage = _m(d['usage']), s = _m(d['series']);
    final inR = _m(cand['inRange']);
    final days = [for (final x in _l(s['days'])) '$x'];
    List<num?> ser(String k) => [for (final x in _l(s[k])) _n(x)];
    final missing = _i(d['missing']);
    final scheme = Theme.of(context).colorScheme;
    return [
      const SizedBox(height: 8),
      Text('${_kRanges[_range]} · ${days.isEmpty ? '' : '${_dd(days.first)} – ${_dd(days.last)}'} · güncelleme ${_msDate(d['cachedAt'] ?? d['generatedAt'])}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      if (missing > 0) ...[
        const SizedBox(height: 8),
        InfoNote(
          icon: Icons.history_rounded,
          color: HadiColors.heyecan,
          text: '$missing günün günlük toplamı henüz yok (gece görevi metricsDaily kurulmadan önceki günler). Seriler bu günlerde boş görünür.',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: _busy ? null : _backfill, icon: const Icon(Icons.auto_fix_high_rounded), label: Text(_busy ? 'Hesaplanıyor…' : 'Geçmişi hesapla')),
        ),
      ],
      _Section(title: 'Üyeler', icon: Icons.groups_rounded, color: HadiColors.aktivite, children: [
        _KpiGrid([
          _Kpi('Toplam üye', _fmt(_n(mem['total'])), sub: 'test hesapları hariç'),
          _Kpi('Yeni üye', _fmt(_n(mem['newInRange'])), sub: _kRanges[_range]),
          _Kpi('Günlük aktif', _fmt(_n(mem['dau'])), sub: 'son 24 saat'),
          _Kpi('Haftalık aktif', _fmt(_n(mem['wau'])), sub: 'son 7 gün'),
          _Kpi('Aylık aktif', _fmt(_n(mem['mau'])), sub: 'son 30 gün'),
          _Kpi('Premium', _fmt(_n(mem['premium'])), color: HadiColors.gold),
          _Kpi('Kimliği doğrulanmış', _fmt(_n(mem['verified']))),
          _Kpi('Analitik rızası', _fmt(_n(mem['consented'])), sub: 'açık rıza veren'),
          _Kpi('Kurucu / yönetici / mod.', '${_fmt(_n(mem['founders']))} / ${_fmt(_n(mem['admins']))} / ${_fmt(_n(mem['moderators']))}'),
        ]),
        _LineChart(days: days, series: [
          _Series('Yeni üye', HadiColors.dostluk, ser('newMembers')),
        ]),
        _LineChart(days: days, series: [
          _Series('Günlük aktif (uygulamayı açan)', HadiColors.aktivite, ser('dau')),
        ]),
      ]),
      _Section(title: 'Adaylar', icon: Icons.how_to_reg_rounded, color: HadiColors.iletisim, children: [
        _KpiGrid([
          _Kpi('Bekleyen', _fmt(_n(cand['pending'])), color: HadiColors.heyecan),
          _Kpi('Onaylanan (toplam)', _fmt(_n(cand['approved']))),
          _Kpi('Reddedilen (toplam)', _fmt(_n(cand['rejected']))),
          _Kpi('Başvuru (aralık)', _fmt(_n(inR['submitted']))),
          _Kpi('Onay / ret (aralık)', '${_fmt(_n(inR['approved']))} / ${_fmt(_n(inR['rejected']))}'),
          _Kpi('Ort. karar süresi', cand['avgDecisionHours'] == null ? '—' : '${_fmt(_n(cand['avgDecisionHours']), dec: 1)} sa'),
        ]),
        _LineChart(days: days, series: [
          _Series('Başvuru', HadiColors.iletisim, ser('appsIn')),
          _Series('Onay', HadiColors.dostluk, ser('appsOk')),
          _Series('Ret', HadiColors.error, ser('appsNo')),
        ]),
      ]),
      _Section(title: 'Elmas & Akçe ekonomisi', icon: Icons.account_balance_wallet_rounded, color: HadiColors.gold, children: [
        _KpiGrid([
          _Kpi('Satın alınan Elmas', '${_fmt(_n(hp['purchasedElmas'] ?? hp['purchasedHp']))}$kElmas', sub: '${_fmt(_n(hp['purchases']))} işlem · ${_fmt(_n(hp['purchasedTl']), dec: 2)} TL'),
          _Kpi('Harcanan (net)', '${_fmt(_n(hp['spentElmas'] ?? hp['spentHp']))}$kElmas', sub: 'Elmas karşılığı · iadeler düşüldü'),
          _Kpi('Satın almasız yükleme', _fmt(_n(hp['credits'])), sub: 'hoş geldin, ödül, iade…'),
          _Kpi('Dolaşımdaki Elmas', '${_fmt(_n(hp['circulatingElmas'] ?? hp['circulating']))}$kElmas', sub: '${_fmt(_n(hp['holders']))} cüzdanda'),
          if (hp['circulatingAkce'] is num) _Kpi('Dolaşımdaki Akçe', '${_fmt(_n(hp['circulatingAkce']))}$kAkce'),
        ]),
        _LineChart(days: days, series: [
          _Series('Satın alınan', HadiColors.dostluk, ser('hpBought')),
          _Series('Harcanan', HadiColors.heyecan, ser('hpSpent')),
          _Series('Satın almasız', HadiColors.iletisim, ser('credits')),
        ]),
        const _Sub('Harcama dağılımı'),
        _BarList([for (final x in _l(hp['spentByType'])) (_m(x)['label'] as String? ?? '${_m(x)['key']}', _n(_m(x)['elmas'] ?? _m(x)['hp']) ?? 0, null)], color: HadiColors.heyecan, unit: kElmas),
        const _Sub('Ücretli hizmetler'),
        _Table(
          headers: const ['Hizmet', 'Adet', 'Elmas'],
          flex: const [5, 2, 2],
          rows: [for (final x in _l(hp['services'])) [ '${_m(x)['name'] ?? _m(x)['key']}', _fmt(_n(_m(x)['n'])), _fmt(_n(_m(x)['hp']))]],
        ),
        const _Sub('Satın almasız yüklemeler'),
        _BarList([for (final e in _m(hp['creditByKind']).entries) (_kCreditKinds[e.key] ?? e.key, _n(e.value) ?? 0, null)]..sort((a, b) => b.$2.compareTo(a.$2)),
            color: HadiColors.iletisim, unit: kElmas),
        const _Sub('En çok harcayanlar'),
        _Table(
          headers: const ['Üye', 'Elmas'],
          flex: const [6, 2],
          rows: [
            for (final x in _l(hp['topSpenders']))
              ['${_m(x)['name']}${_m(x)['username'] == null ? '' : ' @${_m(x)['username']}'}', _fmt(_n(_m(x)['hp']))]
          ],
          onTap: (i) {
            final m = _m(_l(hp['topSpenders'])[i]);
            _openMember('${m['uid']}', '${m['name']}');
          },
        ),
      ]),
      _Section(title: 'İçerik', icon: Icons.photo_library_rounded, color: HadiColors.pink, children: [
        _KpiGrid([
          _Kpi('Gönderi', _fmt(_n(content['posts']))),
          _Kpi('An (reel)', _fmt(_n(content['reels']))),
          _Kpi('Story', _fmt(_n(content['stories']))),
          _Kpi('Yorum', _fmt(_n(content['comments']))),
          _Kpi('Yanıt', _fmt(_n(content['replies']))),
        ]),
        _LineChart(days: days, series: [
          _Series('Gönderi + an', HadiColors.pink, ser('posts')),
          _Series('Story', HadiColors.heyecan, ser('stories')),
          _Series('Yorum', HadiColors.aktivite, ser('comments')),
        ]),
      ]),
      _Section(title: 'Mesajlaşma', icon: Icons.chat_rounded, color: HadiColors.aktivite, children: [
        _KpiGrid([_Kpi('Mesaj', _fmt(_n(msg['total'])), sub: 'tüm sohbetler, kanallar, gruplar')]),
        _LineChart(days: days, series: [_Series('Mesaj', HadiColors.aktivite, ser('msgs'))]),
        const _Sub('Türe göre'),
        _BarList([for (final e in _m(msg['byType']).entries) (_kMsgTypes[e.key] ?? e.key, _n(e.value) ?? 0, null)]..sort((a, b) => b.$2.compareTo(a.$2)),
            color: HadiColors.aktivite),
      ]),
      _Section(title: 'Etkinlikler', icon: Icons.event_rounded, color: HadiColors.heyecan, children: [
        _KpiGrid([
          _Kpi('Oluşturulan', _fmt(_n(ev['created']))),
          _Kpi('Katılım', _fmt(_n(ev['joins']))),
          _Kpi('Doluluk', ev['fillRate'] == null ? '—' : '%${_fmt(_n(ev['fillRate']), dec: 1)}', sub: '${_fmt(_n(ev['held']))} etkinlik yapıldı'),
          _Kpi('Yaklaşan', _fmt(_n(ev['upcoming']))),
          _Kpi('Bilet geliri', '${_fmt(_n(ev['revenueElmas'] ?? ev['revenueHp']))}$kElmas'),
        ]),
        _LineChart(days: days, series: [_Series('Katılım', HadiColors.heyecan, ser('eventJoins'))]),
      ]),
      _Section(title: 'Canlı yayın', icon: Icons.live_tv_rounded, color: HadiColors.error, children: [
        _KpiGrid([
          _Kpi('Yayın', _fmt(_n(live['streams']))),
          _Kpi('Toplam süre', '${_fmt(_n(live['minutes']))} dk'),
          _Kpi('Hediye', '${_fmt(_n(live['giftsElmas'] ?? live['giftsHp']))}$kElmas'),
          _Kpi('Şu an canlı', _fmt(_n(live['liveNow']))),
        ]),
        _LineChart(days: days, series: [_Series('Yayın dakikası', HadiColors.error, ser('liveMin'))]),
      ]),
      _Section(title: 'Oyunlar', icon: Icons.sports_esports_rounded, color: HadiColors.dostluk, children: [
        _KpiGrid([
          _Kpi('Maç', _fmt(_n(games['matches']))),
          _Kpi('Turnuva (açılan)', _fmt(_n(games['tournaments']))),
          _Kpi('Açık turnuva', _fmt(_n(games['tournamentsOpen']))),
        ]),
        _LineChart(days: days, series: [_Series('Maç', HadiColors.dostluk, ser('matches'))]),
        const _Sub('Oyuna göre'),
        _BarList([for (final e in _m(games['byGame']).entries) (e.key, _n(e.value) ?? 0, null)]..sort((a, b) => b.$2.compareTo(a.$2)), color: HadiColors.dostluk),
      ]),
      _Section(title: 'Destek ve şikayetler', icon: Icons.support_agent_rounded, color: HadiColors.ink2, children: [
        _KpiGrid([
          _Kpi('Destek talebi', _fmt(_n(sup['tickets']))),
          _Kpi('Açık / işlemde', '${_fmt(_n(sup['open']))} / ${_fmt(_n(sup['inProgress']))}', color: HadiColors.heyecan),
          _Kpi('Şikayet', _fmt(_n(rep['inRange']))),
          _Kpi('Açık şikayet', _fmt(_n(rep['open'])), color: HadiColors.error),
        ]),
        _LineChart(days: days, series: [
          _Series('Destek', HadiColors.ink2, ser('tickets')),
          _Series('Şikayet', HadiColors.error, ser('reports')),
        ]),
      ]),
      _Section(title: 'Özellik kullanımı', icon: Icons.insights_rounded, color: HadiColors.iletisim, children: [
        _KpiGrid([
          _Kpi('Oturum', _fmt(_n(usage['sessions'])), sub: 'anonim sayaç'),
          _Kpi('Ort. oturum', usage['avgSessionMin'] == null ? '—' : '${_fmt(_n(usage['avgSessionMin']), dec: 1)} dk'),
        ]),
        const _Sub('En çok kullanılanlar'),
        _Table(
          headers: const ['Özellik', 'Kaynak', 'Kullanım'],
          flex: const [6, 2, 3],
          rows: [for (final x in _l(d['features']).take(30)) ['${_m(x)['label']}', '${_m(x)['source']}', _fmt(_n(_m(x)['count']))]],
        ),
        const _Sub('Uygulama olayları (anonim günlük sayaçlar)'),
        _BarList([for (final x in _l(usage['events']).take(12)) (_kAnEvents['${_m(x)['key']}'] ?? '${_m(x)['key']}', _n(_m(x)['count']) ?? 0, null)],
            color: HadiColors.iletisim),
      ]),
      _Section(title: 'Haftalık elde tutma (kohort)', icon: Icons.stacked_line_chart_rounded, color: HadiColors.aktivite, children: [
        _Cohort(_m(d['cohorts'])),
      ]),
      const SizedBox(height: 12),
      const InfoNote(
        text: 'KVKK: Bu sayfadaki tüm sayılar toplamdır. Ekran/oturum sayaçları kişiye bağlı değildir. Üye ayrıntısında kullanım '
            'analitiği yalnızca açık rıza veren üyeler için gösterilir; mesaj içerikleri hiçbir koşulda okunmaz. Her üye görüntüleme kayda geçer.',
      ),
    ];
  }
}

// =============================================================================
// Üye ayrıntısı
// =============================================================================

class MemberMetricsScreen extends StatefulWidget {
  const MemberMetricsScreen({super.key, required this.uid, required this.title});
  final String uid, title;

  @override
  State<MemberMetricsScreen> createState() => _MemberMetricsScreenState();
}

class _MemberMetricsScreenState extends State<MemberMetricsScreen> {
  _J? _d;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool fresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await _api(context).member(widget.uid, fresh: fresh);
      if (mounted) setState(() => _d = d);
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Üye istatistikleri alınamadı.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _export(BuildContext anchor) async {
    final d = _d;
    if (d == null) return;
    final p = _m(d['profile']), c = _m(d['counts']), w = _m(d['wallet']), a = _m(d['analytics']);
    final rows = <List<Object?>>[
      ['HADİ Üye istatistiği', p['name'], p['username'], widget.uid],
      ['Katılım', _msDate(p['joinedAt']), 'Son görülme', _msDate(d['lastSeen'])],
      [],
      ['Ölçü', 'Değer'],
      for (final e in c.entries) [e.key, e.value],
      for (final e in w.entries)
        if (e.value is num || e.value == null) ['wallet.${e.key}', e.value],
      [],
      ['Defter türü', 'Adet', 'Elmas'],
      for (final x in _l(w['byType'])) [_kLedgerTypes['${_m(x)['key']}'] ?? _m(x)['key'], _m(x)['n'], _m(x)['hp']],
      [],
      ['Hizmet', 'Adet', 'Elmas'],
      for (final x in _l(w['services'])) [_m(x)['name'], _m(x)['n'], _m(x)['hp']],
      [],
      ['Satın alma tarihi', 'Elmas', 'TL', 'Kanal'],
      for (final x in _l(w['purchases'])) [_msDate(_m(x)['at']), _m(x)['elmas'] ?? _m(x)['hp'], _m(x)['tl'], _m(x)['channel']],
      if (a.isNotEmpty) ...[
        [],
        ['Kullanım olayı (rızalı)', 'Adet'],
        for (final x in _l(a['events'])) [_m(x)['key'], _m(x)['count']],
        ['Ekran', 'Ziyaret'],
        for (final x in _l(a['screens'])) [_m(x)['key'], _m(x)['count']],
      ],
    ];
    try {
      await _shareCsv(anchor, 'hadi-uye-${p['username'] ?? widget.uid}-${_stamp()}.csv', 'HADİ · Üye istatistiği', rows);
    } catch (_) {
      if (mounted) _snack(context, 'CSV paylaşılamadı.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          Builder(builder: (b) => IconButton(tooltip: 'CSV', onPressed: d == null ? null : () => _export(b), icon: const Icon(Icons.download_rounded))),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(fresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null) InfoNote(text: _error!, icon: Icons.error_outline_rounded, color: HadiColors.error),
            if (d != null) ..._body(d),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(_J d) {
    final p = _m(d['profile']), app = _m(d['application']), c = _m(d['counts']), w = _m(d['wallet']);
    final consent = _m(d['consent']);
    final a = d['analytics'] == null ? null : _m(d['analytics']);
    final scheme = Theme.of(context).colorScheme;
    final chips = <String>[
      if (p['founder'] == true) 'Kurucu',
      if (p['role'] != null) '${p['role']}',
      if (p['plan'] == 'premium') 'Premium${p['premiumUntil'] is num ? ' · ${_msDate(p['premiumUntil']).substring(0, 10)}' : ''}',
      if (app['identityVerified'] == true) 'Kimlik doğrulandı',
      if (p['dummy'] == true) 'Test hesabı',
      for (final b in _l(p['badges'])) '$b',
      for (final b in _l(p['roleBadges'])) _m(b)['name'] is String ? '${_m(b)['name']}' : '$b',
    ];
    final monthly = _l(w['monthly']);
    return [
      Text('${p['name'] ?? widget.title}${p['username'] == null ? '' : '  @${p['username']}'}', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      Text('Güncelleme ${_msDate(d['cachedAt'])} · uid ${widget.uid}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      if (chips.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [for (final t in chips) Chip(label: Text(t), visualDensity: VisualDensity.compact)]),
      ],
      _Section(title: 'Üyelik', icon: Icons.badge_rounded, color: HadiColors.aktivite, children: [
        _KpiGrid([
          _Kpi('Katılım', _msDate(p['joinedAt'])),
          _Kpi('Son görülme', _msDate(d['lastSeen'])),
          _Kpi('Başvuru', _msDate(app['createdAt']), sub: app['status'] == null ? null : 'durum: ${app['status']}'),
          _Kpi('Karar', _msDate(app['decidedAt'])),
          _Kpi('Seviye', _fmt(_n(p['level'])), sub: '${_fmt(_n(p['achievements']))} başarı'),
          _Kpi('Premium kaynağı', '${p['premiumSource'] ?? '—'}', sub: p['premiumEndedReason'] == null ? null : 'son bitiş: ${p['premiumEndedReason']}'),
        ]),
      ]),
      _Section(title: 'Etkinlik ve içerik', icon: Icons.bar_chart_rounded, color: HadiColors.pink, children: [
        _KpiGrid([
          _Kpi('Gönderi', _fmt(_n(c['posts']))),
          _Kpi('Aktif story', _fmt(_n(c['stories']))),
          _Kpi('Mesaj', _fmt(_n(c['messages'])), sub: 'yalnızca sayı'),
          _Kpi('Yorum', _fmt(_n(c['comments']))),
          _Kpi('Beğeni', _fmt(_n(c['likes']))),
          _Kpi('Etkinlik katılımı', _fmt(_n(c['eventsJoined']))),
          _Kpi('Oyun', _fmt(_n(c['games']))),
          _Kpi('Canlı yayın', _fmt(_n(c['livesHosted']))),
          _Kpi('Hediye gönderimi', _fmt(_n(c['giftsSent']))),
          _Kpi('Takipçi / takip', '${_fmt(_n(c['followers']))} / ${_fmt(_n(c['following']))}'),
          _Kpi('Destek talebi', _fmt(_n(c['tickets']))),
          _Kpi('Şikayet etti / edildi', '${_fmt(_n(c['reportsBy']))} / ${_fmt(_n(c['reportsAgainst']))}',
              color: _i(c['reportsAgainst']) > 0 ? HadiColors.error : null),
        ]),
      ]),
      _Section(title: 'Cüzdan', icon: Icons.account_balance_wallet_rounded, color: HadiColors.gold, children: [
        _KpiGrid([
          _Kpi('Elmas', '${_fmt(_n(w['elmas'] ?? w['balance']))}$kElmas', sub: w['refundable'] is num ? 'iade edilebilir ${_fmt(_n(w['refundable']))}$kElmas' : null),
          if (w['akce'] is num) _Kpi('Akçe', '${_fmt(_n(w['akce']))}$kAkce'),
          _Kpi('Satın aldığı', '${_fmt(_n(w['purchasedElmas'] ?? w['purchasedHp']))}$kElmas', sub: '${_fmt(_n(w['purchasedTl']), dec: 2)} TL'),
          _Kpi('Harcadığı (net)', '${_fmt(_n(w['spentElmas'] ?? w['spentHp']))}$kElmas', sub: 'Elmas karşılığı'),
          _Kpi('Defter kaydı', _fmt(_n(w['ledgerCount'])), sub: w['ledgerTruncated'] == true ? 'son 3000 kayıt' : null),
        ]),
        if (monthly.length > 1)
          _LineChart(
            days: [for (final x in monthly) '${_m(x)['month']}'],
            labelOf: (k) => k.length >= 7 ? '${k.substring(5, 7)}.${k.substring(2, 4)}' : k,
            series: [
              _Series('Giren (💎 karşılığı)', HadiColors.dostluk, [for (final x in monthly) _n(_m(x)['in'])]),
              _Series('Çıkan (💎 karşılığı)', HadiColors.heyecan, [for (final x in monthly) _n(_m(x)['out'])]),
            ],
          ),
        const _Sub('Defter türleri'),
        _Table(
          headers: const ['Tür', 'Adet', 'Elmas'],
          flex: const [5, 2, 2],
          rows: [for (final x in _l(w['byType'])) [_kLedgerTypes['${_m(x)['key']}'] ?? '${_m(x)['key']}', _fmt(_n(_m(x)['n'])), _fmt(_n(_m(x)['hp']))]],
        ),
        const _Sub('Kullandığı hizmetler'),
        _Table(
          headers: const ['Hizmet', 'Adet', 'Elmas'],
          flex: const [5, 2, 2],
          rows: [for (final x in _l(w['services'])) ['${_m(x)['name'] ?? _m(x)['key']}', _fmt(_n(_m(x)['n'])), _fmt(_n(_m(x)['hp']))]],
        ),
        const _Sub('Satın almalar'),
        _Table(
          headers: const ['Tarih', 'Elmas', 'TL', 'Kanal'],
          flex: const [4, 2, 2, 2],
          rows: [for (final x in _l(w['purchases'])) [_msDate(_m(x)['at']), _fmt(_n(_m(x)['elmas'] ?? _m(x)['hp'])), _fmt(_n(_m(x)['tl']), dec: 2), '${_m(x)['channel'] ?? ''}']],
        ),
        const _Sub('Satın almasız yüklemeler'),
        _BarList([for (final e in _m(w['creditByKind']).entries) (_kCreditKinds[e.key] ?? e.key, _n(e.value) ?? 0, null)], color: HadiColors.iletisim, unit: kElmas),
      ]),
      _Section(title: 'Kullanım analitiği', icon: Icons.insights_rounded, color: HadiColors.iletisim, children: [
        if (a == null)
          InfoNote(
            text: 'Bu üye kullanım analitiğine açık rıza vermemiş${consent['at'] == null ? '' : ' (ya da rızasını geri çekmiş)'}. KVKK gereği kişiye bağlı '
                'ekran/oturum verisi gösterilmez; yukarıdaki sayılar yalnızca hizmetin işleyişi için tutulan kayıtlardan hesaplanır.',
          )
        else ...[
          _KpiGrid([
            _Kpi('Oturum', _fmt(_n(a['sessions'])), sub: 'son ${_fmt(_n(a['sample']))} olay'),
            _Kpi('Ort. oturum', a['avgSessionMin'] == null ? '—' : '${_fmt(_n(a['avgSessionMin']), dec: 1)} dk'),
            _Kpi('Aktif gün', _fmt(_n(a['activeDays']))),
            _Kpi('Son olay', _msDate(a['lastEvent'])),
          ]),
          if (_l(a['perDay']).length > 1)
            _LineChart(
              days: [for (final x in _l(a['perDay'])) '${_m(x)['day']}'],
              series: [_Series('Günlük olay', HadiColors.iletisim, [for (final x in _l(a['perDay'])) _n(_m(x)['n'])])],
            ),
          const _Sub('Ekranlar (ziyaret)'),
          _BarList([for (final x in _l(a['screens'])) ('${_m(x)['key']}'.replaceAll('~', ':'), _n(_m(x)['count']) ?? 0, null)], color: HadiColors.aktivite),
          const _Sub('Ekran süresi (dk)'),
          _BarList([for (final x in _l(a['screenMinutes'])) ('${_m(x)['key']}'.replaceAll('~', ':'), _n(_m(x)['count']) ?? 0, null)], color: HadiColors.dostluk, unit: 'dk'),
          const _Sub('Olaylar'),
          _BarList([for (final x in _l(a['events'])) (_kAnEvents['${_m(x)['key']}'] ?? '${_m(x)['key']}', _n(_m(x)['count']) ?? 0, null)], color: HadiColors.iletisim),
          const SizedBox(height: 8),
          InfoNote(text: 'Üye ${_msDate(consent['at'])} tarihinde analitiğe açık rıza verdi. Bu görüntüleme denetim kaydına yazıldı.', icon: Icons.verified_user_outlined),
        ],
      ]),
    ];
  }
}

// =============================================================================
// Parçalar
// =============================================================================

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.color, required this.children});
  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 10),
        for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 8), child: c),
      ]),
    );
  }
}

class _Sub extends StatelessWidget {
  const _Sub(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class _Kpi {
  const _Kpi(this.label, this.value, {this.sub, this.color});
  final String label, value;
  final String? sub;
  final Color? color;
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid(this.items);
  final List<_Kpi> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth > 900 ? 4 : box.maxWidth > 540 ? 3 : 2;
      final w = (box.maxWidth - (cols - 1) * 8) / cols;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final k in items)
          Container(
            width: w,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(k.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(k.value, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: k.color ?? scheme.onSurface)),
              ),
              if (k.sub != null) Text(k.sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
          ),
      ]);
    });
  }
}

class _Series {
  const _Series(this.label, this.color, this.values);
  final String label;
  final Color color;
  final List<num?> values;
}

/// Basit çizgi grafik (CustomPainter): boş gün (null) çizgiyi böler; dokun/sürükle → o günün değerleri.
class _LineChart extends StatefulWidget {
  const _LineChart({required this.days, required this.series, this.height = 140, this.labelOf = _dd});
  final List<String> days;
  final List<_Series> series;
  final double height;
  final String Function(String) labelOf;

  @override
  State<_LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<_LineChart> {
  int? _sel;

  void _pick(double dx, double width) {
    final n = widget.days.length;
    if (n == 0 || width <= 0) return;
    final i = n == 1 ? 0 : (dx / width * (n - 1)).round().clamp(0, n - 1);
    if (i != _sel) setState(() => _sel = i);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final n = widget.days.length;
    var maxV = 0.0;
    for (final s in widget.series) {
      for (final v in s.values) {
        if (v != null && v > maxV) maxV = v.toDouble();
      }
    }
    final hasData = widget.series.any((s) => s.values.any((v) => v != null && v != 0));
    final sel = _sel != null && _sel! < n ? _sel : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 12, runSpacing: 4, children: [
        for (final s in widget.series)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 5),
            Flexible(child: Text(
              sel == null ? s.label : '${s.label}: ${_fmt(sel < s.values.length ? s.values[sel] : null)}',
              style: t.labelSmall,
            )),
          ]),
        if (sel != null) Text(widget.labelOf(widget.days[sel]), style: t.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 6),
      SizedBox(
        height: widget.height,
        child: !hasData
            ? Center(child: Text('Bu aralıkta veri yok', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)))
            : LayoutBuilder(
                builder: (context, box) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (e) => _pick(e.localPosition.dx, box.maxWidth),
                  onHorizontalDragUpdate: (e) => _pick(e.localPosition.dx, box.maxWidth),
                  child: Stack(children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _LinePainter(
                          series: widget.series,
                          n: n,
                          maxV: maxV <= 0 ? 1 : maxV,
                          sel: sel,
                          grid: scheme.outlineVariant.withValues(alpha: .6),
                          cursor: scheme.onSurface.withValues(alpha: .35),
                        ),
                      ),
                    ),
                    Positioned(left: 0, top: 0, child: Text(_fmt(maxV), style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant))),
                  ]),
                ),
              ),
      ),
      if (n > 0)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(children: [
            Text(widget.labelOf(widget.days.first), style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            const Spacer(),
            Text(widget.labelOf(widget.days.last), style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          ]),
        ),
    ]);
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.series, required this.n, required this.maxV, required this.sel, required this.grid, required this.cursor});
  final List<_Series> series;
  final int n;
  final double maxV;
  final int? sel;
  final Color grid, cursor;

  double _x(int i, Size size) => n <= 1 ? size.width / 2 : i * size.width / (n - 1);

  @override
  void paint(Canvas canvas, Size size) {
    final g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final f in const [0.0, .5, 1.0]) {
      final y = size.height - f * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), g);
    }
    for (final s in series) {
      final p = Paint()
        ..color = s.color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      final dot = Paint()..color = s.color;
      final path = Path();
      var started = false;
      final m = math.min(n, s.values.length);
      for (var i = 0; i < m; i++) {
        final v = s.values[i];
        if (v == null) {
          started = false;
          continue;
        }
        final o = Offset(_x(i, size), size.height - (v / maxV) * size.height);
        if (!started) {
          path.moveTo(o.dx, o.dy);
          started = true;
          // Tek başına kalan nokta da görünsün.
          final next = i + 1 < m ? s.values[i + 1] : null;
          if (next == null) canvas.drawCircle(o, 2.5, dot);
        } else {
          path.lineTo(o.dx, o.dy);
        }
        if (sel == i) canvas.drawCircle(o, 3.5, dot);
      }
      canvas.drawPath(path, p);
    }
    if (sel != null) {
      final x = _x(sel!, size);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), Paint()
        ..color = cursor
        ..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.series != series || old.sel != sel || old.maxV != maxV || old.n != n || old.grid != grid;
}

/// Yatay çubuk listesi (en büyük değere göre oranlı).
class _BarList extends StatelessWidget {
  const _BarList(this.items, {required this.color, this.unit, this.max = 12});
  final List<(String, num, String?)> items;
  final Color color;
  final String? unit;
  final int max;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final list = items.where((x) => x.$2 > 0).take(max).toList();
    if (list.isEmpty) return Text('—', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant));
    final top = list.map((x) => x.$2).reduce(math.max).toDouble();
    return Column(children: [
      for (final x in list)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(flex: 4, child: Text(x.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall)),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Stack(children: [
                  Container(height: 12, color: color.withValues(alpha: .12)),
                  FractionallySizedBox(
                    widthFactor: top <= 0 ? 0 : (x.$2 / top).clamp(0.0, 1.0).toDouble(),
                    child: Container(height: 12, color: color),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 76,
              child: Text('${_fmt(x.$2)}${unit == null ? '' : ' $unit'}', textAlign: TextAlign.end, style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
    ]);
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.headers, required this.rows, required this.flex, this.onTap});
  final List<String> headers;
  final List<List<String>> rows;
  final List<int> flex;
  final void Function(int index)? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    if (rows.isEmpty) return Text('—', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant));
    Widget row(List<String> cells, {bool head = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(children: [
            for (var i = 0; i < headers.length; i++)
              Expanded(
                flex: i < flex.length ? flex[i] : 1,
                child: Text(
                  i < cells.length ? cells[i] : '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: i == 0 ? TextAlign.start : TextAlign.end,
                  style: head ? t.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700) : t.bodySmall,
                ),
              ),
          ]),
        );
    return Container(
      decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        row(headers, head: true),
        for (var i = 0; i < rows.length; i++) ...[
          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: .5)),
          onTap == null ? row(rows[i]) : InkWell(onTap: () => onTap!(i), child: row(rows[i])),
        ],
      ]),
    );
  }
}

/// Kohort tablosu: satır = katılım haftası, sütun = sonraki haftalar (%).
class _Cohort extends StatelessWidget {
  const _Cohort(this.data);
  final _J data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final rows = _l(data['rows']);
    if (rows.isEmpty) return Text('Kohort verisi henüz yok.', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant));
    final weeks = rows.fold<int>(0, (m, r) => math.max(m, _l(_m(r)['retention']).length));
    Widget cell(String s, {Color? bg, bool bold = false}) => Container(
          width: 52,
          height: 30,
          alignment: Alignment.center,
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
          child: Text(s, style: t.labelSmall?.copyWith(fontWeight: bold ? FontWeight.w700 : null)),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            cell('Hafta', bold: true),
            cell('Üye', bold: true),
            for (var k = 0; k < weeks; k++) cell('H$k', bold: true),
          ]),
          for (final r in rows)
            Row(children: [
              cell(_dd('${_m(r)['week']}')),
              cell(_fmt(_n(_m(r)['size']))),
              for (final v in _l(_m(r)['retention']))
                cell(
                  v == null ? '—' : '%${_fmt(_n(v))}',
                  bg: v is num ? HadiColors.aktivite.withValues(alpha: (.08 + (v / 100) * .6).clamp(.08, .68).toDouble()) : null,
                ),
            ]),
        ]),
      ),
      const SizedBox(height: 6),
      Text('H0 = katıldığı hafta. Oran, o hafta uygulamayı en az bir kez açan üyelerin payıdır (anonim günlük sayaçlar).',
          style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
    ]);
  }
}
