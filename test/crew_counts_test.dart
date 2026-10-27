// HADİ Crew › rozet sayıları (lib/app/crew_counts.dart; 27 Ekim 2026, kurucu 04:45).
// Rozet = liste tutarlılığı (bölüm / Kuyruklar toplamı / sekme rozetleri aynı kaynaktan), işlemden sonra anında düşme,
// odağa dönünce tazeleme, eski (uçan) yanıtın iyimser düşüşü ezmemesi.
//   flutter test test/crew_counts_test.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hadi/data/callables.dart' show HadiCallable;
import 'package:hadi_crew/app/crew_api.dart';
import 'package:hadi_crew/app/crew_counts.dart';

CrewDash _dash(Map<String, int?> counts, {bool partial = false, CrewSeries? series}) =>
    CrewDash(access: counts.keys.toSet(), role: 'founder', counts: counts, series: series, at: DateTime(2026, 10, 27, 4, 45), partial: partial);

/// Kurucunun gördüğü durum: başvuru yok; Ödemeler 1, Anlaşmazlıklar 1.
const _biz = <String, int?>{'businessApps': 0, 'businessEvents': 0, 'businessPayouts': 1, 'businessDisputes': 1};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => CrewCounts.instance.stop());

  // sections.dart web'e özgü ekranları içe aktarır (VM'de yüklenemez): bölümler kaynaktan okunur (panel_kit_test ile aynı yol).
  final src = File('lib/app/sections.dart').readAsStringSync();
  final blocks = src.split('CrewSection(').skip(2).toList();
  final sections = <String, ({bool queue, List<String> keys})>{
    for (final b in blocks)
      RegExp(r"id: '([^']+)'").firstMatch(b)!.group(1)!: (
        queue: b.contains('queue: true'),
        keys: [
          for (final m in RegExp(r"'([A-Za-z]+)'").allMatches(RegExp(r'countKeys: const \[([^\]]*)\]').firstMatch(b)?.group(1) ?? '')) m.group(1)!,
          if (b.contains('countKeys: const [kAiLabelCountKey]')) 'aiLabel',
        ],
      ),
  };
  int? badge(String id, CrewDash? d) => sumCounts(d, sections[id]!.keys);
  int total(CrewDash? d) => queueTotalOf([for (final s in sections.values) if (s.queue) s.keys], d);

  group('rozet = liste tutarlılığı', () {
    test('İşletmeler rozeti tüm sekmelerin toplamı; her sayaç bir sekmede görünür', () {
      expect(sections['isletmeler']!.keys, ['businessApps', 'businessEvents', 'businessPayouts', 'businessDisputes']);
      expect(badge('isletmeler', _dash(_biz)), 2);
      expect(sections['kuryeler']!.keys, ['courierApps', 'courierCases', 'courierPayouts']);
      expect(sections['destek']!.keys, ['ticketsAwaiting']);
      expect(sections['yz-icerigi']!.keys, ['aiLabel']);
      expect(src, contains('int queueTotal(Iterable<CrewSection> visible, CrewDash? d) => queueTotalOf('));
      expect(src, contains('int? sectionCount(CrewSection s, CrewDash? d) => sumCounts(d, s.countKeys);'));
      // Rozeti olan her kuyruk bölümü Kuyruklar'da listelenir.
      for (final e in sections.entries) {
        if (e.value.keys.isNotEmpty) expect(e.value.queue, isTrue, reason: e.key);
      }
    });

    test('Kuyruklar toplamı = kuyruk bölümlerinin rozet toplamı (her sayaç bir kez)', () {
      final counts = <String, int?>{
        'applications': 2, 'reports': 3, 'modFlags': 1, 'aiLabel': 1, 'liveReports': 1, 'ticketsAwaiting': 2, 'ticketsOpen': 9,
        'idReviews': 1, 'addressReviews': 0, 'kahveReviews': 0, ..._biz, 'courierApps': 1, 'courierCases': 1, 'courierPayouts': 0,
        'creatorReviews': 2, 'secondhand': 1, 'storeOrders': 2, 'proLicenses': 2, 'notifyApprovals': 1,
        'members': 1200, 'dau': 300, // topluluk sayıları kuyruk değildir
      };
      final d = _dash(counts);
      var sum = 0;
      for (final e in sections.entries) {
        if (e.value.queue) sum += badge(e.key, d) ?? 0;
      }
      expect(total(d), sum);
      expect(total(d), 23);
      // Destek rozeti "ekip yanıtı bekleyen"; ham "open" sayısı (9) karışmaz.
      expect(badge('destek', d), 2);
    });

    test('sayı yoksa rozet yok (null), yetkisiz kuyruk toplama girmez', () {
      expect(badge('isletmeler', null), isNull);
      expect(badge('isletmeler', _dash({'applications': 4})), isNull);
      expect(total(_dash({'applications': 4})), 4);
      expect(total(null), 0);
    });
  });

  group('canlılık', () {
    test('karar işleminden sonra rozet HEMEN düşer, ardından sunucudan yeniden çekilir', () async {
      var server = Map<String, int?>.from(_biz);
      var fetches = 0;
      CrewCounts.instance.ensureStarted('k1', () async {
        fetches++;
        return _dash(server, partial: true);
      });
      await pumpEventQueue();
      expect(fetches, 1);
      expect(badge('isletmeler', crewDashNotifier.value), 2);
      expect(HadiCallable.onSuccess, isNotNull, reason: 'başarılı çağrılar rozetleri tazelemeli');

      // Ödendi işaretlendi: sunucuda talep kapandı.
      server = {...server, 'businessPayouts': 0};
      HadiCallable.onSuccess!('business', {'op': 'payoutPaid', 'id': 'p1', 'bankRef': 'TR1'});
      expect(crewDashNotifier.value!.count('businessPayouts'), 0, reason: 'iyimser düşüş beklemeden');
      expect(badge('isletmeler', crewDashNotifier.value), 1);
      await Future<void>.delayed(CrewCounts.afterAction + const Duration(milliseconds: 50));
      await pumpEventQueue();
      expect(fetches, 2, reason: 'işlemden sonra sayılar yeniden çekilir');
      expect(crewDashNotifier.value!.count('businessPayouts'), 0);
    });

    test('okuma op\'ları (liste, ayrıntı) tazeleme tetiklemez; bilinmeyen yazma op\'u tetikler', () async {
      var fetches = 0;
      CrewCounts.instance.ensureStarted('k2', () async {
        fetches++;
        return _dash(_biz, partial: true);
      });
      await pumpEventQueue();
      for (final op in ['reviewList', 'eventsPending', 'payoutsPending', 'orderDisputes', 'cases', 'list', 'configGet']) {
        HadiCallable.onSuccess!('business', {'op': op});
      }
      HadiCallable.onSuccess!('crewDash', {'op': 'counts'});
      await Future<void>.delayed(CrewCounts.afterAction + const Duration(milliseconds: 50));
      expect(fetches, 1);
      HadiCallable.onSuccess!('opsMod', {'op': 'act', 'key': 'r:1'});
      await Future<void>.delayed(CrewCounts.afterAction + const Duration(milliseconds: 50));
      await pumpEventQueue();
      expect(fetches, 2);
      expect(isReadCall('supportDesk', {'op': 'pending'}), isTrue);
      expect(isReadCall('business', {'op': 'approve'}), isFalse);
    });

    test('işlemden ÖNCE başlamış (eski) yanıt iyimser düşüşü ezmez', () async {
      final gate = Completer<CrewDash>();
      var first = true;
      CrewCounts.instance.ensureStarted('k3', () {
        if (first) {
          first = false;
          return gate.future;
        }
        return Future.value(_dash({..._biz, 'businessDisputes': 0}, partial: true));
      });
      CrewCounts.instance.apply(_dash(_biz));
      CrewCounts.instance.onCallSuccess('business', {'op': 'orderResolve', 'id': 'o1'});
      expect(crewDashNotifier.value!.count('businessDisputes'), 0);
      gate.complete(_dash(_biz, partial: true)); // eski: anlaşmazlık hâlâ 1
      await pumpEventQueue();
      expect(crewDashNotifier.value!.count('businessDisputes'), 0, reason: 'eski yanıt yazılmadı');
      await Future<void>.delayed(CrewCounts.afterAction + const Duration(milliseconds: 50));
      await pumpEventQueue();
      expect(crewDashNotifier.value!.count('businessDisputes'), 0);
    });

    test('pencere odağa dönünce tazelenir; arka plandayken zamanlayıcı çekmez', () async {
      var fetches = 0;
      CrewCounts.instance.ensureStarted('k4', () async {
        fetches++;
        return _dash(_biz, partial: true);
      });
      await pumpEventQueue();
      expect(fetches, 1);
      CrewCounts.instance.didChangeAppLifecycleState(AppLifecycleState.hidden);
      CrewCounts.instance.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(fetches, 2);
    });

    test('liste yüklenince (tam liste) rozet listeyle eşitlenir; kısmi listede dokunulmaz', () {
      CrewCounts.instance.apply(_dash({..._biz, 'businessApps': 1}));
      CrewCounts.instance.reconcile('businessApps', 0);
      expect(crewDashNotifier.value!.count('businessApps'), 0, reason: '"Bekleyen işletme başvurusu yok" ↔ rozet 0');
      CrewCounts.instance.reconcile('businessEvents', 50, complete: false);
      expect(crewDashNotifier.value!.count('businessEvents'), 0);
    });

    test('counts (partial) yanıtı topluluk sayılarını ve serileri korur; kullanıcı değişince sayılar silinir', () async {
      final series = CrewSeries(days: const ['2026-10-27'], lines: const {'dau': [3]});
      CrewCounts.instance.ensureStarted('k5', () async => _dash({'applications': 1}, partial: true));
      CrewCounts.instance.apply(_dash({'applications': 5, 'members': 1200}, series: series));
      await pumpEventQueue();
      final d = crewDashNotifier.value!;
      expect(d.count('applications'), 1);
      expect(d.count('members'), 1200);
      expect(d.series, same(series));
      CrewCounts.instance.ensureStarted('baska', () => Completer<CrewDash>().future);
      expect(crewDashNotifier.value, isNull);
    });
  });

  testWidgets('sekme rozeti: "Anlaşmazlıklar 1" görünür, işlemden sonra kaybolur', (t) async {
    CrewCounts.instance.apply(_dash(_biz));
    await t.pumpWidget(const MaterialApp(
      home: DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: TabBar(tabs: [
            CountTab(text: 'Başvurular', keys: ['businessApps']),
            CountTab(text: 'Anlaşmazlıklar', keys: ['businessDisputes']),
            Tab(text: 'Ayarlar'),
          ]),
        ),
      ),
    ));
    expect(find.text('Başvurular'), findsOneWidget);
    expect(find.byKey(const ValueKey('tab-count-Başvurular')), findsNothing, reason: '0 ise rozet yok');
    expect(find.byKey(const ValueKey('tab-count-Anlaşmazlıklar')), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    CrewCounts.instance.bump('businessDisputes');
    await t.pump();
    expect(find.byKey(const ValueKey('tab-count-Anlaşmazlıklar')), findsNothing);
  });
}
