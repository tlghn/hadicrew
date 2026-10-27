// Panel bölümleri: ortak model, kategori sıralaması ve yerel akıllı arama (27 Ekim 2026).
// Kurucu Paneli ve HADİ Crew aynı motoru kullanır. Saf mantık (widget yok) — test/panel_kit_test.dart.
//
// Arama: başlık, kategori, anahtar sözcükler (eski `keys` alanları + eş anlamlılar), kısa açıklama ve sekme içi bölümler.
// Türkçe normalizasyon (büyük/küçük, ı/i, aksan), basit kök/önek eşleşmesi ("anahtarları" ↔ "anahtar", "ayarla" ↔ "ayar"),
// yazım hatası toleransı (Damerau-Levenshtein), doğal dil sorgularında dolgu sözcükleri ("nasıl", "nerede", "istiyorum")
// yok sayılır. Sonuç başlık ve açıklamada eşleşen aralıklarla döner (vurgulama).
import 'package:flutter/widgets.dart' show IconData;

import 'tr_text.dart';

/// Bir panel sekmesi/bölümü. [id] kalıcıdır (adres çubuğu, sabitlenenler, son kullanılanlar, YZ yanıtı bunu kullanır).
class PanelEntry {
  const PanelEntry({
    required this.id,
    required this.title,
    required this.icon,
    required this.category,
    this.description = '',
    this.keys = '',
    this.sections = const [],
    this.pinned = false,
  });

  final String id, title, category, description;

  /// Kategorisinin en üstünde (alfabetik sıradan önce; kurucu 27 Ekim 14:40: "Etkinlikler" listesi grubun en üstünde).
  final bool pinned;
  final IconData icon;

  /// Aramada bulunması için ek sözcükler (eski `keys` + eş anlamlılar), boşlukla ayrılmış.
  final String keys;

  /// Sekmenin içindeki alt bölümler (ör. API anahtarları › "Google Haritalar"); YZ "ilgili bölüm"ü söyleyebilsin diye.
  final List<String> sections;
}

/// Kategorilere ayırır; kategoriler ve içlerindeki sekmeler Türk alfabesine göre sıralı ([PanelEntry.pinned] olanlar en üstte).
List<({String category, List<PanelEntry> entries})> groupByCategory(Iterable<PanelEntry> entries) {
  final by = <String, List<PanelEntry>>{};
  for (final e in entries) {
    (by[e.category] ??= []).add(e);
  }
  final cats = by.keys.toList()..sort(trCompare);
  return [
    for (final c in cats) (category: c, entries: by[c]!..sort((a, b) => a.pinned != b.pinned ? (a.pinned ? -1 : 1) : trCompare(a.title, b.title))),
  ];
}

/// Eşleşmenin türü (vurgulama ve puan için).
enum MatchKind { exact, prefix, inflected, stem, substring, fuzzy }

const _kindScore = <MatchKind, double>{
  MatchKind.exact: 1.0,
  MatchKind.prefix: .9,
  MatchKind.inflected: .85,
  MatchKind.stem: .8,
  MatchKind.substring: .6,
  MatchKind.fuzzy: .6,
};

/// Doğal dil sorgularındaki dolgu sözcükleri (katlanmış). Yalnız bunlardan oluşan sorguda yine de kullanılır.
const kSearchStopWords = <String>{
  've', 'ile', 'veya', 'ya', 'bir', 'bu', 'su', 'o', 'icin', 'gibi', 'nasil', 'nerede', 'neresi', 'nereden', 'nereye', 'ne', 'neyi',
  'mi', 'mu', 'ben', 'bana', 'beni', 'benim', 'sen', 'biz', 'istiyorum', 'isterim', 'lazim', 'gerek', 'gerekiyor', 'yapmak', 'yap',
  'yapabilirim', 'yapilir', 'olan', 'de', 'da', 'ki', 'en', 'cok', 'daha', 'hangi', 'kim', 'var', 'yok', 'acaba', 'bul', 'bulmak',
  'the', 'a', 'an', 'to', 'of', 'how', 'where', 'set', 'up',
};

/// Bir alan içinde eşleşen aralık [start, end) — asıl metindeki konumlar.
typedef TextRange2 = ({int start, int end});

class PanelHit {
  PanelHit(this.entry, this.score, {this.titleRanges = const [], this.descRanges = const [], this.via});
  final PanelEntry entry;

  /// 0–100+ (yüksek = daha iyi).
  final double score;
  final List<TextRange2> titleRanges, descRanges;

  /// Başlıkta değil de anahtar sözcükte/kategoride/bölümde eşleştiyse o sözcük (ör. "harita", "Google Haritalar").
  final String? via;
}

class _Field {
  _Field(this.text, this.weight) : folded = trFold(text) {
    var i = 0;
    for (final w in folded.split(' ')) {
      if (w.isNotEmpty) words.add((w: w, at: i, stem: trStem(w)));
      i += w.length + 1;
    }
  }
  final String text, folded;
  final double weight;
  final words = <({String w, int at, String stem})>[];
}

class _Doc {
  _Doc(this.e)
      : title = _Field(e.title, 1.0),
        keys = _Field(e.keys, .7),
        sections = _Field(e.sections.join(' · '), .7),
        category = _Field(e.category, .5),
        desc = _Field(e.description, .45);
  final PanelEntry e;
  final _Field title, keys, sections, category, desc;
  List<_Field> get fields => [title, keys, sections, category, desc];
}

/// Sorgu sözcüğü ile alan sözcüğü eşleşmesi (yoksa null).
MatchKind? matchWord(String q, String w, {String? qStem, String? wStem}) {
  if (q.isEmpty || w.isEmpty) return null;
  if (q == w) return MatchKind.exact;
  if (q.length >= 2 && w.startsWith(q)) return MatchKind.prefix;
  if (q.length == 1) return w.startsWith(q) ? MatchKind.prefix : null;
  if (w.length >= 3 && q.startsWith(w)) return MatchKind.inflected;
  final qs = qStem ?? trStem(q), ws = wStem ?? trStem(w);
  if (qs.length >= 3 && qs == ws) return MatchKind.stem;
  if (q.length >= 4 && w.contains(q)) return MatchKind.substring;
  if (q.length >= 4) {
    final tol = q.length >= 8 ? 2 : 1;
    if (editDistance(q, w, max: tol) <= tol) return MatchKind.fuzzy;
    // yazarken yazım hatası: "gemnı" ↔ "gemini", "bildirm" ↔ "bildirim…"
    if (q.length >= 5 && w.length > q.length && editDistance(q, w.substring(0, q.length), max: 1) <= 1) return MatchKind.fuzzy;
    if (q.length >= 5 && w.length > q.length && editDistance(q, w.substring(0, q.length + 1), max: 1) <= 1) return MatchKind.fuzzy;
  }
  return null;
}

/// Yerel arama motoru (girdiler değişmedikçe yeniden kullanılabilir).
class PanelSearchIndex {
  PanelSearchIndex(Iterable<PanelEntry> entries) : _docs = [for (final e in entries) _Doc(e)];
  final List<_Doc> _docs;

  List<PanelEntry> get entries => [for (final d in _docs) d.e];

  List<PanelHit> search(String query, {int limit = 12}) {
    final all = trTokens(query);
    if (all.isEmpty) return const [];
    final content = all.where((t) => !kSearchStopWords.contains(t)).toList();
    final toks = content.isEmpty ? all : content;
    final stems = [for (final t in toks) trStem(t)];
    final qFold = toks.join(' ');
    final hits = <PanelHit>[];
    for (final d in _docs) {
      var sum = 0.0;
      var matched = 0;
      final tr = <TextRange2>[], dr = <TextRange2>[];
      String? via;
      double viaScore = 0;
      for (var i = 0; i < toks.length; i++) {
        final q = toks[i];
        var best = 0.0;
        for (final f in d.fields) {
          for (final w in f.words) {
            final k = matchWord(q, w.w, qStem: stems[i], wStem: w.stem);
            if (k == null) continue;
            final s = f.weight * _kindScore[k]!;
            if (identical(f, d.title)) tr.add(_range(w, q, k, f.folded));
            if (identical(f, d.desc)) dr.add(_range(w, q, k, f.folded));
            if (s > best) best = s;
            if (!identical(f, d.title) && !identical(f, d.desc) && s > viaScore) {
              viaScore = s;
              via = identical(f, d.sections) ? _sectionAt(d.e.sections, w.at) : _wordAt(f.text, w.at, w.w.length);
            }
          }
        }
        if (best > 0) matched++;
        sum += best;
      }
      if (matched == 0) continue;
      final coverage = matched / toks.length;
      var score = sum / toks.length * 100;
      // Çok sözcüklü sorguda kapsama önemli: yarıdan azı eşleştiyse puan düşer.
      if (toks.length > 1 && coverage < .5) score *= .6;
      final tf = d.title.folded.trim().replaceAll(RegExp(r' +'), ' ');
      if (tf == qFold) {
        score += 30;
      } else if (tf.startsWith(qFold)) {
        score += 15;
      }
      if (score < 22) continue;
      // Başlıkta eşleştiyse "via" gereksiz.
      final titleHit = tr.isNotEmpty;
      hits.add(PanelHit(d.e, score, titleRanges: _merge(tr), descRanges: _merge(dr), via: titleHit ? null : via));
    }
    hits.sort((a, b) {
      final c = b.score.compareTo(a.score);
      return c != 0 ? c : trCompare(a.entry.title, b.entry.title);
    });
    return hits.length > limit ? hits.sublist(0, limit) : hits;
  }
}

TextRange2 _range(({String w, int at, String stem}) w, String q, MatchKind k, String folded) {
  switch (k) {
    case MatchKind.exact:
    case MatchKind.prefix:
      return (start: w.at, end: w.at + (q.length < w.w.length ? q.length : w.w.length));
    case MatchKind.substring:
      final i = w.w.indexOf(q);
      return (start: w.at + i, end: w.at + i + q.length);
    case MatchKind.inflected:
    case MatchKind.stem:
    case MatchKind.fuzzy:
      return (start: w.at, end: w.at + w.w.length);
  }
}

String _wordAt(String text, int at, int len) => at + len <= text.length ? text.substring(at, at + len) : text;

String? _sectionAt(List<String> sections, int at) {
  var pos = 0;
  for (final s in sections) {
    if (at < pos + s.length) return s;
    pos += s.length + 3; // ' · '
  }
  return sections.isEmpty ? null : sections.last;
}

List<TextRange2> _merge(List<TextRange2> r) {
  if (r.length < 2) return r;
  final s = [...r]..sort((a, b) => a.start - b.start);
  final out = <TextRange2>[s.first];
  for (final x in s.skip(1)) {
    final l = out.last;
    if (x.start <= l.end) {
      out[out.length - 1] = (start: l.start, end: x.end > l.end ? x.end : l.end);
    } else {
      out.add(x);
    }
  }
  return out;
}

/// Yerel sonuçlar zayıf mı (YZ önerilerini kendiliğinden getirmek için)?
bool weakResults(List<PanelHit> hits) => hits.isEmpty || hits.first.score < 60 || (hits.length == 1 && hits.first.score < 80);

/// YZ'ye kendiliğinden sorulacak kadar uzun mu: en az 3 sözcük ya da 12 karakter.
bool aiEligible(String q) {
  final t = q.trim();
  return t.length >= 12 || t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length >= 3;
}
