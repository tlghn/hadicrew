// HADİ Crew › Test bulguları (lib/ops/admin/field_test_crew_view.dart; 27 Ekim 2026): SALT-OKUNUR.
// Yalnız durum, açıklama (+ sesli not dökümü), ekran görüntüsü / gizli ekran notu ve insan notları görünür; işlem düğmesi yok;
// sunucu eski/zengin biçimde fazladan alan gönderse bile YZ / Claude metni, derece, Akçe, kimlik, bağlam görünmez.
//   flutter test test/field_test_crew_view_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hadi_crew/ops/admin/field_test_crew_view.dart';

final _item = <String, Object?>{
  'id': 'ftabc123XYZ_0001', 'status': 'kabul_edildi', 'description': 'Katıl düğmesi çalışmıyor', 'voiceTranscript': 'katıl düğmesine bastım',
  'hasShot': false, 'secure': true,
  'notes': [{'text': 'İnsan notu: tekrar ettim'}],
  // Sunucu artık göndermez; gelse bile görünmemeli:
  'reviews': [{'ai': true, 'text': 'HADİ ön değerlendirmesi: YZ metni'}, {'by': 'claude', 'text': 'Claude değerlendirmesi'}],
  'rating': 'kritik', 'name': 'Ali Test', 'uid': 'u1', 'akceTotal': 35, 'context': {'screen': '/etkinlik/9', 'device': 'Pixel 8'},
  'founderDecision': {'note': 'Karar gerekçesi'}, 'title': 'Gizli başlık',
};

Future<Map<String, Object?>> _loader(String? id) async => id == null ? {'items': [_item]} : {'item': _item, 'shotUrl': null};

void _noLeaks() {
  for (final s in ['YZ metni', 'ön değerlendirme', 'Claude', 'Kritik', 'kritik', 'Ali Test', 'Akçe', 'Pixel', '/etkinlik/9', 'Karar gerekçesi', 'Gizli başlık']) {
    expect(find.textContaining(s), findsNothing, reason: s);
  }
}

void _noActions() {
  for (final s in ['Onayla', 'Reddet', 'Kaydet', 'Sil', 'Dışa aktar', 'JSON', 'Not ekle', 'Durumu değiştir', 'Duyur']) {
    expect(find.textContaining(s), findsNothing, reason: s);
  }
  expect(find.byType(FilledButton), findsNothing);
  expect(find.byType(ElevatedButton), findsNothing);
  expect(find.byType(TextField), findsNothing);
  expect(find.byType(Checkbox), findsNothing);
  expect(find.byType(PopupMenuButton<String>), findsNothing);
}

void main() {
  testWidgets('liste ve ayrıntı salt-okunur; yalnız izinli bilgiler', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(const MaterialApp(home: FieldTestCrewScreen(loader: _loader)));
    await t.pumpAndSettle();
    expect(find.text('Test bulguları'), findsOneWidget);
    expect(find.text('Kabul edildi'), findsOneWidget);
    expect(find.text('Katıl düğmesi çalışmıyor'), findsOneWidget);
    expect(find.textContaining('Kurucu Paneli'), findsNothing);
    _noLeaks();
    _noActions();
    await t.tap(find.byKey(const ValueKey('ft-crew-ftabc123XYZ_0001')));
    await t.pumpAndSettle();
    expect(find.text('Durum'), findsOneWidget);
    expect(find.text('Katıl düğmesi çalışmıyor'), findsOneWidget);
    expect(find.text('katıl düğmesine bastım'), findsOneWidget);
    expect(find.text('Gizli ekran — görüntü alınmadı.'), findsOneWidget);
    expect(find.text('İnsan notu: tekrar ettim'), findsOneWidget);
    _noLeaks();
    _noActions();
  });
}
