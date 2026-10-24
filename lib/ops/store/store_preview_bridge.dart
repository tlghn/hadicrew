// HADİ Crew — Mağaza yönetiminin üye uygulamasındaki veri ve çizim katmanına köprüsü.
// Yönetim ekranları ürünü, siparişi ve tasarımı ham harita olarak düzenler; sunucu çağrıları hadi paketindeki
// StoreService'in admin* sarmalayıcılarıyla (lib/data/store_service.dart; tanıtım modu dahil), önizleme ve baskı dosyası
// StoreDesignPreview / StoreDesignPainter / renderStoreDesignPng ile (lib/features/store/store_preview.dart) yapılır.
// Bu dosyalar üye uygulamasınındır; burada DEĞİŞTİRİLMEDEN kullanılır.
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:hadi/core/session.dart';
import 'package:hadi/data/hadi_call.dart';
import 'package:hadi/data/store_service.dart';
import 'package:hadi/features/store/store_mockups.dart' show kStoreMockupAreas, storeMockupViews;
import 'package:hadi/features/store/store_preview.dart' show StoreArt, StoreDesignPainter, StoreDesignPreview, renderStoreDesignPng;

// ---------------------------------------------------------------- dönüşümler

StoreProduct storeProductOf(Map<String, dynamic> m) => StoreProduct.fromMap(m);
StoreDesign storeDesignOf(Map<String, dynamic> m) => StoreDesign.fromMap(m);

/// Ürünün görünümleri (ön / arka / sargı). Boşsa kategorinin çizim görünümleri.
List<String> storeProductViews(Map<String, dynamic> product) {
  final v = [for (final x in (product['views'] as List? ?? const [])) '$x'];
  if (v.isNotEmpty) return v;
  return storeMockupViews('${product['category'] ?? ''}');
}

String storeViewLabel(String v) => switch (v) {
      'front' => 'Ön',
      'back' => 'Arka',
      'wrap' => 'Sargı',
      'sleeve' => 'Kol',
      _ => v,
    };

/// Bu kategori + alan için mockup çizimiyle hizalı (kanonik) bir yer var mı? Varsa önizleme ve baskı dosyası onu kullanır;
/// üründeki x/y/w/h yalnızca kanonik yeri olmayan kategori/alan için geçerlidir (store_mockups.dart › storeMockupArea).
bool storeHasCanonicalArea(String category, String areaId, String view) =>
    kStoreMockupAreas[category]?.any((x) => x.id == areaId && x.view == view) ?? false;

/// Kategorinin kanonik alanları (yeni ürün için başlangıç değeri).
List<Map<String, dynamic>> storeCanonicalAreas(String category) => [
      for (final PrintArea a in kStoreMockupAreas[category] ?? const <PrintArea>[]) {'id': a.id, 'view': a.view, 'x': a.x, 'y': a.y, 'w': a.w, 'h': a.h},
    ];

// ---------------------------------------------------------------- çizim

/// Tasarımın önizlemesi (ürün mockup'ı + katmanlar). [showAreas]: baskı alanı kılavuzu (kesikli çerçeve).
Widget storeDesignPreview(Map<String, dynamic> product, Map<String, dynamic> design, {String view = 'front', double? width, bool showAreas = false}) {
  final p = storeProductOf(product);
  final d = storeDesignOf(design);
  if (!showAreas) return StoreDesignPreview(product: p, design: d, view: view, width: width);
  StoreArt.instance.ensure();
  StoreArt.instance.ensureFonts(d.layers);
  final child = AspectRatio(
    aspectRatio: 1,
    child: CustomPaint(painter: StoreDesignPainter(product: p, design: d, view: view, showAreas: true, repaint: StoreArt.instance)),
  );
  return width == null ? child : SizedBox(width: width, child: child);
}

/// Baskı dosyası (PNG baytları): görünümün baskı alan(lar)ı, şeffaf zemin.
Future<Uint8List> storeDesignPng(Map<String, dynamic> product, Map<String, dynamic> design, {String view = 'front', int px = 2400}) =>
    renderStoreDesignPng(storeProductOf(product), storeDesignOf(design), view: view, px: px);

// ---------------------------------------------------------------- sunucu (StoreService admin*)

StoreService _svc(BuildContext context) => StoreService.of(SessionScope.read(context).services);

Map<String, dynamic> _plain(Map<String, Object?> m) => m.map((k, v) => MapEntry(k, v));

Future<List<Map<String, dynamic>>> storeAdminProducts(BuildContext context) async {
  final list = await _svc(context).adminProducts();
  return [for (final p in list) {..._plain(p.toMap()), 'isDefault': p.isDefault}];
}

Future<void> storeAdminProductSave(BuildContext context, Map<String, dynamic> product) => _svc(context).adminProductSave(storeProductOf(product));

/// Siler; kod varsayılanı ürünü yalnızca pasifleştirir. true: pasifleştirildi (sunucu `deactivated`).
Future<bool> storeAdminProductDelete(BuildContext context, String id) async {
  final svc = _svc(context);
  if (svc.demo) {
    await svc.adminProductDelete(id);
    return false;
  }
  final r = await hadiCall('store', {'op': 'adminProductDelete', 'id': id});
  return r['deactivated'] == true;
}

Future<void> storeAdminFeature(BuildContext context, String id, {required bool featured, int? sort}) =>
    _svc(context).adminFeature(id, featured: featured, sort: sort);

/// Yönetim sipariş listesi. Ham yanıt kullanılır: StoreOrder modeli yönetime özgü alanları (buyerName, carrierName,
/// kalem colorName, pay.cpId/ref) taşımaz. Tanıtım modunda StoreService örnekleri.
Future<List<Map<String, dynamic>>> storeAdminOrders(BuildContext context, {String? status, int? limit}) async {
  final svc = _svc(context);
  if (svc.demo) return [for (final o in await svc.adminOrders(status: status)) _plain(o.toMap())];
  final r = await hadiCall('store', {'op': 'adminOrders', if (status != null && status.isNotEmpty) 'status': status, 'limit': ?limit}, timeout: const Duration(seconds: 60));
  return [for (final o in (r['orders'] as List?) ?? const []) if (o is Map) o.map((k, v) => MapEntry('$k', v))];
}

/// Durum değiştirir. [carrier] "other" ise firma adı [carrierName] ile gider (StoreService sarmalayıcısında bu alan yok).
Future<void> storeAdminOrderUpdate(BuildContext context, String id,
    {required String status, String? carrier, String? carrierName, String? trackingNo, String? trackingUrl, String? note}) async {
  final svc = _svc(context);
  if (svc.demo || carrier != 'other') {
    await svc.adminOrderUpdate(id, status: status, carrier: carrier, trackingNo: trackingNo, trackingUrl: trackingUrl, note: note);
    return;
  }
  await hadiCall('store', {
    'op': 'adminOrderUpdate',
    'id': id,
    'status': status,
    'carrier': carrier,
    'carrierName': ?carrierName,
    'trackingNo': ?trackingNo,
    'trackingUrl': ?trackingUrl,
    'note': ?note,
  });
  svc.changes.value++;
}

Future<Map<String, dynamic>> storeAdminConfig(BuildContext context, {Map<String, Object?>? set}) async =>
    _plain((await _svc(context).adminConfig(set: set)).toMap());

/// Tasarım varlıkları (katalogdan): {logos|stickers|fonts: [{id, name}]}.
Future<Map<String, dynamic>> storeAdminAssets(BuildContext context) async {
  final a = (await _svc(context).catalog()).assets;
  List<Map<String, String>> l(Iterable<StoreAsset> x) => [for (final e in x) {'id': e.id, 'name': e.name}];
  return {'logos': l(a.logos), 'stickers': l(a.stickers), 'fonts': l(a.fonts)};
}
