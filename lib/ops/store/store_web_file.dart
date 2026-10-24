// HADİ Crew — Mağaza: tarayıcıda dosya indirme ve yazdırma (Crew ve Kurucu Paneli yalnızca web'de çalışır).
// Baskı dosyası (PNG) Blob olarak indirilir; sipariş fişi yeni sekmede açılan basit HTML sayfasıdır, sayfa açılınca
// tarayıcının yazdırma penceresi gelir (PDF'e kaydet de oradan). Sunucuya hiçbir şey gönderilmez.
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// [bytes]'ı [fileName] adıyla indirir.
void storeDownloadBytes(Uint8List bytes, String fileName, {String mime = 'image/png'}) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.append(a);
  a.click();
  a.remove();
  // İndirme başladıktan sonra adresi bırak.
  Future<void>.delayed(const Duration(seconds: 20), () => web.URL.revokeObjectURL(url));
}

/// [html] sayfasını yeni sekmede açar (sayfa kendi `window.print()`ini çağırır). Açılamazsa (açılır pencere engeli) false.
bool storeOpenPrintable(String html) {
  final blob = web.Blob([html.toJS].toJS, web.BlobPropertyBag(type: 'text/html;charset=utf-8'));
  final url = web.URL.createObjectURL(blob);
  final w = web.window.open(url, '_blank');
  Future<void>.delayed(const Duration(minutes: 2), () => web.URL.revokeObjectURL(url));
  return w != null;
}

/// HTML içine güvenle yazılacak metin.
String storeHtmlEscape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;');
