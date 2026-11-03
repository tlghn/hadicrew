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

/// Pano › Tüm üyeler satırı (functions/src/crew_members.ts): YALNIZCA fotoğraf, görünen ad ve kullanıcı adı.
class CrewMember {
  const CrewMember({required this.uid, required this.name, this.handle, this.photo});
  final String uid;

  /// Herkese görünen ad (rumuz kuralı; gerçek ad gizliyse @kullanıcıadı).
  final String name;
  final String? handle;
  final String? photo;

  static CrewMember fromMap(Map<String, dynamic> m) {
    String? s(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
    return CrewMember(uid: '${m['uid'] ?? ''}', name: s(m['name']) ?? 'Üye', handle: s(m['handle']), photo: s(m['photo']));
  }
}

/// Bir sayfa üye. [total] yalnız ilk sayfada gelir; [cursor] null ise liste bitti.
class CrewMembersPage {
  const CrewMembersPage({required this.items, this.total, this.cursor});
  final List<CrewMember> items;
  final int? total;
  final Map<String, Object?>? cursor;
  bool get done => cursor == null;

  static CrewMembersPage fromMap(Map<String, dynamic> m) {
    final c = m['cursor'];
    return CrewMembersPage(
      items: [for (final x in (m['items'] as List? ?? const [])) if (x is Map) CrewMember.fromMap(Map<String, dynamic>.from(x))],
      total: m['total'] is num ? (m['total'] as num).toInt() : null,
      cursor: m['done'] == true || c is! Map ? null : Map<String, Object?>.from(c),
    );
  }
}

abstract final class CrewApi {
  /// Pano › Tüm üyeler: toplam + 30'luk sayfalar (sort: new | old) ya da arama ([q]; en çok 20 sonuç, sayfa yok).
  static Future<CrewMembersPage> members(Services services, {String sort = 'new', Map<String, Object?>? cursor, String? q}) async {
    if (services.isDemo) return _demoMembers(sort, cursor, q);
    return CrewMembersPage.fromMap(await OpsApi.call('crewDash', 'members', {
      'sort': sort,
      'cursor': ?cursor,
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
    }));
  }

  static CrewMembersPage _demoMembers(String sort, Map<String, Object?>? cursor, String? q) {
    const first = ['Ayşe', 'Mehmet', 'Zeynep', 'Can', 'Elif', 'Burak', 'Deniz', 'Selin', 'Emre', 'Ece'];
    const last = ['Yılmaz', 'Kaya', 'Demir', 'Şahin', 'Çelik', 'Aydın'];
    const total = 1284;
    final all = [
      for (var i = 0; i < total; i++)
        CrewMember(uid: 'demo$i', name: '${first[i % first.length]} ${last[i % last.length]}', handle: '${first[i % first.length].toLowerCase()}$i'),
    ];
    final list = sort == 'old' ? all : all.reversed.toList();
    if (q != null && q.trim().length >= 2) {
      final k = q.trim().replaceFirst('@', '').toLowerCase();
      return CrewMembersPage(items: list.where((m) => m.name.toLowerCase().contains(k) || (m.handle ?? '').startsWith(k)).take(20).toList(), total: total);
    }
    final start = cursor == null ? 0 : (cursor['i'] as int? ?? 0);
    final end = math.min(start + 30, list.length);
    return CrewMembersPage(items: list.sublist(start, end), total: cursor == null ? total : null, cursor: end < list.length ? {'i': end} : null);
  }

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
