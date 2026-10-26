// Tarayıcı: localStorage (bu cihazda kalır). Gizli pencere / engellenmiş site verisinde sessizce geçer.
import 'package:web/web.dart' as web;

String? panelStoreRead(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

void panelStoreWrite(String key, String value) {
  try {
    web.window.localStorage.setItem(key, value);
  } catch (_) {}
}
