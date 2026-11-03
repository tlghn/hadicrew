// Kişisel veri erişim gerekçesi (hadi › widgets/access_reason.dart) panelde açılabilmeli: pencere kök gezgin
// anahtarıyla (appNavigatorKey) açılır; Crew / Kurucu Paneli yönlendiricisi bu anahtara bağlı değilken pencere hiç
// açılmıyor, çağrı "Gerekçe girilmediği için kişisel veri açılmadı." ile düşüyordu (geçici kurucu moderasyonu).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hadi/widgets/access_reason.dart';
import 'package:hadi/widgets/share_result.dart' show appNavigatorKey;

void main() {
  testWidgets('kök anahtar bağlı panel yönlendiricisinde gerekçe penceresi açılır ve gerekçeyi döndürür', (t) async {
    final router = GoRouter(
      navigatorKey: appNavigatorKey,
      routes: [GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('panel')))],
    );
    addTearDown(router.dispose);
    await t.pumpWidget(MaterialApp.router(routerConfig: router));

    Map<String, String>? got;
    var done = false;
    askAccessReasonGlobal({'scopeLabel': 'Moderasyon kaydı'}).then((v) => (got, done) = (v, true));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Erişim gerekçesi'), findsOneWidget);

    await t.tap(find.text('Şikayet incelemesi'));
    await t.enterText(find.byType(TextField), '#4F2A1C şikayetinde geçmiş uyarılara bakıyorum.');
    await t.pump();
    await t.ensureVisible(find.text('Gerekçeyle aç'));
    await t.pump();
    await t.tap(find.text('Gerekçeyle aç'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(done, isTrue);
    expect(got, {'category': 'report', 'text': '#4F2A1C şikayetinde geçmiş uyarılara bakıyorum.'});
  });

  testWidgets('kök anahtar bağlı değilse pencere açılamaz (eski hata)', (t) async {
    final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('panel')))]);
    addTearDown(router.dispose);
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(await askAccessReasonGlobal(const {}), isNull);
  });
}
