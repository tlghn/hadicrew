import 'dart:math' as math;

import 'package:hadi/data/ops_api.dart';
import 'package:hadi/data/services.dart';

/// Pano verisi (functions/src/crew_dash.ts › `crewDash`). Yalnızca çağıranın yetkisindeki kuyruklar döner.
class CrewDash {
  const CrewDash({required this.access, required this.role, required this.counts, this.series, required this.at, this.partial = false});

  /// Erişilebilen kuyruklar (crew_dash.ts › QUEUES): applications, reports, modFlags, aiLabel, liveReports, tickets, idReviews,
  /// addressReviews, kahveReviews, businessApps/Events/Payouts/Disputes, courierApps/Cases/Payouts, creatorReviews,
  /// secondhand, storeOrders, proLicenses, notifyApprovals.
  final Set<String> access;

  /// founder | admin | moderator | operator
  final String role;
  final Map<String, int?> counts;
  final CrewSeries? series;
  final DateTime at;

  /// `crewDash › counts` yanıtı: yalnız kuyruk sayıları (topluluk sayıları ve seriler yok; crew_counts.dart birleştirir).
  final bool partial;

  int? count(String k) => counts[k];

  /// Tek sayacı değiştirilmiş kopya (iyimser güncelleme / listeyle eşitleme).
  CrewDash withCount(String k, int v) =>
      CrewDash(access: access, role: role, counts: {...counts, k: v}, series: series, at: at, partial: partial);

  static CrewDash fromMap(Map<String, dynamic> m) {
    final c = OpsApi.map(m['counts']);
    final s = m['series'];
    return CrewDash(
      access: {for (final a in (m['access'] as List? ?? const [])) '$a'},
      role: '${m['role'] ?? 'operator'}',
      counts: {for (final e in c.entries) e.key: e.value is num ? (e.value as num).toInt() : null},
      series: s is Map ? CrewSeries.fromMap(Map<String, dynamic>.from(s)) : null,
      at: DateTime.fromMillisecondsSinceEpoch(m['at'] is num ? (m['at'] as num).toInt() : DateTime.now().millisecondsSinceEpoch),
      partial: m['partial'] == true,
    );
  }
}

/// Günlük seriler (Türkiye günü; eksik gün null).
class CrewSeries {
  const CrewSeries({required this.days, required this.lines});
  final List<String> days;

  /// newMembers, dau, eventJoins, posts, msgs, tickets, reports
  final Map<String, List<double?>> lines;

  List<double?> of(String k) => lines[k] ?? List<double?>.filled(days.length, null);

  static CrewSeries fromMap(Map<String, dynamic> m) {
    final days = [for (final d in (m['days'] as List? ?? const [])) '$d'];
    final lines = <String, List<double?>>{};
    for (final e in m.entries) {
      if (e.key == 'days' || e.value is! List) continue;
      lines[e.key] = [for (final v in e.value as List) v is num ? v.toDouble() : null];
    }
    return CrewSeries(days: days, lines: lines);
  }
}

abstract final class CrewApi {
  static Future<CrewDash> dash(Services services, {int days = 30}) async {
    if (services.isDemo) return _demo(days);
    return CrewDash.fromMap(await OpsApi.call('crewDash', 'dash', {'days': days}));
  }

  /// Yalnız kuyruk sayıları (rozet yenilemesi; ucuz). crew_counts.dart çağırır.
  static Future<CrewDash> counts(Services services) async {
    if (services.isDemo) return _demo(30);
    return CrewDash.fromMap(await OpsApi.call('crewDash', 'counts'));
  }

  /// Firebase'siz yerel deneme (PANEL_DEMO): tutarlı örnek sayılar.
  static CrewDash _demo(int days) {
    final r = math.Random(7);
    final now = DateTime.now();
    String key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final keys = [for (var i = days - 1; i >= 0; i--) key(now.subtract(Duration(days: i)))];
    List<double?> walk(double base, double amp) {
      var v = base;
      return [for (var i = 0; i < days; i++) (v = math.max(0, v + (r.nextDouble() - .42) * amp)).roundToDouble()];
    }

    return CrewDash(
      access: const {'applications', 'reports', 'modFlags', 'aiLabel', 'liveReports', 'tickets', 'idReviews', 'addressReviews', 'kahveReviews', 'businessApps', 'businessEvents', 'businessPayouts', 'businessDisputes', 'courierApps', 'courierCases', 'courierPayouts', 'creatorReviews', 'storeOrders', 'proLicenses', 'notifyApprovals'},
      role: 'founder',
      counts: const {
        'applications': 12, 'reports': 7, 'liveReports': 1, 'ticketsAwaiting': 4, 'ticketsOpen': 5, 'ticketsInProgress': 3, 'idReviews': 4, 'addressReviews': 2,
        'kahveReviews': 0, 'aiLabel': 3, 'businessApps': 3, 'businessEvents': 2, 'businessPayouts': 1, 'businessDisputes': 1, 'courierApps': 1,
        'courierCases': 1, 'courierPayouts': 0, 'creatorReviews': 2, 'storeOrders': 4, 'proLicenses': 2, 'notifyApprovals': 1, 'liveNow': 2, 'eventsNext7d': 9,
        'members': 1284, 'premium': 173, 'dau': 312, 'wau': 744, 'mau': 1033,
      },
      series: CrewSeries(days: keys, lines: {
        'newMembers': walk(6, 5),
        'dau': walk(280, 40),
        'eventJoins': walk(30, 12),
        'posts': walk(60, 20),
        'msgs': walk(900, 160),
        'tickets': walk(4, 3),
        'reports': walk(3, 3),
      }),
      at: now,
    );
  }
}
