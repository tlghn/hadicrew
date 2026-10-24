// HADİ Crew — Bildirim Stüdyosu istemcisi (24 Ekim 2026). Sunucu: hadimobile/functions/src/notify_studio.ts (callable
// `notifyStudio`, bildirim grubu). Yetki: notify.send (hazırla/gönder), notify.approve (onay), kurucu (ayarlar).
// Tanıtım modunda (PANEL_DEMO) bellekte örnek kampanyalar, kitle sayımı ve raporlar.
import 'dart:convert';
import 'dart:math' as math;

import 'package:hadi/data/models.dart' show AppFailure;
import 'package:hadi/data/ops_api.dart';
import 'package:hadi/data/services.dart';

const kNsCategories = <String, ({String label, String emoji, String hint})>{
  'service': (label: 'Hizmet', emoji: '🔔', hint: 'Sipariş, güvenlik, hesap. Tercih ve sessiz saatten bağımsız; pazarlama içeremez.'),
  'announcement': (label: 'Duyuru', emoji: '📣', hint: 'Yeni özellik, kural değişikliği, kulüp haberi. "HADİ duyuruları"nı kapatana gitmez.'),
  'event': (label: 'Etkinlik', emoji: '📅', hint: 'Etkinlik hatırlatması / önerisi. "Etkinlik önerileri"ni kapatana gitmez.'),
  'marketing': (label: 'Pazarlama', emoji: '🎁', hint: 'Kampanya, indirim, satış. YALNIZCA açık izni olan 18+ üyelere; günde en çok sınır kadar.'),
};

const kNsStatus = <String, String>{
  'draft': 'Taslak', 'pending_approval': 'Onay bekliyor', 'approved': 'Onaylandı', 'scheduled': 'Planlandı', 'sending': 'Gönderiliyor',
  'recurring': 'Tekrarlı', 'paused': 'Duraklatıldı', 'sent': 'Gönderildi', 'cancelled': 'İptal', 'rejected': 'Reddedildi', 'failed': 'Hata',
};

const kNsSkip = <String, String>{
  'no_consent': 'Kampanya izni yok', 'opted_out': 'Bu kategoriyi kapatmış', 'under18': '18 yaş altı', 'age_unknown': 'Yaşı bilinmiyor',
  'frozen': 'Hesabı dondurulmuş', 'deleted': 'Hesap silinmiş', 'dummy': 'Test hesabı', 'stale': 'Bekleme süresi doldu',
};

const kNsSounds = <({String id, String label, String file})>[
  (id: 'default', label: 'Telefonun varsayılan sesi', file: ''),
  (id: 'hadi_ding', label: 'Ding (yumuşak çan)', file: 'hadi_ding.wav'),
  (id: 'hadi_pop', label: 'Pıt (baloncuk)', file: 'hadi_pop.wav'),
  (id: 'hadi_marimba', label: 'Marimba (üç nota)', file: 'hadi_marimba.wav'),
  (id: 'hadi_parilti', label: 'Parıltı (kampanya)', file: 'hadi_parilti.wav'),
  (id: 'hadi_davet', label: 'Davet (sıcak zil)', file: 'hadi_davet.wav'),
  (id: 'hadi_zil', label: 'Kapı zili (iki ton)', file: 'hadi_zil.wav'),
];

/// Süzgeç alanları (sunucudaki beyaz liste ile aynı; özel nitelikli veri alanı YOK).
const kNsFields = <String, String>{
  'province': 'İl', 'district': 'İlçe', 'age': 'Yaş aralığı', 'gender': 'Cinsiyet (kendi seçtiyse)', 'interests': 'İlgi alanları',
  'community': 'Topluluk üyeliği', 'eventType': 'Katıldığı etkinlik türü', 'premium': 'Premium', 'memberDays': 'Üyelik süresi (gün)',
  'inactiveDays': 'En az N gündür girmeyen', 'activeDays': 'Son N günde giren', 'elmasBuyer': 'Elmas satın almış', 'storeCustomer': 'Mağaza müşterisi',
  'platform': 'Platform', 'appVersion': 'Uygulama sürümü', 'lang': 'Dil',
};

/// Bir taslak (düzenlenebilir).
class NsVariant {
  NsVariant(this.id);
  final String id;
  String title = '', body = '', sound = 'default', link = '';
  String? image;
  List<({String label, String link})> buttons = [];
  bool cardOn = false;
  String cardTitle = '', cardBody = '';
  String? cardImage, cardAudio;
  int cardAudioSec = 0;

  Map<String, Object?> toJson() => {
        'title': title, 'body': body, 'sound': sound, 'link': link, 'image': image,
        'buttons': [for (final b in buttons) {'label': b.label, 'link': b.link}],
        'card': cardOn ? {'on': true, 'title': cardTitle, 'body': cardBody, 'image': cardImage, 'audio': cardAudio, 'audioSec': cardAudioSec} : null,
      };

  static NsVariant from(String id, Map<String, dynamic> m) {
    final v = NsVariant(id)
      ..title = '${m['title'] ?? ''}'
      ..body = '${m['body'] ?? ''}'
      ..sound = '${m['sound'] ?? 'default'}'
      ..link = '${m['link'] ?? ''}'
      ..image = m['image'] as String?
      ..buttons = [for (final b in OpsApi.list(m['buttons'])) (label: '${b['label'] ?? ''}', link: '${b['link'] ?? ''}')];
    final c = m['card'];
    if (c is Map && c['on'] == true) {
      v
        ..cardOn = true
        ..cardTitle = '${c['title'] ?? ''}'
        ..cardBody = '${c['body'] ?? ''}'
        ..cardImage = c['image'] as String?
        ..cardAudio = c['audio'] as String?
        ..cardAudioSec = c['audioSec'] is num ? (c['audioSec'] as num).toInt() : 0;
    }
    return v;
  }
}

class NsDraft {
  String? cid;
  String name = '', category = 'announcement', reason = '';
  Map<String, Object?> audience = {'mode': 'all'};
  final variants = [NsVariant('A'), NsVariant('B')];
  bool abOn = false;
  int abSample = 20, abWait = 4;
  String scheduleMode = 'now';
  DateTime? at;
  Set<int> dow = {5};
  int hour = 18, minute = 0;
  DateTime? until;

  Map<String, Object?> toJson() => {
        'name': name, 'category': category, 'reason': reason, 'audience': audience,
        'variants': [variants[0].toJson(), if (abOn) variants[1].toJson()],
        'ab': {'on': abOn, 'samplePct': abSample, 'waitHours': abWait},
        'schedule': {
          'mode': scheduleMode,
          if (scheduleMode == 'at') 'at': at?.millisecondsSinceEpoch,
          if (scheduleMode == 'recurring') 'rec': {'dow': dow.toList()..sort(), 'hour': hour, 'minute': minute, 'until': until?.millisecondsSinceEpoch},
        },
      };

  static NsDraft from(Map<String, dynamic> m) {
    final d = NsDraft()
      ..cid = m['id'] as String?
      ..name = '${m['name'] ?? ''}'
      ..category = '${m['category'] ?? 'announcement'}'
      ..reason = '${m['reason'] ?? ''}'
      ..audience = OpsApi.map(m['audience']);
    final vs = OpsApi.list(m['variants']);
    if (vs.isNotEmpty) d.variants[0] = NsVariant.from('A', vs[0]);
    if (vs.length > 1) d.variants[1] = NsVariant.from('B', vs[1]);
    final ab = OpsApi.map(m['ab']);
    d
      ..abOn = ab['on'] == true
      ..abSample = ab['samplePct'] is num ? (ab['samplePct'] as num).toInt() : 20
      ..abWait = ab['waitHours'] is num ? (ab['waitHours'] as num).toInt() : 4;
    final s = OpsApi.map(m['schedule']);
    d.scheduleMode = '${s['mode'] ?? 'now'}';
    if (s['at'] is num) d.at = DateTime.fromMillisecondsSinceEpoch((s['at'] as num).toInt());
    final r = OpsApi.map(s['rec']);
    if (r.isNotEmpty) {
      d
        ..dow = {for (final x in (r['dow'] as List? ?? const [])) (x as num).toInt()}
        ..hour = (r['hour'] as num?)?.toInt() ?? 18
        ..minute = (r['minute'] as num?)?.toInt() ?? 0
        ..until = r['until'] is num ? DateTime.fromMillisecondsSinceEpoch((r['until'] as num).toInt()) : null;
    }
    return d;
  }

  NsDraft copyAsNew() {
    final d = NsDraft.from({...jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>, 'id': null});
    d.name = name.isEmpty ? '' : '$name (kopya)';
    return d;
  }
}

/// Kampanya listesi satırı.
class NsItem {
  NsItem(this.m);
  final Map<String, dynamic> m;
  String get id => '${m['id']}';
  String get name => '${m['name'] ?? ''}';
  String get title => '${m['title'] ?? ''}';
  String get body => '${m['body'] ?? ''}';
  String? get image => m['image'] as String?;
  String get category => '${m['category'] ?? ''}';
  String get status => '${m['status'] ?? ''}';
  String get audienceText => '${m['audienceText'] ?? ''}';
  String get by => '${m['createdByName'] ?? ''}';
  int? get resolved => (m['resolvedCount'] as num?)?.toInt();
  DateTime? get updatedAt => OpsApi.time(m['updatedAt']);
  DateTime? get nextAt => OpsApi.time(m['nextAt']);
  Map<String, dynamic> get stats => OpsApi.map(m['stats']);
  int stat(String k) => (stats[k] as num?)?.toInt() ?? 0;
  bool get retracted => m['retracted'] == true;
  bool get ab => m['ab'] != null;
  String? get abWinner => OpsApi.map(m['ab'])['winner'] as String?;
  String get scheduleMode => '${m['scheduleMode'] ?? 'now'}';
}

abstract final class NsApi {
  static Future<Map<String, dynamic>> _call(Services s, String op, [Map<String, Object?> data = const {}]) {
    if (s.isDemo) return _Demo.instance.call(op, data);
    return OpsApi.call('notifyStudio', op, data);
  }

  static Future<Map<String, dynamic>> bootstrap(Services s) => _call(s, 'bootstrap');
  static Future<List<NsItem>> list(Services s, String status) async => [for (final x in OpsApi.list((await _call(s, 'list', {'status': status}))['items'])) NsItem(x)];
  static Future<Map<String, dynamic>> get(Services s, String cid) async => OpsApi.map((await _call(s, 'get', {'cid': cid}))['campaign']);
  static Future<Map<String, dynamic>> report(Services s, String cid) => _call(s, 'report', {'cid': cid});
  static Future<Map<String, dynamic>> count(Services s, Map<String, Object?> audience, String category) =>
      _call(s, 'audienceCount', {'audience': audience, 'category': category});
  static Future<String> save(Services s, NsDraft d) async => '${(await _call(s, 'save', {'cid': d.cid, 'campaign': d.toJson()}))['cid']}';
  static Future<Map<String, dynamic>> submit(Services s, String cid, {bool ackSmall = false}) => _call(s, 'submit', {'cid': cid, 'ackSmall': ackSmall});
  static Future<Map<String, dynamic>> test(Services s, NsDraft d, {String variant = 'A'}) => _call(s, 'test', {'campaign': d.toJson(), 'variant': variant});
  static Future<void> act(Services s, String op, String cid, {String? note}) => _call(s, op, {'cid': cid, 'note': ?note, 'reason': ?note});
  static Future<List<Map<String, dynamic>>> audiences(Services s) async => OpsApi.list((await _call(s, 'audienceList'))['items']);
  static Future<Map<String, dynamic>> saveAudience(Services s, String name, Map<String, Object?> audience) => _call(s, 'audienceSave', {'name': name, 'audience': audience});
  static Future<void> deleteAudience(Services s, String id) => _call(s, 'audienceDelete', {'id': id});
  static Future<List<Map<String, dynamic>>> communities(Services s, String q) async => OpsApi.list((await _call(s, 'communities', {'q': q}))['items']);
  static Future<String> upload(Services s, String kind, String mime, List<int> bytes) async =>
      '${(await _call(s, 'upload', {'kind': kind, 'mime': mime, 'b64': base64Encode(bytes)}))['url']}';
  static Future<Map<String, dynamic>> audit(Services s, {int? cursor}) => _call(s, 'audit', {'cursor': ?cursor});
  static Future<Map<String, dynamic>> configGet(Services s) => _call(s, 'configGet');
  static Future<Map<String, dynamic>> configSet(Services s, Map<String, Object?> c) => _call(s, 'configSet', {'config': c});
  static Future<Map<String, dynamic>> rebuild(Services s) => _call(s, 'rebuild');
}

// ================================================================== tanıtım modu (bellekte)

class _Demo {
  _Demo._() {
    _seed();
  }
  static final instance = _Demo._();

  final _items = <String, Map<String, dynamic>>{};
  final _audiences = <Map<String, dynamic>>[];
  final _audit = <Map<String, dynamic>>[];
  var _config = <String, dynamic>{
    'approvalThreshold': 1000, 'marketingPerDay': 2, 'otherPerDay': 4, 'quietOn': true, 'quietStart': 22, 'quietEnd': 9,
    'marketingDefaultOn': false, 'consentVersion': '2026-10-24', 'consentBonusAkce': 50, 'reaskDays': 18, 'smallAudience': 20,
    'perMinute': 3000, 'conversionHours': 48, 'staleHours': 72,
  };
  int _n = 0;
  static const _img = 'https://images.unsplash.com/photo-1501281668745-f7f57925c3b4?w=900&q=70';
  static const _img2 = 'https://images.unsplash.com/photo-1528605248644-14dd04022da1?w=900&q=70';
  static const _img3 = 'https://images.unsplash.com/photo-1520975916090-3105956dac38?w=900&q=70';

  void _seed() {
    final now = DateTime.now().millisecondsSinceEpoch;
    int ago(int h) => now - h * 3600000;
    Map<String, dynamic> v(String t, String b, {String? img, String link = '', List<Map<String, String>> btn = const [], Map<String, Object?>? card, String sound = 'hadi_ding'}) =>
        {'title': t, 'body': b, 'image': img, 'link': link, 'sound': sound, 'buttons': btn, 'card': card};
    void add(String id, Map<String, dynamic> m) => _items[id] = {'id': id, ...m};
    add('kadikoy_akustik', {
      'name': 'Kadıköy akustik gece', 'category': 'event', 'status': 'sent', 'createdByName': 'Elif (Etkinlik)', 'updatedAt': ago(26), 'createdAt': ago(30),
      'audienceText': '(İl: İstanbul VE İlgi alanı: Konser buluşmaları, Karaoke)', 'resolvedCount': 1840, 'scheduleMode': 'at',
      'variants': [v('Cuma akşamı Moda\'da akustik gece 🎶', '{ad}, bu cuma 20:00\'de sahilde gitarlar çalıyor. Yerler sınırlı!', img: _img, link: '/etkinlik/akustik', btn: [{'label': 'Katılıyorum', 'link': '/etkinlik/akustik'}])],
      'stats': {'targeted': 1840, 'sent': 1712, 'pushed': 1650, 'opened': 498, 'skipped': 128, 'clicks': {'b0': 211, 'b1': 0},
        'byVariant': {'A': {'sent': 1712, 'opened': 498, 'clicks': 211}}, 'conv': {'n': 143, 'kind': 'event', 'byVariant': {'A': 143}, 'sampled': 498}},
      'skip': {'opted_out': 96, 'frozen': 4, 'dummy': 28},
    });
    add('kasim_indirim', {
      'name': 'Kasım mağaza indirimi (A/B)', 'category': 'marketing', 'status': 'sending', 'createdByName': 'Can (Mağaza)', 'updatedAt': ago(3), 'createdAt': ago(8),
      'audienceText': '(Mağaza müşterisi: evet VEYA Elmas alan: evet) VE (Son 30 günde giren)', 'resolvedCount': 6120, 'scheduleMode': 'now',
      'variants': [
        v('Sepetindekiler %25 indirimde 🛍️', 'Sadece bu hafta sonu: HADİ tişört ve kupalarda %25. {ad}, kaçırma!', img: _img3, link: '/magaza', sound: 'hadi_parilti', btn: [{'label': 'Mağazaya git', 'link': '/magaza'}, {'label': 'Sonra', 'link': '/bildirimler'}]),
        v('{ad}, sana özel %25 indirim 🎁', 'Tişört, sweat ve kupalar bu hafta sonu %25 indirimli. Stoklar sınırlı.', img: _img3, link: '/magaza', sound: 'hadi_parilti', btn: [{'label': 'Fırsatı gör', 'link': '/magaza'}]),
      ],
      'ab': {'on': true, 'samplePct': 20, 'waitHours': 4, 'winner': 'B', 'rateA': 0.18, 'rateB': 0.27, 'confident': true},
      'stats': {'targeted': 6120, 'sent': 3405, 'pushed': 3301, 'opened': 812, 'skipped': 2210, 'clicks': {'b0': 377, 'b1': 41},
        'byVariant': {'A': {'sent': 612, 'opened': 110, 'clicks': 51}, 'B': {'sent': 2793, 'opened': 702, 'clicks': 367}}, 'conv': {'n': 96, 'kind': 'store', 'byVariant': {'A': 9, 'B': 87}, 'sampled': 812}},
      'skip': {'no_consent': 2030, 'age_unknown': 61, 'opted_out': 0, 'frozen': 11, 'dummy': 108},
      'funnelExtra': {'queued': 480, 'held': 0, 'deferred': 410},
    });
    add('yeni_ozellik_kitap', {
      'name': 'HADİ Kitap Mağazası açıldı', 'category': 'announcement', 'status': 'pending_approval', 'createdByName': 'Deniz (İçerik)', 'updatedAt': ago(1), 'createdAt': ago(2),
      'audienceText': 'Herkes', 'resolvedCount': 12840, 'scheduleMode': 'at', 'nextAt': now + 20 * 3600000,
      'moderation': 'onaylandi',
      'variants': [v('📚 HADİ Kitap Mağazası açıldı', 'E-kitap ve sesli kitaplar artık HADİ\'de. İlk kitabın için kulübe göz at!', img: _img2, link: '/kitap', card: {'on': true, 'title': 'Kitaplar artık HADİ\'de', 'body': 'Okuma kulüplerine katıl, alıntılarını paylaş, sesli kitapları birlikte dinle.', 'image': _img2})],
      'stats': {},
    });
    add('cuma_hatirlatma', {
      'name': 'Her cuma etkinlik özeti', 'category': 'event', 'status': 'recurring', 'createdByName': 'Elif (Etkinlik)', 'updatedAt': ago(50), 'createdAt': ago(400),
      'audienceText': 'Kayıtlı kitle: Hafta sonu kaşifleri', 'resolvedCount': 3920, 'scheduleMode': 'recurring', 'nextAt': now + 31 * 3600000,
      'variants': [v('Hafta sonu planın hazır mı? 🗓️', 'Bu hafta sonu şehrinde 12 etkinlik var. {ad}, birini seç, gerisini bize bırak.', link: '/etkinlikler', sound: 'hadi_marimba')],
      'stats': {'targeted': 15680, 'sent': 14920, 'pushed': 14410, 'opened': 3870, 'skipped': 760, 'clicks': {'b0': 0, 'b1': 0}, 'byVariant': {'A': {'sent': 14920, 'opened': 3870}}},
    });
    add('kural_degisikligi', {
      'name': 'Topluluk kuralları güncellendi', 'category': 'announcement', 'status': 'draft', 'createdByName': 'Sen', 'updatedAt': ago(5), 'createdAt': ago(5),
      'audienceText': 'Herkes', 'scheduleMode': 'now',
      'variants': [v('Topluluk kurallarımızı güncelledik', 'Kısa ve anlaşılır: neler değişti, 1 dakikada oku.', link: '/topluluk-degerleri')],
      'stats': {},
    });
    _audiences.addAll([
      {'id': 'aud1', 'name': 'Hafta sonu kaşifleri', 'text': '(İlgi alanı: Doğa yürüyüşleri, Kamp, Bisiklet turları) VE (Son 30 günde giren ≤: 30)', 'count': 3920, 'by': 'Elif'},
      {'id': 'aud2', 'name': 'Uyuyan üyeler (30+ gün)', 'text': '(Girmeyen (gün) ≥: 30)', 'count': 2210, 'by': 'Can'},
      {'id': 'aud3', 'name': 'İzmir Premium', 'text': '(İl: İzmir VE Premium: evet)', 'count': 214, 'by': 'Deniz'},
    ]);
    _audit.addAll([
      {'actorName': 'Kurucu', 'action': 'approve', 'title': 'Sepetindekiler %25 indirimde 🛍️', 'category': 'marketing', 'resolvedCount': 6120, 'audienceText': '(Mağaza müşterisi…)', 'at': ago(8)},
      {'actorName': 'Can (Mağaza)', 'action': 'submit', 'title': 'Sepetindekiler %25 indirimde 🛍️', 'category': 'marketing', 'resolvedCount': 6120, 'audienceText': '(Mağaza müşterisi…)', 'at': ago(9)},
      {'actorName': 'Elif (Etkinlik)', 'action': 'send', 'title': 'Cuma akşamı Moda\'da akustik gece 🎶', 'category': 'event', 'resolvedCount': 1840, 'audienceText': '(İl: İstanbul …)', 'at': ago(30)},
      {'actorName': 'Destek', 'action': 'send', 'title': 'Siparişin kargoda', 'category': 'service', 'resolvedCount': 1, 'audienceText': 'Tek üye: Ayşe K.', 'reason': 'Kargo takip numarası yanlış gitmişti, düzeltme', 'at': ago(52)},
      {'actorName': 'Elif (Etkinlik)', 'action': 'test', 'title': 'Hafta sonu planın hazır mı? 🗓️', 'category': 'event', 'at': ago(401)},
    ]);
  }

  Map<String, dynamic> _view(Map<String, dynamic> c) {
    final vs = OpsApi.list(c['variants']);
    return {
      ...c, 'title': vs.isEmpty ? '' : vs[0]['title'], 'body': vs.isEmpty ? '' : vs[0]['body'], 'image': vs.isEmpty ? null : vs[0]['image'],
      'ab': OpsApi.map(c['ab'])['on'] == true ? {'winner': OpsApi.map(c['ab'])['winner']} : null,
    };
  }

  int _countFor(Map<String, Object?> a) {
    switch (a['mode']) {
      case 'all':
        return 12840;
      case 'single':
        return 1;
      case 'list':
        return (a['uids'] as List?)?.length ?? 0;
      case 'saved':
        return (_audiences.firstWhere((x) => x['id'] == a['savedId'], orElse: () => {'count': 0})['count'] as num).toInt();
    }
    var n = 12840.0;
    final groups = (a['groups'] as List?) ?? const [];
    final orTop = a['join'] == 'or';
    double total = orTop ? 0 : 12840;
    for (final g in groups) {
      final rules = ((g as Map)['rules'] as List?) ?? const [];
      var gn = g['join'] == 'or' ? 0.0 : 12840.0;
      for (final r in rules) {
        final f = '${(r as Map)['f']}';
        final frac = switch (f) {
          'province' => .08 + .3 * math.min(1, ((r['v'] as List?)?.length ?? 1) / 4),
          'district' => .02 * ((r['v'] as List?)?.length ?? 1),
          'age' => .35,
          'gender' => .48,
          'premium' => .13,
          'elmasBuyer' => .21,
          'storeCustomer' => .09,
          'inactiveDays' => .17,
          'activeDays' => .62,
          'platform' => .55,
          'appVersion' => .7,
          'community' => .04 * ((r['v'] as List?)?.length ?? 1),
          _ => .18,
        };
        gn = g['join'] == 'or' ? math.min(12840, gn + 12840 * frac) : gn * frac;
      }
      total = orTop ? math.min(12840, total + gn) : total * gn / 12840;
    }
    n = total;
    return n.round();
  }

  Future<Map<String, dynamic>> call(String op, Map<String, Object?> d) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final now = DateTime.now().millisecondsSinceEpoch;
    switch (op) {
      case 'bootstrap':
        return {
          'me': {'uid': 'demo-user', 'name': 'Demo Kurucu', 'founder': true, 'send': true, 'approve': true},
          'config': _config, 'audience': {'total': 12840, 'builtAt': now - 5 * 3600000},
          'pending': _items.values.where((x) => x['status'] == 'pending_approval').length,
        };
      case 'list':
        final st = '${d['status']}';
        bool keep(String s) => switch (st) {
              'pending' => s == 'pending_approval',
              'active' => const ['scheduled', 'sending', 'recurring', 'paused', 'approved'].contains(s),
              'drafts' => s == 'draft' || s == 'rejected',
              _ => true,
            };
        final l = _items.values.where((x) => keep('${x['status']}')).toList()..sort((a, b) => ((b['updatedAt'] as num?) ?? 0).compareTo((a['updatedAt'] as num?) ?? 0));
        return {'items': [for (final x in l) _view(x)]};
      case 'get':
        final c = _items['${d['cid']}'] ?? (throw const AppFailure('Kampanya bulunamadı.'));
        return {'campaign': {..._view(c), 'variants': c['variants'], 'ab': c['ab'], 'audience': c['audience'] ?? {'mode': 'all'}, 'schedule': c['schedule'] ?? {'mode': 'now'}}};
      case 'report':
        final c = _items['${d['cid']}'] ?? (throw const AppFailure('Kampanya bulunamadı.'));
        final s = OpsApi.map(c['stats']);
        final fx = OpsApi.map(c['funnelExtra']);
        return {
          'campaign': _view(c),
          'funnel': {'targeted': s['targeted'] ?? 0, 'queued': fx['queued'] ?? 0, 'held': fx['held'] ?? 0, 'deferred': fx['deferred'] ?? 0, 'sent': s['sent'] ?? 0, 'pushed': s['pushed'] ?? 0, 'opened': s['opened'] ?? 0, 'skipped': s['skipped'] ?? 0},
          'clicks': {...OpsApi.map(s['clicks']), 'labels': [for (final b in OpsApi.list(OpsApi.list(c['variants']).firstOrNull?['buttons'])) b['label']]},
          'byVariant': s['byVariant'] ?? {}, 'ab': c['ab'], 'skip': c['skip'] ?? {}, 'conversion': s['conv'], 'conversionHours': 48,
        };
      case 'audienceCount':
        final a = OpsApi.map(d['audience']);
        final total = _countFor(a);
        final cat = '${d['category']}';
        final noConsent = cat == 'marketing' ? (total * .34).round() : 0;
        final opted = cat == 'announcement' || cat == 'event' ? (total * .05).round() : 0;
        final ageU = cat == 'marketing' ? (total * .01).round() : 0;
        final dummy = (total * .008).round();
        final elig = math.max(0, total - noConsent - opted - ageU - dummy);
        return {
          'total': total, 'eligible': elig, 'estimated': total > 3000,
          'skipped': {if (noConsent > 0) 'no_consent': noConsent, if (opted > 0) 'opted_out': opted, if (ageU > 0) 'age_unknown': ageU, if (dummy > 0) 'dummy': dummy},
          'withDevice': (total * .93).round(), 'small': a['mode'] == 'filter' && total < 20, 'smallMin': 20, 'approval': false, 'threshold': 1000,
          'text': a['mode'] == 'all' ? 'Herkes' : 'Seçilen kitle', 'builtAt': now - 5 * 3600000,
        };
      case 'save':
        final id = (d['cid'] as String?) ?? 'demo${++_n}';
        final c = OpsApi.map(d['campaign']);
        _items[id] = {
          ..._items[id] ?? {}, 'id': id, ...c, 'status': 'draft', 'createdByName': 'Demo Kurucu', 'updatedAt': now, 'createdAt': now,
          'audienceText': c['audience'] is Map && (c['audience'] as Map)['mode'] == 'all' ? 'Herkes' : 'Seçilen kitle', 'scheduleMode': OpsApi.map(c['schedule'])['mode'], 'stats': {},
        };
        return {'cid': id};
      case 'submit':
        final c = _items['${d['cid']}']!;
        final total = _countFor(OpsApi.map(c['audience']));
        final sched = OpsApi.map(c['schedule']);
        c['status'] = sched['mode'] == 'now' ? 'sending' : (sched['mode'] == 'recurring' ? 'recurring' : 'scheduled');
        c['resolvedCount'] = total;
        c['stats'] = {'targeted': total, 'sent': (total * .4).round(), 'pushed': (total * .38).round(), 'opened': 0, 'skipped': (total * .05).round()};
        c['updatedAt'] = now;
        _audit.insert(0, {'actorName': 'Demo Kurucu', 'action': 'send', 'title': OpsApi.list(c['variants']).firstOrNull?['title'], 'category': c['category'], 'resolvedCount': total, 'audienceText': c['audienceText'], 'at': now});
        return {'status': c['status'], 'count': total, 'moderation': {'verdict': 'onaylandi', 'reason': 'Uygun.'}};
      case 'test':
        return {'ok': true, 'devices': 2, 'delivered': 2};
      case 'approve':
      case 'reject':
      case 'cancel':
      case 'pause':
      case 'resume':
      case 'retract':
        final c = _items['${d['cid']}']!;
        c['status'] = switch (op) {
          'approve' => 'scheduled',
          'reject' => 'rejected',
          'cancel' => 'cancelled',
          'pause' => 'paused',
          'resume' => 'sending',
          _ => c['status'],
        };
        if (op == 'retract') c['retracted'] = true;
        c['updatedAt'] = now;
        _audit.insert(0, {'actorName': 'Demo Kurucu', 'action': op, 'title': OpsApi.list(c['variants']).firstOrNull?['title'], 'category': c['category'], 'reason': d['note'], 'at': now});
        return {'ok': true};
      case 'audienceList':
        return {'items': _audiences};
      case 'audienceSave':
        final m = {'id': 'aud${++_n}', 'name': d['name'], 'text': 'Kayıtlı süzgeç', 'audience': d['audience'], 'count': _countFor(OpsApi.map(d['audience'])), 'by': 'Demo Kurucu'};
        _audiences.insert(0, m);
        return m;
      case 'audienceDelete':
        _audiences.removeWhere((x) => x['id'] == d['id']);
        return {'ok': true};
      case 'communities':
        final q = '${d['q'] ?? ''}'.toLowerCase();
        return {
          'items': [
            for (final c in const [
              {'id': 'c_kosu', 'name': 'Sabah Koşucuları', 'emoji': '🏃', 'members': 412},
              {'id': 'c_kitap', 'name': 'Kitap Kurtları', 'emoji': '📚', 'members': 388},
              {'id': 'c_foto', 'name': 'Şehir Fotoğrafçıları', 'emoji': '📷', 'members': 301},
              {'id': 'c_kamp', 'name': 'Kamp Ateşi', 'emoji': '🏕️', 'members': 276},
              {'id': 'c_kutu', 'name': 'Kutu Oyunu Geceleri', 'emoji': '🎲', 'members': 198},
              {'id': 'c_yemek', 'name': 'Mutfak Maceraları', 'emoji': '🍳', 'members': 164},
            ])
              if (q.isEmpty || '${c['name']}'.toLowerCase().contains(q)) c,
          ],
        };
      case 'upload':
        return {'url': d['kind'] == 'audio' ? 'https://firebasestorage.googleapis.com/v0/b/demo/o/notify_studio%2Fses.m4a?alt=media' : _img};
      case 'audit':
        return {'items': _audit, 'cursor': null};
      case 'configGet':
        return {'config': _config, 'audience': {'total': 12840, 'builtAt': now - 5 * 3600000}};
      case 'configSet':
        _config = {..._config, ...OpsApi.map(d['config'])};
        return {'config': _config};
      case 'rebuild':
        return {'total': 12840, 'shards': 4};
    }
    throw const AppFailure('Bilinmeyen işlem.');
  }
}
