// HADİ Crew — Mağaza yönetimi ortak parçaları (sipariş kuyruğu, ürünler, ayarlar).
// Sunucu: `store` callable'ının yönetim op'ları (adminProducts, adminProductSave, adminProductDelete, adminFeature,
// adminOrders, adminOrderUpdate, adminConfig). Yetki: kurucu ya da `store.manage`; asıl denetim sunucudadır.
import 'package:flutter/material.dart';

import 'package:hadi/core/capabilities.dart';
import 'package:hadi/core/format.dart';
import 'package:hadi/core/money.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/data/models.dart' show AppFailure;
import 'package:hadi/theme/hadi_colors.dart';

/// Mağaza yönetimini görebilir mi (kurucu ya da `store.manage`).
bool canManageStore(Session s) => s.isFounder || s.can(Cap.storeManage);

/// Sipariş durumları: kimlik, kısa ad, renk, emoji.
const kStoreOrderStatuses = <(String, String, Color, String)>[
  ('paid', 'Yeni · ödendi', HadiColors.aktivite, '🆕'),
  ('in_production', 'Üretimde', HadiColors.heyecan, '🧵'),
  ('shipped', 'Kargoda', HadiColors.iletisim, '🚚'),
  ('delivered', 'Teslim edildi', HadiColors.dostluk, '✅'),
  ('awaiting_address', 'Hediye adresi bekliyor', HadiColors.pink, '🎁'),
  ('cancelled', 'İptal', HadiColors.error, '✖️'),
  ('refunded', 'İade edildi', HadiColors.error, '↩️'),
];

String storeStatusLabel(String s) => kStoreOrderStatuses.where((x) => x.$1 == s).firstOrNull?.$2 ?? s;
Color storeStatusColor(String s) => kStoreOrderStatuses.where((x) => x.$1 == s).firstOrNull?.$3 ?? HadiColors.ink3;
String storeStatusEmoji(String s) => kStoreOrderStatuses.where((x) => x.$1 == s).firstOrNull?.$4 ?? '•';

/// Kategori kimliği → Türkçe ad (sözleşmedeki liste; katalog yeni bir kategori getirirse kimliği gösterilir).
const kStoreCategories = <(String, String, String)>[
  ('tshirt', 'Tişört', '👕'),
  ('sweat', 'Sweatshirt', '🧥'),
  ('hoodie', 'Kapüşonlu', '🧥'),
  ('mug', 'Kupa', '☕'),
  ('figurine', 'Biblo / figür', '🗿'),
  ('cap', 'Şapka', '🧢'),
  ('tote', 'Bez çanta', '👜'),
  ('bottle', 'Termos/matara', '🧴'),
  ('phonecase', 'Telefon kılıfı', '📱'),
  ('notebook', 'Defter', '📓'),
  ('sticker', 'Sticker seti', '🏷️'),
  ('poster', 'Poster', '🖼️'),
  ('pin', 'Rozet / pin', '📍'),
  ('keychain', 'Anahtarlık', '🔑'),
  ('socks', 'Çorap', '🧦'),
  ('beanie', 'Bere', '🧶'),
  ('mousepad', 'Mousepad', '🖱️'),
  ('puzzle', 'Yapboz', '🧩'),
  ('giftbox', 'Hediye kutusu', '🎁'),
];

String storeCategoryLabel(String id) => kStoreCategories.where((x) => x.$1 == id).firstOrNull?.$2 ?? id;
String storeCategoryEmoji(String id) => kStoreCategories.where((x) => x.$1 == id).firstOrNull?.$3 ?? '🛍️';

/// Sayısal alan okuma (sunucu int/double karışık döndürebilir).
num storeNum(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

/// Milisaniye / ISO / Timestamp benzeri → tarih.
DateTime? storeTime(Object? v) {
  if (v is num && v > 0) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  if (v is String) return DateTime.tryParse(v)?.toLocal();
  if (v is DateTime) return v;
  if (v is Map && v['_seconds'] is num) return DateTime.fromMillisecondsSinceEpoch(((v['_seconds'] as num) * 1000).toInt());
  try {
    // Firestore Timestamp (toDate) — doğrudan okunan belgeler için.
    final d = (v as dynamic)?.toDate();
    if (d is DateTime) return d;
  } catch (_) {}
  return null;
}

String storeWhen(Object? v) {
  final t = storeTime(v);
  return t == null ? '—' : dateTimeLong(t);
}

/// "349 ₺ + 120💎" gibi toplam.
String storeTotalText(Map<String, dynamic>? total, {String method = ''}) {
  final tl = storeNum(total?['tl']), el = storeNum(total?['elmas']);
  if (method == 'elmas') return elmasText(el);
  if (method == 'card') return money(tl);
  return [if (tl > 0) money(tl), if (el > 0) elmasText(el)].join(' · ').ifEmpty('—');
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

Map<String, dynamic> storeMap(Object? v) => v is Map ? v.map((k, x) => MapEntry('$k', x)) : <String, dynamic>{};
List<Map<String, dynamic>> storeList(Object? v) => v is List ? [for (final x in v) if (x is Map) storeMap(x)] : <Map<String, dynamic>>[];

void storeToast(BuildContext context, String msg) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));
}

String storeError(Object e) => e is AppFailure ? e.message : 'İşlem yapılamadı. Bağlantını kontrol edip tekrar dene.';

/// Durum rozeti.
class StoreStatusChip extends StatelessWidget {
  const StoreStatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final c = storeStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: HadiColors.wash(c), borderRadius: BorderRadius.circular(99)),
      child: Text('${storeStatusEmoji(status)} ${storeStatusLabel(status)}',
          style: TextStyle(color: HadiColors.text(c), fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }
}

/// Bölüm başlığı (kart içi).
class StoreSectionTitle extends StatelessWidget {
  const StoreSectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
          ?trailing,
        ]),
      );
}

/// Yuvarlak köşeli kart.
class StoreCard extends StatelessWidget {
  const StoreCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.color});
  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? HadiColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: HadiColors.line),
        ),
        child: child,
      );
}

/// Hex "#1D9AD6" → renk (geçersizse null).
Color? storeHexColor(String? hex) {
  var h = (hex ?? '').trim().replaceFirst('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length != 6) return null;
  final n = int.tryParse(h, radix: 16);
  return n == null ? null : Color(0xFF000000 | n);
}

String storeColorHex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
