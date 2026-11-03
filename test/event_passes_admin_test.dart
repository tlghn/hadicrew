// Geçiş biletleri (lib/ops/events/event_passes_admin.dart; 3 Kasım 2026). Sınanan: Crew kullanılanları listeler (varsayılan süzgeç
// "Kullanılan"), satırda durum/etkinlik/kullanım ve ayrılış (iade yok), süzgeç sorguya gider; Kurucu Paneli (canGrant) bilet verme kartı
// ve kullanılmamış bileti geri alma; Crew'da verme/geri alma yok.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/data/event_admin_service.dart';
import 'package:hadi/data/event_pass_service.dart';
import 'package:hadi/data/models.dart' show PhoneVerification;
import 'package:hadi/data/services.dart';
import 'package:hadi/theme/hadi_theme.dart';
import 'package:hadi_crew/ops/events/event_passes_admin.dart';

class _Api implements EventPassApi {
  final statuses = <String>[];
  final revoked = <String>[];
  @override
  Future<EventPassPage> list({String status = '', String? eventId, int limit = 100}) async {
    statuses.add(status);
    final all = [
      EventPass(id: 'U1_E1', uid: 'U1', eventId: 'E1', eventTitle: 'Ege Kahvaltısı', name: 'Ada Yıldız', status: EventPassStatus.used,
          grantedAt: DateTime(2026, 11, 3, 9), usedAt: DateTime(2026, 11, 3, 10), grantedByName: 'Kurucu'),
      EventPass(id: 'U2_E1', uid: 'U2', eventId: 'E1', eventTitle: 'Ege Kahvaltısı', name: 'Can Demir', status: EventPassStatus.used,
          grantedAt: DateTime(2026, 11, 3, 9), usedAt: DateTime(2026, 11, 3, 11), leftAt: DateTime(2026, 11, 4, 8)),
      EventPass(id: 'U3_E2', uid: 'U3', eventId: 'E2', eventTitle: 'Yürüyüş', name: 'Ece Kaya', grantedAt: DateTime(2026, 11, 3, 12), note: 'gönüllü'),
    ];
    final items = status.isEmpty ? all : all.where((p) => p.status.name == status).toList();
    return EventPassPage(items);
  }

  @override
  Future<void> revoke({required String uid, required String eventId}) async => revoked.add('${uid}_$eventId');
  @override
  Future<void> grant({required String uid, required String eventId, String note = ''}) async {}
  @override
  Stream<EventPass?> watchMine(String eventId, String uid) => Stream.value(null);
  @override
  Future<EventPass?> mine(String eventId, String uid) async => null;
  @override
  Stream<Set<String>> watchUsedUids(String eventId) => Stream.value(const {});
}

class _Events implements EventAdminApi {
  @override
  Future<AdminEventPage> list(AdminEventQuery q, {Map<String, Object?>? cursor, int limit = 30}) async => const AdminEventPage(items: [], next: null, counts: {}, allScope: true);
  @override
  Future<int> seriesAdd(String eventId, List<DateTime> dates) async => 0;
  @override
  Future<void> unpublish(String eventId, String reason) async {}
  @override
  Future<void> publish(String eventId) async {}
}

Future<void> _pump(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(900, 1400) * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final svc = Services.demo();
  await t.runAsync(() => svc.auth.confirmCode(PhoneVerification(phone: '+905550000000', verificationId: 'demo'), '123456'));
  await t.pumpWidget(SessionScope(session: Session(svc), child: MaterialApp(theme: HadiTheme.light(), home: w)));
  for (var i = 0; i < 4; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('Crew: varsayılan "Kullanılan"; satırda kullanım ve ayrılış, verme/geri alma yok', (t) async {
    final api = _Api();
    await _pump(t, EventPassesAdminScreen(api: api, eventsApi: _Events()));
    expect(api.statuses, ['used']);
    expect(find.text('Ada Yıldız'), findsOneWidget);
    expect(find.text('Can Demir'), findsOneWidget);
    expect(find.text('Ece Kaya'), findsNothing);
    expect(find.text('Kullanıldı · ayrıldı'), findsOneWidget);
    expect(find.textContaining('iade yok'), findsOneWidget);
    expect(find.textContaining('Ege Kahvaltısı'), findsNWidgets(2));
    expect(find.text('Bilet ver'), findsNothing);
    expect(find.text('Geri al'), findsNothing);
  });

  testWidgets('süzgeç sorguya gider', (t) async {
    final api = _Api();
    await _pump(t, EventPassesAdminScreen(api: api, eventsApi: _Events()));
    await t.tap(find.text('Kullanılmayan'));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
    expect(api.statuses.last, 'active');
    expect(find.text('Ece Kaya'), findsOneWidget);
    expect(find.text('Not: gönüllü'), findsOneWidget);
  });

  testWidgets('Kurucu Paneli: bilet verme kartı; kullanılmamış bilet geri alınır', (t) async {
    final api = _Api();
    await _pump(t, EventPassesAdminScreen(api: api, eventsApi: _Events(), canGrant: true));
    expect(api.statuses, [''], reason: 'kurucu panelinde tümü');
    expect(find.text('Bilet ver'), findsOneWidget);
    expect(find.byKey(const ValueKey('bilet-uye')), findsOneWidget);
    expect(find.byKey(const ValueKey('bilet-etkinlik')), findsOneWidget);
    final give = t.widget<ButtonStyleButton>(find.byKey(const ValueKey('bilet-ver')));
    expect(give.onPressed, isNull, reason: 'üye ve etkinlik seçilmeden verilemez');
    // Yalnızca kullanılmamış bilette "Geri al".
    expect(find.text('Geri al'), findsOneWidget);
    await t.tap(find.text('Geri al'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Geri al'));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
    expect(api.revoked, ['U3_E2']);
  });
}
