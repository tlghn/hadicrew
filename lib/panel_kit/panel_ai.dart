// "✨ Yapay zekâya sor" — panel aramasında niyet anlama (27 Ekim 2026).
// Sunucu: functions/src/panel_search.ts (+ panel_search_core.ts), `crewDash` callable'ının `panelSearch` işlemi
// (yonetim grubu; yeni Cloud Function yok). Yalnızca sorgu ve kullanıcının GÖREBİLDİĞİ sekmelerin meta verisi gider
// (id, başlık, kategori, açıklama, anahtar sözcükler, alt bölümler) — kişisel veri yok. YZ yalnızca başlık önerir; hiçbir
// işlem yapmaz. Yanıt burada da doğrulanır: listede olmayan id atılır. Hata/zaman aşımında arama yerel sonuçlarla kalır.
import 'package:hadi/data/ops_api.dart';

import 'panel_search.dart';

class PanelAiSuggestion {
  const PanelAiSuggestion({required this.id, required this.reason, this.section});
  final String id, reason;

  /// Sekmenin içindeki ilgili bölüm (biliniyorsa), ör. "Google Haritalar".
  final String? section;
}

class PanelAiResult {
  const PanelAiResult({this.items = const [], this.intent, this.error});
  final List<PanelAiSuggestion> items;

  /// YZ'nin anladığı niyet (kısa cümle).
  final String? intent;

  /// Kullanıcıya gösterilecek kısa hata ("YZ şu an yanıt veremedi"); başarıda null.
  final String? error;

  bool get ok => error == null;
}

/// Sunucuya giden sekme listesi (alan adları kısa; sunucu sınırları: panel_search_core.ts › PS_LIMITS).
List<Map<String, Object?>> panelAiItems(Iterable<PanelEntry> entries) => [
      for (final e in entries)
        {
          'id': e.id,
          't': e.title,
          'c': e.category,
          if (e.description.isNotEmpty) 'd': e.description.length > 200 ? e.description.substring(0, 200) : e.description,
          if (e.keys.isNotEmpty) 'k': e.keys.length > 300 ? e.keys.substring(0, 300) : e.keys,
          if (e.sections.isNotEmpty) 's': e.sections.take(12).toList(),
        },
    ];

String _str(Object? v, int max) {
  final s = v is String ? v.replaceAll(RegExp(r'[\u0000-\u001f<>]'), ' ').trim() : '';
  return s.length > max ? '${s.substring(0, max - 1)}…' : s;
}

/// Sunucu yanıtını doğrular: yalnızca [allowed] içindeki id'ler, tekrarsız, en çok 5; gerekçe/bölüm kısaltılır.
PanelAiResult parsePanelAiResponse(Object? raw, Set<String> allowed) {
  if (raw is! Map) return const PanelAiResult(error: 'YZ şu an yanıt veremedi');
  if (raw['ok'] == false) {
    final code = '${raw['error'] ?? ''}';
    return PanelAiResult(error: switch (code) {
      'rate' => 'Çok sık soruldu; biraz sonra yeniden dene.',
      'guard' => 'Bu soru yapay zekâya iletilmedi.',
      _ => 'YZ şu an yanıt veremedi',
    });
  }
  final list = raw['results'];
  final out = <PanelAiSuggestion>[];
  final seen = <String>{};
  if (list is List) {
    for (final x in list) {
      if (x is! Map) continue;
      final id = x['id'];
      if (id is! String || !allowed.contains(id) || !seen.add(id)) continue;
      final section = _str(x['section'], 80);
      out.add(PanelAiSuggestion(id: id, reason: _str(x['reason'], 200), section: section.isEmpty ? null : section));
      if (out.length >= 5) break;
    }
  }
  final intent = _str(raw['intent'], 140);
  return PanelAiResult(items: out, intent: intent.isEmpty ? null : intent);
}

/// YZ'ye sorar. Hiç fırlatmaz: hata/zaman aşımında `error` dolu sonuç döner.
typedef PanelAiAsk = Future<PanelAiResult> Function(String query, List<PanelEntry> visible);

/// Varsayılan sorucu: `crewDash` › `panelSearch` (kurucu/crew rolü; sunucu hız sınırlı).
PanelAiAsk panelAiAsker(String panel) => (query, visible) async {
      try {
        final r = await OpsApi.call('crewDash', 'panelSearch', {'panel': panel, 'q': query, 'items': panelAiItems(visible)})
            .timeout(const Duration(seconds: 15));
        return parsePanelAiResponse(r, {for (final e in visible) e.id});
      } catch (_) {
        return const PanelAiResult(error: 'YZ şu an yanıt veremedi');
      }
    };
