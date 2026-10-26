// Panel gezinme tercihleri (27 Ekim 2026): sabitlenenler (★), son kullanılanlar (son 5) ve kategori aç/kapa durumu.
// Bu cihazda saklanır (web: localStorage; okunamaz/yazılamazsa bellekte kalır, panel yine çalışır). Sekmeler kimlikle (id)
// tutulur; sırası/dizini değişse de bozulmaz. Artık var olmayan id'ler gösterilirken atlanır.
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'panel_store_stub.dart' if (dart.library.js_interop) 'panel_store_web.dart';

class PanelPrefs extends ChangeNotifier {
  PanelPrefs._(this.ns) {
    _load();
  }

  /// Panel başına tek örnek: 'founder' | 'crew'.
  factory PanelPrefs.of(String ns) => _all.putIfAbsent(ns, () => PanelPrefs._(ns));
  static final Map<String, PanelPrefs> _all = {};

  /// Testler için: belleği sıfırla.
  @visibleForTesting
  static void resetForTest() => _all.clear();

  static const maxRecent = 5;
  static const maxPins = 24;

  final String ns;
  final List<String> _pins = [];
  final List<String> _recent = [];
  final Map<String, bool> _open = {};

  String get _key => 'hadi.panel.$ns.v1';

  List<String> get pins => List.unmodifiable(_pins);
  List<String> get recent => List.unmodifiable(_recent);
  bool isPinned(String id) => _pins.contains(id);

  /// Kullanıcının bu kategori için seçtiği durum (hiç dokunmadıysa null).
  bool? categoryOpen(String category) => _open[category];

  void togglePin(String id) {
    if (!_pins.remove(id)) {
      _pins.add(id);
      if (_pins.length > maxPins) _pins.removeAt(0);
    }
    _save();
    notifyListeners();
  }

  /// Bölüm açıldı: son kullanılanların başına.
  void touch(String id) {
    if (_recent.isNotEmpty && _recent.first == id) return;
    _recent
      ..remove(id)
      ..insert(0, id);
    while (_recent.length > maxRecent) {
      _recent.removeLast();
    }
    _save();
    notifyListeners();
  }

  void setCategoryOpen(String category, bool open) {
    _open[category] = open;
    _save();
    notifyListeners();
  }

  void setAllCategories(Iterable<String> categories, bool open) {
    for (final c in categories) {
      _open[c] = open;
    }
    _save();
    notifyListeners();
  }

  void _load() {
    try {
      final raw = panelStoreRead(_key);
      if (raw == null || raw.isEmpty) return;
      final m = jsonDecode(raw);
      if (m is! Map) return;
      List<String> ids(Object? v) => v is List ? [for (final x in v) if (x is String && x.length <= 80) x] : const [];
      _pins.addAll(ids(m['pins']).take(maxPins));
      _recent.addAll(ids(m['recent']).take(maxRecent));
      final o = m['open'];
      if (o is Map) {
        for (final e in o.entries) {
          if (e.key is String && e.value is bool) _open[e.key as String] = e.value as bool;
        }
      }
    } catch (_) {
      // bozuk kayıt: boş başla
    }
  }

  void _save() {
    try {
      panelStoreWrite(_key, jsonEncode({'pins': _pins, 'recent': _recent, 'open': _open}));
    } catch (_) {}
  }
}
