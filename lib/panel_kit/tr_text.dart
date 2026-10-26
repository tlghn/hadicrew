// Türkçe metin yardımcıları (panel gezinmesi ve araması; 27 Ekim 2026). Saf Dart: Flutter'a bağlı değil, birim testli
// (test/panel_kit_test.dart). Kurucu Paneli (hadifounder) bu dosyayı `package:hadi_crew/panel_kit/...` ile kullanır.
//
//  trLower   Türkçe küçük harf (I → ı, İ → i), uzunluğu korur
//  trFold    arama biçimi: küçük harf + aksansız (ç→c, ğ→g, ı→i, ö→o, ş→s, ü→u, â→a…), harf/rakam dışı → boşluk; uzunluğu
//            KORUR (vurgulama için konumlar asıl metinle aynı kalır)
//  trCompare Türk alfabesi sıralaması (a b c ç d e f g ğ h ı i j k l m n o ö p r s ş t u ü v y z; rakamlar önce)
//  trStem    kaba kök: yaygın çekim/yapım eklerini atar ("anahtarları" → "anahtar", "ayarla" → "ayar")
//  editDistance  Damerau (bitişik harf yer değişimi) + Levenshtein, en çok [max]'a kadar hesaplar

/// Türkçe küçük harf; her kod birimi tek kod birimine eşlenir (uzunluk korunur).
String trLower(String s) {
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == 'I') {
      b.write('ı');
    } else if (c == 'İ') {
      b.write('i');
    } else {
      final l = c.toLowerCase();
      b.write(l.length == 1 ? l : c);
    }
  }
  return b.toString();
}

const _fold = <String, String>{
  'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u', 'â': 'a', 'î': 'i', 'û': 'u',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'á': 'a', 'à': 'a', 'ä': 'a', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'ú': 'u', 'ù': 'u',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'ñ': 'n', 'ß': 's',
};

bool _alnum(int u) => (u >= 0x30 && u <= 0x39) || (u >= 0x61 && u <= 0x7a);

/// Arama biçimi. Uzunluk asıl metinle aynıdır: `trFold(s)[i]`, `s[i]`nin karşılığıdır.
String trFold(String s) {
  final low = trLower(s);
  final b = StringBuffer();
  for (var i = 0; i < low.length; i++) {
    final c = low[i];
    final f = _fold[c] ?? c;
    b.write(_alnum(f.codeUnitAt(0)) ? f : ' ');
  }
  return b.toString();
}

/// Sözcüklere böler (katlanmış).
List<String> trTokens(String s) => trFold(s).split(' ').where((w) => w.isNotEmpty).toList();

// ---------------------------------------------------------------- sıralama

const _alphabet = '0123456789abcçdefgğhıijklmnoöpqrsştuüvwxyz';
final Map<String, int> _rank = {for (var i = 0; i < _alphabet.length; i++) _alphabet[i]: i};
final _letter = RegExp(r'\p{L}', unicode: true);
const _secondary = <String, String>{'â': 'a', 'î': 'i', 'û': 'u', 'é': 'e', 'á': 'a', 'ó': 'o', 'ú': 'u', 'í': 'i', 'ä': 'a'};

/// Birincil sıra anahtarı: boşluk en küçük (-1), noktalama yok sayılır, bilinmeyen karakter alfabenin sonuna.
List<int> _key(String s) {
  final low = trLower(s);
  final out = <int>[];
  for (var i = 0; i < low.length; i++) {
    var c = low[i];
    c = _secondary[c] ?? c;
    final r = _rank[c];
    if (r != null) {
      out.add(r);
    } else if (c == ' ' || c == '\t') {
      if (out.isNotEmpty && out.last != -1) out.add(-1);
    } else if (_letter.hasMatch(c)) {
      out.add(1000 + c.codeUnitAt(0));
    }
    // noktalama / simge: yok sayılır ("H.A.D.İ." → "hadi")
  }
  while (out.isNotEmpty && out.last == -1) {
    out.removeLast();
  }
  return out;
}

/// Türk alfabesine göre karşılaştırır (büyük/küçük harf ve noktalama birincil düzeyde yok sayılır).
int trCompare(String a, String b) {
  final ka = _key(a), kb = _key(b);
  final n = ka.length < kb.length ? ka.length : kb.length;
  for (var i = 0; i < n; i++) {
    final d = ka[i] - kb[i];
    if (d != 0) return d;
  }
  if (ka.length != kb.length) return ka.length - kb.length;
  return a.compareTo(b); // eşitlikte kararlı
}

// ---------------------------------------------------------------- kök

/// Katlanmış (aksansız) biçimdeki yaygın ekler — uzundan kısaya.
const _suffixes = <String>[
  'lerinden', 'larindan', 'lerinde', 'larinda', 'lerini', 'larini', 'lerine', 'larina', 'leriyle', 'lariyla',
  'imizi', 'umuzu', 'iniz', 'unuz', 'imiz', 'umuz', 'leri', 'lari', 'ler', 'lar',
  'iyor', 'uyor', 'mak', 'mek', 'yla', 'yle', 'nin', 'nun', 'dan', 'den', 'tan', 'ten', 'nda', 'nde', 'sini', 'sunu',
  'lik', 'luk', 'siz', 'suz', 'si', 'su', 'la', 'le', 'da', 'de', 'ta', 'te', 'ya', 'ye', 'yi', 'yu', 'in', 'un', 'ni', 'nu',
  'i', 'u', 'a', 'e',
];

/// Kaba Türkçe kök (katlanmış girdi beklenir; en çok iki ek atar, kök en az 3 harf kalır).
String trStem(String w) {
  var s = w;
  for (var round = 0; round < 2; round++) {
    var cut = false;
    for (final x in _suffixes) {
      if (s.length - x.length >= 3 && s.endsWith(x)) {
        s = s.substring(0, s.length - x.length);
        cut = true;
        break;
      }
    }
    if (!cut) break;
  }
  return s;
}

// ---------------------------------------------------------------- bulanık eşleşme

/// Damerau–Levenshtein (bitişik yer değişimi tek hata) uzaklığı; [max] aşılınca `max + 1` döner.
int editDistance(String a, String b, {int max = 3}) {
  if ((a.length - b.length).abs() > max) return max + 1;
  final n = a.length, m = b.length;
  if (n == 0) return m;
  if (m == 0) return n;
  var prev2 = List<int>.filled(m + 1, 0);
  var prev = List<int>.generate(m + 1, (j) => j);
  var cur = List<int>.filled(m + 1, 0);
  for (var i = 1; i <= n; i++) {
    cur[0] = i;
    var rowMin = cur[0];
    for (var j = 1; j <= m; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = prev[j] + 1;
      if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
      if (prev[j - 1] + cost < v) v = prev[j - 1] + cost;
      if (i > 1 && j > 1 && a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) && a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
        if (prev2[j - 2] + 1 < v) v = prev2[j - 2] + 1;
      }
      cur[j] = v;
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > max) return max + 1;
    final t = prev2;
    prev2 = prev;
    prev = cur;
    cur = t;
  }
  return prev[m] > max ? max + 1 : prev[m];
}
