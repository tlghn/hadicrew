// Panel gezinmesi ve araması (lib/panel_kit; 27 Ekim 2026): Türkçe sıralama, normalizasyon, kök/bulanık eşleşme, yerel arama
// sıralaması ve vurgu aralıkları, YZ yanıt doğrulama (uydurma id atılır), sabitlenenler / son kullanılanlar, Crew kategorileri.
//   flutter test test/panel_kit_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hadi_crew/panel_kit/panel_ai.dart';
import 'package:hadi_crew/panel_kit/panel_prefs.dart';
import 'package:hadi_crew/panel_kit/panel_search.dart';
import 'package:hadi_crew/panel_kit/tr_text.dart';

PanelEntry _e(String id, String title, String cat, {String desc = '', String keys = '', List<String> sections = const []}) =>
    PanelEntry(id: id, title: title, icon: Icons.circle, category: cat, description: desc, keys: keys, sections: sections);

final _entries = [
  _e('api-anahtarlari', 'API anahtarları', 'Altyapı ve entegrasyonlar',
      desc: 'Harici servis anahtarları: Google Haritalar, fal.ai, Replicate',
      keys: 'api anahtar key gemini harita maps fal carto replicate google cloud google maps',
      sections: ['Google Haritalar (Maps) anahtarı', 'fal.ai (AI video) anahtarı']),
  _e('sms-saglayici', 'SMS sağlayıcı', 'Altyapı ve entegrasyonlar', desc: 'Telefonla giriş SMS kodu sağlayıcısı', keys: 'sms otp doğrulama kodu giriş telefon verimor'),
  _e('yapay-zeka', 'Yapay zekâ', 'Yapay zekâ', desc: 'Model, bölge, moderasyon talimatları', keys: 'ai yapay zeka model gemini istem'),
  _e('yapay-zeka-icerigi', 'Yapay Zeka İçeriği', 'Yapay zekâ', keys: 'etiket yz ai'),
  _e('iadeler', 'İadeler', 'Ekonomi ve ödemeler', desc: 'Satın alma iade talepleri', keys: 'iade geri ödeme'),
  _e('elmas-akce', 'Elmas & Akçe', 'Ekonomi ve ödemeler', keys: 'elmas akçe kur'),
  _e('odemeler', 'Ödemeler', 'Ekonomi ve ödemeler', keys: 'ödeme iyzico'),
  _e('kimlik-dogrulama', 'Kimlik doğrulama', 'Doğrulama ve incelemeler', keys: 'kimlik tc doğrulama'),
  _e('bildirim-studyosu-ayarlari', 'Bildirim stüdyosu ayarları', 'İletişim ve bildirimler', keys: 'bildirim push kampanya'),
  _e('ipuclari', 'İpuçları', 'İletişim ve bildirimler', keys: 'ipucu dürtme'),
  _e('uyeler', 'Üyeler', 'Üyeler ve roller', keys: 'üye ara bul'),
  _e('2-el-ayarlari', '2. El ayarları', 'Mağaza ve ticaret', keys: 'ikinci el'),
  _e('ai-guvenligi', 'AI güvenliği', 'Güvenlik ve gizlilik', keys: 'güvenlik enjeksiyon'),
];

List<String> _ids(List<PanelHit> h) => [for (final x in h) x.entry.id];

void main() {
  group('Türkçe sıralama', () {
    test('Türk alfabesi: c<ç, g<ğ<h, ı<i, o<ö, s<ş, u<ü; büyük/küçük ve noktalama birincil düzeyde yok', () {
      final words = ['Şeker', 'Ürün', 'İnce', 'Çay', 'Ilık', 'ah', 'Ödeme', 'ağ', 'Sabun', 'Oyun', 'Cam', 'Uzay', 'ag', 'Hız', 'H.A.D.İ. hesabı'];
      words.sort(trCompare);
      expect(words, ['ag', 'ağ', 'ah', 'Cam', 'Çay', 'H.A.D.İ. hesabı', 'Hız', 'Ilık', 'İnce', 'Oyun', 'Ödeme', 'Sabun', 'Şeker', 'Uzay', 'Ürün']);
    });
    test('rakam önce; kısa önek önce; â = a', () {
      final words = ['Yapay Zeka İçeriği', 'API anahtarları', '2. El ayarları', 'AI güvenliği', 'Yapay zekâ', 'Adres belgeleri'];
      words.sort(trCompare);
      expect(words, ['2. El ayarları', 'Adres belgeleri', 'AI güvenliği', 'API anahtarları', 'Yapay zekâ', 'Yapay Zeka İçeriği']);
    });
    test('kategoriler ve içleri A–Z (groupByCategory)', () {
      final g = groupByCategory(_entries);
      final cats = [for (final x in g) x.category];
      expect(cats, [
        'Altyapı ve entegrasyonlar', 'Doğrulama ve incelemeler', 'Ekonomi ve ödemeler', 'Güvenlik ve gizlilik', 'İletişim ve bildirimler',
        'Mağaza ve ticaret', 'Üyeler ve roller', 'Yapay zekâ',
      ]);
      final eko = g.firstWhere((x) => x.category == 'Ekonomi ve ödemeler').entries.map((e) => e.title).toList();
      expect(eko, ['Elmas & Akçe', 'İadeler', 'Ödemeler']);
      final ilet = g.firstWhere((x) => x.category == 'İletişim ve bildirimler').entries.map((e) => e.title).toList();
      expect(ilet, ['Bildirim stüdyosu ayarları', 'İpuçları']);
    });
  });

  group('normalizasyon ve eşleşme', () {
    test('trFold: Türkçe küçük harf + aksansız, uzunluk korunur', () {
      expect(trFold('İSTANBUL Iğdır'), 'istanbul igdir');
      expect(trFold('Elmas & Akçe'), 'elmas   akce');
      for (final s in ['H.A.D.İ. hesabı', 'Yapay zekâ', 'ŞÇĞÜÖİI', '2. El ✨ ayarları']) {
        expect(trFold(s).length, s.length, reason: s);
      }
    });
    test('trStem: yaygın ekler', () {
      expect(trStem('anahtarlari'), 'anahtar');
      expect(trStem('ayarla'), 'ayar');
      expect(trStem('bildirimleri'), 'bildirim');
      expect(trStem('uyeler'), 'uye');
      expect(trStem('ses'), 'ses'); // kök en az 3 harf
    });
    test('editDistance: yer değişimi tek hata, sınır', () {
      expect(editDistance('gemnii', 'gemini'), 1);
      expect(editDistance('odeme', 'odeme'), 0);
      expect(editDistance('kimlik', 'kimlig'), 1);
      expect(editDistance('abc', 'xyzxyz', max: 2), 3);
    });
    test('matchWord türleri', () {
      expect(matchWord('api', 'api'), MatchKind.exact);
      expect(matchWord('anah', 'anahtar'), MatchKind.prefix);
      expect(matchWord('anahtarlari', 'anahtar'), MatchKind.inflected);
      expect(matchWord('bildirm', 'bildirim'), MatchKind.fuzzy);
      expect(matchWord('xyz', 'anahtar'), isNull);
    });
  });

  group('yerel arama', () {
    final idx = PanelSearchIndex(_entries);
    test('başlık dışı: "google api ayarla" → API anahtarları, başlıkta "API" vurgulu', () {
      final h = idx.search('google api ayarla');
      expect(h.first.entry.id, 'api-anahtarlari');
      expect(h.first.titleRanges.first, (start: 0, end: 3));
    });
    test('büyük harf / İ: "İADE" → İadeler (vurgu 0–4)', () {
      final h = idx.search('İADE');
      expect(h.first.entry.id, 'iadeler');
      expect(h.first.titleRanges.first, (start: 0, end: 4));
    });
    test('aksansız ve & işareti: "elmas akce" → Elmas & Akçe', () {
      expect(idx.search('elmas akce').first.entry.id, 'elmas-akce');
    });
    test('çekimli: "anahtarları" → API anahtarları', () {
      expect(idx.search('anahtarları').first.entry.id, 'api-anahtarlari');
    });
    test('yazım hatası: "gemnı" → Yapay zekâ; "bildirm" → Bildirim stüdyosu', () {
      expect(_ids(idx.search('gemnı')), contains('yapay-zeka'));
      expect(idx.search('bildirm').first.entry.id, 'bildirim-studyosu-ayarlari');
    });
    test('dolgu sözcükleri yok sayılır: "kimlik doğrulama nerede"', () {
      expect(idx.search('kimlik doğrulama nerede').first.entry.id, 'kimlik-dogrulama');
    });
    test('anahtar sözcükle bulunursa nedeni (via): "harita" → API anahtarları', () {
      final h = idx.search('harita');
      expect(h.first.entry.id, 'api-anahtarlari');
      expect(h.first.via, isNotNull);
    });
    test('alt bölümden: "maps" bulunur', () {
      expect(idx.search('maps').first.entry.id, 'api-anahtarlari');
    });
    test('ilgisiz sorgu sonuç vermez; zayıflık ve YZ uygunluğu', () {
      final h = idx.search('qqqq zzzz');
      expect(h, isEmpty);
      expect(weakResults(h), isTrue);
      expect(weakResults(idx.search('iadeler')), isFalse);
      expect(aiEligible('google api ayarla'), isTrue);
      expect(aiEligible('kullanıcıyı bul'), isTrue); // 15 karakter
      expect(aiEligible('iade'), isFalse);
    });
  });

  group('YZ yanıt doğrulama', () {
    final allowed = {for (final e in _entries) e.id};
    test('uydurma id atılır, tekrar atılır, en çok 5, bölüm/gerekçe kısaltılır', () {
      final r = parsePanelAiResponse({
        'ok': true,
        'intent': 'Google Haritalar anahtarını ayarlamak',
        'results': [
          {'id': 'google-konsolu', 'reason': 'uydurma'},
          {'id': 'api-anahtarlari', 'reason': 'Google Haritalar anahtarı burada.', 'section': 'Google Haritalar (Maps) anahtarı'},
          {'id': 'api-anahtarlari', 'reason': 'tekrar'},
          {'id': 'yapay-zeka', 'reason': 'x' * 400},
          {'id': 'iadeler'}, {'id': 'uyeler'}, {'id': 'odemeler'}, {'id': 'ipuclari'},
          'çöp', 42,
        ],
      }, allowed);
      expect(r.ok, isTrue);
      expect(r.items.map((x) => x.id), ['api-anahtarlari', 'yapay-zeka', 'iadeler', 'uyeler', 'odemeler']);
      expect(r.items.first.section, 'Google Haritalar (Maps) anahtarı');
      expect(r.items[1].reason.length, lessThanOrEqualTo(200));
      expect(r.intent, 'Google Haritalar anahtarını ayarlamak');
    });
    test('görünmeyen sekme (crew yetkisi dışı) atılır', () {
      final r = parsePanelAiResponse({'ok': true, 'results': [{'id': 'api-anahtarlari'}, {'id': 'kuyruk'}]}, {'kuyruk'});
      expect(r.items.map((x) => x.id), ['kuyruk']);
    });
    test('hata kodları ve bozuk yanıt → sessiz hata metni', () {
      expect(parsePanelAiResponse({'ok': false, 'error': 'rate'}, allowed).error, contains('sık'));
      expect(parsePanelAiResponse({'ok': false, 'error': 'unavailable'}, allowed).error, 'YZ şu an yanıt veremedi');
      expect(parsePanelAiResponse('x', allowed).error, 'YZ şu an yanıt veremedi');
      expect(parsePanelAiResponse(null, allowed).ok, isFalse);
    });
    test('istek gövdesi yalnızca meta veri taşır', () {
      final items = panelAiItems(_entries.take(2));
      expect(items.first.keys.toSet(), {'id', 't', 'c', 'd', 'k', 's'});
      expect(items[1].containsKey('s'), isFalse);
    });
  });

  group('sabitlenenler ve son kullanılanlar', () {
    setUp(PanelPrefs.resetForTest);
    test('son 5, tekrar başa alınır', () {
      final p = PanelPrefs.of('t1');
      for (final id in ['a', 'b', 'c', 'd', 'e', 'f', 'c']) {
        p.touch(id);
      }
      expect(p.recent, ['c', 'f', 'e', 'd', 'b']);
    });
    test('sabitle / kaldır, kategori durumu', () {
      final p = PanelPrefs.of('t2');
      p.togglePin('x');
      p.togglePin('y');
      expect(p.pins, ['x', 'y']);
      p.togglePin('x');
      expect(p.isPinned('x'), isFalse);
      expect(p.categoryOpen('Yapay zekâ'), isNull);
      p.setCategoryOpen('Yapay zekâ', true);
      expect(p.categoryOpen('Yapay zekâ'), isTrue);
    });
  });

  // Crew bölümleri lib/app/sections.dart kaynağından okunur (dosya web'e bağlı ekranları içe aktardığı için VM testinde
  // doğrudan yüklenemez).
  group('Crew bölümleri', () {
    final src = File('lib/app/sections.dart').readAsStringSync();
    final labels = {
      for (final m in RegExp(r"^  (\w+)\('([^']+)'\)[,;]", multiLine: true).allMatches(src)) m.group(1)!: m.group(2)!,
    };
    final blocks = src.split('CrewSection(').skip(2).toList(); // [0]: dosya başı, [1]: sınıf tanımı
    String? f(String b, String name) => RegExp("$name: '((?:[^'\\\\]|\\\\.)*)'").firstMatch(b)?.group(1);
    final sections = [
      for (final b in blocks)
        if (f(b, 'id') != null)
          (id: f(b, 'id')!, title: f(b, 'title')!, sub: f(b, 'subtitle') ?? '', keys: f(b, 'keys') ?? '', group: RegExp(r'group: CrewGroup\.(\w+)').firstMatch(b)?.group(1)),
    ];

    test('her bölümün kategorisi ve anahtar sözcükleri var; kimlikler tekil; Genel yalnız Pano', () {
      expect(sections.length, greaterThan(30));
      expect(labels['genel'], 'Genel');
      final ids = <String>{};
      for (final s in sections) {
        expect(ids.add(s.id), isTrue, reason: 'tekrarlı kimlik ${s.id}');
        expect(labels[s.group], isNotNull, reason: '${s.id} kategorisiz');
        expect(s.keys.trim(), isNotEmpty, reason: '${s.id} anahtar sözcük yok');
        if (s.group == 'genel') expect(s.id, 'pano');
      }
    });
    final entries = [
      for (final s in sections)
        if (s.group != 'genel') _e(s.id, s.title, labels[s.group]!, desc: s.sub, keys: s.keys),
    ];
    test('kategori menüsü A–Z ve bütün bölümleri kapsar', () {
      final g = groupByCategory(entries);
      final cats = [for (final x in g) x.category];
      expect(cats, [...cats]..sort(trCompare));
      expect(cats.first, 'Destek ve geri bildirim');
      expect(g.fold<int>(0, (a, x) => a + x.entries.length), sections.length - 1);
      for (final x in g) {
        final titles = x.entries.map((e) => e.title).toList();
        expect(titles, [...titles]..sort(trCompare));
      }
    });
    test('Crew araması: "kimlik onayı" → Kimlik doğrulama; "2. el dolandırıcı" → 2. El inceleme; "push gönder" → Bildirim stüdyosu', () {
      final idx = PanelSearchIndex(entries);
      expect(idx.search('kimlik onayı').first.entry.id, 'kimlik');
      expect(idx.search('2. el dolandırıcı').first.entry.id, 'ikinci-el');
      expect(idx.search('push gönder').first.entry.id, 'bildirim-studyosu');
    });
  });
}
