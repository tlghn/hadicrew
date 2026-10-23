{{flutter_js}}
{{flutter_build_config}}

// Flutter'ın service worker'ı kaydedilmez (uygulama dosyalarını önbelleğe alıp eski sürümü açtırıyordu).
// main.dart.js sürüm etiketiyle istenir (index.html › HADI_BUILD; önbellekteki eski kopya kullanılmaz).
if (window.HADI_BUILD && _flutter.buildConfig && _flutter.buildConfig.builds) {
  for (const b of _flutter.buildConfig.builds) {
    if (b.mainJsPath) b.mainJsPath += (b.mainJsPath.indexOf('?') < 0 ? '?' : '&') + 'v=' + window.HADI_BUILD;
  }
}
_flutter.loader.load();
