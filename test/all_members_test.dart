// HADİ Crew › Pano › Tüm üyeler (lib/app/all_members.dart; 3 Kasım 2026).
// Toplam sayı, yalnız ad + @kullanıcı adı, sayfalı yükleme ("Daha fazla göster"), sıralama, arama, eski yanıtın yazılmaması,
// sunucu yanıtının ayrıştırılması (CrewMembersPage).
//   flutter test test/all_members_test.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hadi_crew/app/all_members.dart';
import 'package:hadi_crew/app/crew_api.dart';

typedef _Call = ({String sort, Map<String, Object?>? cursor, String? q});

CrewMember _m(int i) => CrewMember(uid: 'u$i', name: 'Üye $i', handle: 'uye$i');

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)));

void main() {
  group('CrewMembersPage.fromMap', () {
    test('ilk sayfa: toplam + imleç; yalnız uid/ad/kullanıcı adı/fotoğraf okunur', () {
      final p = CrewMembersPage.fromMap({
        'total': 1284,
        'items': [
          {'uid': 'a', 'name': 'Ayşe K.', 'handle': 'ayse', 'photo': 'https://x/y.jpg', 'phone': '+905551112233'},
          {'uid': 'b', 'name': '', 'handle': null, 'photo': null},
        ],
        'cursor': {'s': 1, 'n': 2, 'id': 'b'},
        'done': false,
      });
      expect(p.total, 1284);
      expect(p.items.length, 2);
      expect(p.items[0].name, 'Ayşe K.');
      expect(p.items[0].handle, 'ayse');
      expect(p.items[0].photo, 'https://x/y.jpg');
      expect(p.items[1].name, 'Üye');
      expect(p.items[1].handle, isNull);
      expect(p.cursor, {'s': 1, 'n': 2, 'id': 'b'});
      expect(p.done, isFalse);
    });

    test('son sayfa / arama: imleç yok, toplam yalnız ilk sayfada', () {
      final p = CrewMembersPage.fromMap({'total': null, 'items': [], 'cursor': null, 'done': true});
      expect(p.done, isTrue);
      expect(p.total, isNull);
      expect(CrewMembersPage.fromMap({'items': [], 'cursor': {'s': 1, 'n': 0, 'id': 'x'}, 'done': true}).done, isTrue);
    });
  });

  test('fmtCount', () {
    expect(fmtCount(null), '—');
    expect(fmtCount(7), '7');
    expect(fmtCount(1284), '1.284');
    expect(fmtCount(1234567), '1.234.567');
  });

  testWidgets('toplam, liste ve "Daha fazla göster" ile sayfalama', (t) async {
    final calls = <_Call>[];
    Future<CrewMembersPage> fetch({required String sort, Map<String, Object?>? cursor, String? q}) async {
      calls.add((sort: sort, cursor: cursor, q: q));
      final start = cursor == null ? 0 : cursor['i'] as int;
      final end = start + 30 > 45 ? 45 : start + 30;
      return CrewMembersPage(
        items: [for (var i = start; i < end; i++) _m(i)],
        total: cursor == null ? 45 : null,
        cursor: end < 45 ? {'i': end} : null,
      );
    }

    await t.pumpWidget(_host(AllMembersSection(fetch: fetch)));
    await t.pumpAndSettle();
    expect(find.text('Tüm üyeler'), findsOneWidget);
    expect(find.text('45 üye'), findsOneWidget);
    expect(find.text('Üye 0'), findsOneWidget);
    expect(find.text('@uye0'), findsOneWidget);
    expect(find.text('Üye 30'), findsNothing);
    expect(find.text('Daha fazla göster (30 / 45)'), findsOneWidget);

    await t.ensureVisible(find.text('Daha fazla göster (30 / 45)'));
    await t.tap(find.text('Daha fazla göster (30 / 45)'));
    await t.pumpAndSettle();
    expect(find.text('Üye 44'), findsOneWidget);
    expect(find.textContaining('Daha fazla göster'), findsNothing);
    expect(calls.length, 2);
    expect(calls[1].cursor, {'i': 30});
    // Sonraki sayfada toplam gelmez; ilk sayfanın toplamı korunur.
    expect(find.text('45 üye'), findsOneWidget);
  });

  testWidgets('sıralama değişince baştan yüklenir; arama sunucuya gider ve sıralamayı kilitler', (t) async {
    final calls = <_Call>[];
    Future<CrewMembersPage> fetch({required String sort, Map<String, Object?>? cursor, String? q}) async {
      calls.add((sort: sort, cursor: cursor, q: q));
      if (q != null) return CrewMembersPage(items: [_m(7)], total: 100);
      return CrewMembersPage(items: [_m(sort == 'old' ? 1 : 99)], total: 100);
    }

    await t.pumpWidget(_host(AllMembersSection(fetch: fetch)));
    await t.pumpAndSettle();
    expect(find.text('Üye 99'), findsOneWidget);

    await t.tap(find.text('En eski'));
    await t.pumpAndSettle();
    expect(calls.last.sort, 'old');
    expect(calls.last.cursor, isNull);
    expect(find.text('Üye 1'), findsOneWidget);
    expect(find.text('Üye 99'), findsNothing);

    // Tek harf aramaz.
    await t.enterText(find.byType(TextField), 'a');
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(calls.where((c) => c.q != null), isEmpty);

    await t.enterText(find.byType(TextField), '@uye7');
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(calls.last.q, '@uye7');
    expect(find.text('Üye 7'), findsOneWidget);
    expect(find.text('Aramada en çok 20 sonuç gösterilir.'), findsOneWidget);
    final seg = t.widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>));
    expect(seg.onSelectionChanged, isNull);

    // Temizle → arama kalkar, liste geri gelir.
    await t.tap(find.byTooltip('Temizle'));
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(calls.last.q, isNull);
    expect(find.text('Üye 1'), findsOneWidget);
  });

  testWidgets('eski (uçan) yanıt yeni sıralamanın sonucunu ezmez', (t) async {
    final slow = Completer<CrewMembersPage>();
    Future<CrewMembersPage> fetch({required String sort, Map<String, Object?>? cursor, String? q}) {
      if (sort == 'new') return slow.future;
      return Future.value(CrewMembersPage(items: [_m(1)], total: 2));
    }

    await t.pumpWidget(_host(AllMembersSection(fetch: fetch)));
    await t.pump();
    await t.tap(find.text('En eski'));
    await t.pumpAndSettle();
    slow.complete(CrewMembersPage(items: [_m(2)], total: 2));
    await t.pumpAndSettle();
    expect(find.text('Üye 1'), findsOneWidget);
    expect(find.text('Üye 2'), findsNothing);
  });

  testWidgets('hata: yeniden dene', (t) async {
    var fail = true;
    Future<CrewMembersPage> fetch({required String sort, Map<String, Object?>? cursor, String? q}) async {
      if (fail) throw Exception('ağ');
      return CrewMembersPage(items: [_m(3)], total: 1);
    }

    await t.pumpWidget(_host(AllMembersSection(fetch: fetch)));
    await t.pumpAndSettle();
    expect(find.textContaining('Yüklenemedi'), findsOneWidget);
    fail = false;
    await t.tap(find.textContaining('Tekrar'));
    await t.pumpAndSettle();
    expect(find.text('Üye 3'), findsOneWidget);
    expect(find.text('1 üye'), findsOneWidget);
  });
}
