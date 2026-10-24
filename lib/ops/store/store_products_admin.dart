// HADİ Crew / Kurucu Paneli — Mağaza ürünleri (store › adminProducts, adminProductSave, adminProductDelete, adminFeature).
// Liste: etkin/pasif, öne çıkan yıldızı, sıra (yukarı/aşağı). Düzenleyici: ad, kategori, açıklama, rozetler, renkler
// (ad + hex, renk seçici), bedenler + beden tablosu, görünümler, baskı alanları (sayısal; önizlemede canlı çerçeve),
// hazır tasarımlar (katman listesi + canlı önizleme), özelleştirme kuralları, fiyatlar, fiziksel/dijital, stok, üretim süresi.
// Kod varsayılanı ürün silinemez, yalnızca pasifleşir (sunucu kuralı). Görsel yüklenmez: mockup'lar vektörel çizilir.
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:hadi/core/format.dart' show money;
import 'package:hadi/core/money.dart';
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/skeleton.dart';

import 'store_admin_common.dart';
import 'store_preview_bridge.dart';

class StoreProductsAdminTab extends StatefulWidget {
  const StoreProductsAdminTab({super.key, this.embedded = true});
  final bool embedded;

  @override
  State<StoreProductsAdminTab> createState() => _StoreProductsAdminTabState();
}

/// Tasarım varlıkları (logo, sticker, yazı tipi kimlikleri). Katalogdan gelir; gelmezse sözleşmedeki temel set.
class StoreAdminAssets {
  StoreAdminAssets({required this.logos, required this.stickers, required this.fonts});
  final List<(String, String)> logos, stickers, fonts;

  static List<(String, String)> _ids(Object? v) => [
        for (final x in (v as List? ?? const []))
          if (x is Map) ('${x['id']}', '${x['label'] ?? x['name'] ?? x['emoji'] ?? x['id']}') else ('$x', '$x'),
      ];

  static StoreAdminAssets from(Map<String, dynamic> m) {
    final a = StoreAdminAssets(logos: _ids(m['logos']), stickers: _ids(m['stickers']), fonts: _ids(m['fonts']));
    return StoreAdminAssets(
      logos: a.logos.isEmpty ? fallback.logos : a.logos,
      stickers: a.stickers.isEmpty ? fallback.stickers : a.stickers,
      fonts: a.fonts.isEmpty ? fallback.fonts : a.fonts,
    );
  }

  static final fallback = StoreAdminAssets(
    logos: const [('hadi_wordmark', 'HADİ yazısı'), ('hadi_mark', 'HADİ işareti'), ('hadi_badge', 'HADİ rozeti'), ('hadi_circle', 'HADİ daire')],
    stickers: const [],
    fonts: const [('Bricolage', 'Bricolage')],
  );
}

class _StoreProductsAdminTabState extends State<StoreProductsAdminTab> {
  List<Map<String, dynamic>>? _products;
  String? _error;
  bool _showPassive = true;
  String _q = '';
  StoreAdminAssets _assets = StoreAdminAssets.fallback;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    try {
      final r = await storeAdminAssets(context);
      if (mounted) setState(() => _assets = StoreAdminAssets.from(r));
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final list = (await storeAdminProducts(context))..sort((a, b) => storeNum(a['sort']).compareTo(storeNum(b['sort'])));
      if (!mounted) return;
      setState(() {
        _products = list;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _products = const [];
          _error = storeError(e);
        });
      }
    }
  }

  Future<void> _feature(Map<String, dynamic> p, {bool? featured, num? sort}) async {
    final id = '${p['id']}';
    setState(() => _busy.add(id));
    try {
      await storeAdminFeature(context, id, featured: featured ?? (p['featured'] == true), sort: sort?.toInt());
      setState(() {
        if (featured != null) p['featured'] = featured;
        if (sort != null) p['sort'] = sort;
      });
    } catch (e) {
      if (mounted) storeToast(context, storeError(e));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  /// Sırayı bir basamak kaydırır: tüm listeye 10'ar aralıklı sıra numarası verip yalnızca değişenleri yazar.
  Future<void> _move(int i, int dir) async {
    final list = _products!;
    final j = i + dir;
    if (j < 0 || j >= list.length) return;
    final next = [...list];
    final x = next.removeAt(i);
    next.insert(j, x);
    final changes = <Map<String, dynamic>, int>{};
    for (var k = 0; k < next.length; k++) {
      final want = (k + 1) * 10;
      if (storeNum(next[k]['sort']) != want) changes[next[k]] = want;
    }
    setState(() => _products = next);
    for (final e in changes.entries) {
      await _feature(e.key, sort: e.value);
    }
  }

  Future<void> _open(Map<String, dynamic>? p) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => StoreProductEditor(
        product: p,
        assets: _assets,
        nextSort: ((_products ?? const []).fold<num>(0, (m, x) => storeNum(x['sort']) > m ? storeNum(x['sort']) : m) + 10).toInt(),
      ),
    ));
    if (saved == true) await _load();
  }

  Widget _tile(int i, Map<String, dynamic> p) {
    final id = '${p['id']}';
    final active = p['active'] != false;
    final featured = p['featured'] == true;
    final colors = storeList(p['colors']);
    return Opacity(
      opacity: active ? 1 : .55,
      child: StoreCard(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        child: Row(children: [
          SizedBox(
            width: 64,
            height: 64,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: storeDesignPreview(p, _firstDesign(p), width: 64),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: () => _open(p),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text('${p['title'] ?? id}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900))),
                  if (!active) ...[const SizedBox(width: 6), _tag('Pasif', HadiColors.ink3)],
                  if (p['isDefault'] == true || p['builtin'] == true) ...[const SizedBox(width: 6), _tag('Hazır', HadiColors.aktivite)],
                  for (final b in (p['badges'] as List? ?? const [])) ...[const SizedBox(width: 6), _tag('$b', HadiColors.heyecan)],
                ]),
                const SizedBox(height: 2),
                Text(
                  [
                    '${storeCategoryEmoji('${p['category']}')} ${storeCategoryLabel('${p['category']}')}',
                    if (p['physical'] != false && storeNum(p['priceTl']) > 0) money(storeNum(p['priceTl'])),
                    if (p['physical'] != false && storeNum(p['priceElmasPhysical']) > 0) elmasText(storeNum(p['priceElmasPhysical'])),
                    if (p['digital'] != false && storeNum(p['priceDigital']) > 0) 'dijital ${elmasText(storeNum(p['priceDigital']))}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: HadiColors.ink2, fontSize: 12.5),
                ),
                const SizedBox(height: 4),
                Row(children: [
                  for (final c in colors.take(10))
                    Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.only(right: 3),
                      decoration: BoxDecoration(color: storeHexColor('${c['hex']}') ?? HadiColors.mist, shape: BoxShape.circle, border: Border.all(color: HadiColors.line)),
                    ),
                  if (colors.length > 10) Text('+${colors.length - 10}', style: TextStyle(color: HadiColors.ink3, fontSize: 11)),
                  const Spacer(),
                  Text('sıra ${storeNum(p['sort']).toInt()}', style: TextStyle(color: HadiColors.ink3, fontSize: 11)),
                ]),
              ]),
            ),
          ),
          IconButton(
            tooltip: featured ? 'Öne çıkandan kaldır' : 'Öne çıkar',
            onPressed: _busy.contains(id) ? null : () => _feature(p, featured: !featured),
            icon: Icon(featured ? Icons.star_rounded : Icons.star_outline_rounded, color: featured ? HadiColors.heyecan : HadiColors.ink3),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            InkWell(onTap: i == 0 ? null : () => _move(i, -1), child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.keyboard_arrow_up_rounded))),
            InkWell(
              onTap: i == (_products!.length - 1) ? null : () => _move(i, 1),
              child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.keyboard_arrow_down_rounded)),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _tag(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: HadiColors.wash(c), borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: TextStyle(color: HadiColors.text(c), fontSize: 11, fontWeight: FontWeight.w800)),
      );

  @override
  Widget build(BuildContext context) {
    final all = _products;
    final q = _q.trim().toLowerCase();
    final indexed = [
      for (var i = 0; i < (all?.length ?? 0); i++)
        if ((_showPassive || all![i]['active'] != false) &&
            (q.isEmpty || '${all![i]['title']} ${all[i]['id']} ${storeCategoryLabel('${all[i]['category']}')}'.toLowerCase().contains(q)))
          i,
    ];
    final body = RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 90), children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v),
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Ürün ara', isDense: true),
                  ),
                ),
                FilterChip(label: const Text('Pasifleri göster'), selected: _showPassive, onSelected: (v) => setState(() => _showPassive = v)),
                if (all != null)
                  Text('${all.where((p) => p['active'] != false).length} etkin · ${all.where((p) => p['featured'] == true).length} öne çıkan',
                      style: TextStyle(color: HadiColors.ink3, fontSize: 12.5)),
              ]),
              const SizedBox(height: 10),
              if (all == null) ...const [ListTileSkeleton(), ListTileSkeleton(), ListTileSkeleton()],
              if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: TextStyle(color: HadiColors.ink2))),
              if (all != null && indexed.isEmpty && _error == null)
                Padding(padding: const EdgeInsets.all(24), child: Text('Ürün yok.', textAlign: TextAlign.center, style: TextStyle(color: HadiColors.ink3))),
              for (final i in indexed) Padding(padding: const EdgeInsets.only(bottom: 8), child: _tile(i, all![i])),
              if (q.isNotEmpty && indexed.isNotEmpty)
                Text('Arama açıkken sıralama okları tüm listeye göre çalışır.', style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
            ]),
          ),
        ),
      ]),
    );
    final fab = FloatingActionButton.extended(onPressed: () => _open(null), icon: const Icon(Icons.add_rounded), label: const Text('Yeni ürün'));
    if (widget.embedded) {
      return Stack(children: [body, Positioned(right: 16, bottom: 16, child: fab)]);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mağaza ürünleri', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [IconButton(tooltip: 'Yenile', onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      floatingActionButton: fab,
      body: body,
    );
  }
}

/// Liste küçük resmi için tasarım: ilk hazır tasarım, yoksa yalnızca ilk renk.
Map<String, dynamic> _firstDesign(Map<String, dynamic> p) {
  final t = storeList(p['templates']).firstOrNull;
  if (t != null) return storeMap(t['design']);
  return {'colorId': '${storeList(p['colors']).firstOrNull?['id'] ?? ''}', 'layers': const []};
}

Map<String, dynamic> _deepCopy(Map<String, dynamic> m) => storeMap(jsonDecode(jsonEncode(m, toEncodable: (o) => o is DateTime ? o.millisecondsSinceEpoch : '$o')));

String _slug(String s) {
  const tr = {'ç': 'c', 'ğ': 'g', 'ı': 'i', 'i̇': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u', 'â': 'a'};
  var x = s.toLowerCase();
  tr.forEach((k, v) => x = x.replaceAll(k, v));
  return x.replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
}

const _kBadges = ['yeni', 'çok satan', 'sınırlı'];
const _kViews = [('front', 'Ön'), ('back', 'Arka'), ('wrap', 'Sargı (kupa, termos)')];
const _kAreaIds = [('front', 'Ön'), ('back', 'Arka'), ('sleeve', 'Kol'), ('wrap', 'Sargı')];
const _kSizePresets = <(String, List<String>)>[
  ('Giyim', ['XS', 'S', 'M', 'L', 'XL', 'XXL']),
  ('Çorap', ['36-40', '41-46']),
  ('Tek beden', []),
];

// ------------------------------------------------------------------ ürün düzenleyici

class StoreProductEditor extends StatefulWidget {
  const StoreProductEditor({super.key, required this.product, required this.assets, this.nextSort = 10});

  /// null: yeni ürün.
  final Map<String, dynamic>? product;
  final StoreAdminAssets assets;
  final int nextSort;

  @override
  State<StoreProductEditor> createState() => _StoreProductEditorState();
}

class _StoreProductEditorState extends State<StoreProductEditor> {
  late final bool _isNew = widget.product == null;
  late final bool _builtin = widget.product?['isDefault'] == true || widget.product?['builtin'] == true;
  late final Map<String, dynamic> _p = _isNew
      ? {
          'id': '',
          'title': '',
          'category': 'tshirt',
          'desc': '',
          'badges': <String>['yeni'],
          'colors': [
            {'id': 'beyaz', 'name': 'Beyaz', 'hex': '#FFFFFF'},
            {'id': 'siyah', 'name': 'Siyah', 'hex': '#1A1A1A'},
          ],
          'sizes': ['S', 'M', 'L', 'XL'],
          'sizeChart': '',
          'views': ['front', 'back'],
          'printAreas': [
            {'id': 'front', 'view': 'front', 'x': .3, 'y': .25, 'w': .4, 'h': .45},
            {'id': 'back', 'view': 'back', 'x': .28, 'y': .2, 'w': .44, 'h': .5},
          ],
          'templates': <Map<String, dynamic>>[],
          'customizable': true,
          'allowText': true,
          'maxTextLen': 24,
          'fonts': [for (final f in widget.assets.fonts.take(3)) f.$1],
          'priceTl': 0,
          'priceElmasPhysical': 0,
          'priceDigital': 0,
          'physical': true,
          'digital': true,
          'leadDays': 5,
          'featured': false,
          'sort': widget.nextSort,
          'active': false,
        }
      : _deepCopy(widget.product!);

  /// Önizlemenin görünümü ve rengi; seçili hazır tasarım (önizlemede gösterilir).
  String _view = 'front';
  String? _colorId;
  int? _template;
  bool _stockOn = false, _busy = false, _dirty = false;

  @override
  void initState() {
    super.initState();
    _stockOn = _p['stock'] is Map && (_p['stock'] as Map).isNotEmpty;
    _view = storeProductViews(_p).first;
    _colorId = storeList(_p['colors']).firstOrNull?['id']?.toString();
  }

  List<Map<String, dynamic>> _listOf(String k) {
    final v = _p[k];
    if (v is List<Map<String, dynamic>>) return v;
    final l = storeList(v);
    _p[k] = l;
    return l;
  }

  List<String> _strings(String k) {
    final v = _p[k];
    if (v is List<String>) return v;
    final l = [for (final x in (v as List? ?? const [])) '$x'];
    _p[k] = l;
    return l;
  }

  void _set(String k, Object? v) => setState(() {
        _p[k] = v;
        _dirty = true;
      });

  void _touch() => setState(() => _dirty = true);

  Map<String, dynamic> get _previewDesign {
    final t = _template != null && _template! < _listOf('templates').length ? storeMap(_listOf('templates')[_template!]['design']) : <String, dynamic>{'layers': const []};
    return {...t, 'colorId': _colorId ?? t['colorId'] ?? ''};
  }

  String? _validate() {
    if (_isNew && '${_p['id']}'.trim().isEmpty) _p['id'] = _slug('${_p['title']}');
    final id = '${_p['id']}'.trim();
    if (!RegExp(r'^[a-z0-9_]{2,40}$').hasMatch(id)) return 'Ürün kimliği 2-40 karakter olmalı (küçük harf, rakam, alt çizgi).';
    if ('${_p['title']}'.trim().length < 2) return 'Ürün adını yaz.';
    final colors = _listOf('colors');
    if (colors.isEmpty) return 'En az bir renk ekle.';
    for (final c in colors) {
      if ('${c['name']}'.trim().isEmpty) return 'Renklerin adını yaz.';
      if (storeHexColor('${c['hex']}') == null) return '${c['name']}: renk kodu #RRGGBB biçiminde olmalı.';
    }
    final ids = colors.map((c) => '${c['id']}').toSet();
    if (ids.length != colors.length) return 'İki rengin adı aynı olamaz.';
    final views = _strings('views');
    if (views.isEmpty) return 'En az bir görünüm seç.';
    for (final a in _listOf('printAreas')) {
      if (!views.contains('${a['view']}')) return 'Baskı alanı "${a['id']}" seçili olmayan bir görünümde.';
      for (final k in const ['x', 'y', 'w', 'h']) {
        final v = storeNum(a[k]);
        if (v < 0 || v > 1) return 'Baskı alanı değerleri 0 ile 1 arasında olmalı.';
      }
      if (storeNum(a['x']) + storeNum(a['w']) > 1.001 || storeNum(a['y']) + storeNum(a['h']) > 1.001) return 'Baskı alanı "${a['id']}" görselin dışına taşıyor.';
    }
    if (_p['physical'] != false && storeNum(_p['priceTl']) <= 0 && storeNum(_p['priceElmasPhysical']) <= 0) return 'Fiziksel satış açıksa en az bir fiziksel fiyat gir.';
    if (_p['digital'] != false && storeNum(_p['priceDigital']) <= 0) return 'Dijital satış açıksa dijital fiyat gir.';
    return null;
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) return storeToast(context, err);
    final out = _deepCopy(_p);
    if (!_stockOn) out.remove('stock');
    out['colors'] = [for (final c in storeList(out['colors'])) {...c}..remove('_new')];
    out['id'] = '${out['id']}'.trim();
    out['title'] = '${out['title']}'.trim();
    setState(() => _busy = true);
    try {
      await storeAdminProductSave(context, out);
      if (!mounted) return;
      storeToast(context, 'Ürün kaydedildi.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) storeToast(context, storeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_builtin ? 'Ürünü pasifleştir' : 'Ürünü sil'),
        content: Text(_builtin
            ? 'Bu ürün HADİ ile hazır geliyor; silinmez, pasifleştirilir (mağazada görünmez). Verilmiş siparişler ve üyelerin dijital ürünleri etkilenmez.'
            : 'Ürün silinir. Verilmiş siparişler ve üyelerin dijital ürünleri etkilenmez. Yalnızca gizlemek istiyorsan "Etkin" anahtarını kapatıp kaydet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HadiColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_builtin ? 'Pasifleştir' : 'Sil'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final passive = await storeAdminProductDelete(context, '${_p['id']}');
      if (!mounted) return;
      storeToast(context, passive || _builtin ? 'Ürün pasifleştirildi.' : 'Ürün silindi.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) storeToast(context, storeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kaydedilmemiş değişiklikler'),
        content: const Text('Çıkarsan değişiklikler kaybolur.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Düzenlemeye dön')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Çık')),
        ],
      ),
    );
    return r == true;
  }

  // ---------------------------------------------------------------- önizleme

  Widget _preview({double? width}) {
    final views = _strings('views');
    if (!views.contains(_view)) _view = views.isEmpty ? 'front' : views.first;
    final colors = _listOf('colors');
    final templates = _listOf('templates');
    // Kanonik yeri olan alanları çizici kendisi gösterir (mavi kesikli); burada yalnızca üründeki değerlerle çizilenler (mor).
    final areas = [
      for (final a in _listOf('printAreas'))
        if ('${a['view']}' == _view && !storeHasCanonicalArea('${_p['category']}', '${a['id']}', _view)) a,
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      LayoutBuilder(builder: (context, cons) {
        final w = width ?? cons.maxWidth;
        return Center(
          child: SizedBox(
            width: w,
            height: w,
            child: Stack(children: [
              Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(16), child: storeDesignPreview(_p, _previewDesign, view: _view, width: w, showAreas: true))),
              // Baskı alanları (0..1 oransal) — kesikli çerçeve.
              for (final a in areas)
                Positioned(
                  left: storeNum(a['x']) * w,
                  top: storeNum(a['y']) * w,
                  width: storeNum(a['w']) * w,
                  height: storeNum(a['h']) * w,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: HadiColors.iletisim, width: 1.5),
                        color: HadiColors.iletisim.withValues(alpha: .06),
                      ),
                      alignment: Alignment.topLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        color: HadiColors.iletisim,
                        child: Text(_areaLabel('${a['id']}'), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        );
      }),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
        for (final v in views) ChoiceChip(label: Text(storeViewLabel(v)), selected: _view == v, onSelected: (_) => setState(() => _view = v)),
      ]),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
        for (final c in colors)
          Tooltip(
            message: '${c['name']}',
            child: InkWell(
              onTap: () => setState(() => _colorId = '${c['id']}'),
              customBorder: const CircleBorder(),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: storeHexColor('${c['hex']}') ?? HadiColors.mist,
                  shape: BoxShape.circle,
                  border: Border.all(color: _colorId == '${c['id']}' ? HadiColors.aktivite : HadiColors.line, width: _colorId == '${c['id']}' ? 3 : 1),
                ),
              ),
            ),
          ),
      ]),
      if (templates.isNotEmpty) ...[
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
          ChoiceChip(label: const Text('Boş'), selected: _template == null, onSelected: (_) => setState(() => _template = null)),
          for (var i = 0; i < templates.length; i++)
            ChoiceChip(label: Text('${templates[i]['name']}'), selected: _template == i, onSelected: (_) => setState(() => _template = i)),
        ]),
      ],
    ]);
  }

  String _areaLabel(String id) => _kAreaIds.where((x) => x.$1 == id).firstOrNull?.$2 ?? id;

  // ---------------------------------------------------------------- form parçaları

  Widget _text(String label, String key, {int maxLines = 1, int? maxLength, String? hint, bool enabled = true, ValueChanged<String>? onChanged}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          initialValue: '${_p[key] ?? ''}',
          enabled: enabled,
          maxLines: maxLines,
          minLines: 1,
          maxLength: maxLength,
          decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
          onChanged: onChanged ??
              (v) {
                _p[key] = v;
                _touch();
              },
        ),
      );

  Widget _num(String label, Map<String, dynamic> target, String key, {String? suffix, bool decimal = false, double width = 140, VoidCallback? after}) => SizedBox(
        width: width,
        child: TextFormField(
          initialValue: _numText(target[key]),
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          decoration: InputDecoration(labelText: label, suffixText: suffix, isDense: true),
          onChanged: (v) {
            final n = num.tryParse(v.trim().replaceAll(',', '.'));
            target[key] = n ?? 0;
            _touch();
            after?.call();
          },
        ),
      );

  static String _numText(Object? v) {
    if (v is! num) return '${v ?? ''}';
    return v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '');
  }

  Widget _switch(String label, String key, {String? sub, bool def = false}) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: _p[key] == null ? def : _p[key] == true,
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: sub == null ? null : Text(sub, style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
        onChanged: (v) => _set(key, v),
      );

  Widget _section(String title, List<Widget> children, {Widget? trailing, String? help}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: StoreCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
              ?trailing,
            ]),
            if (help != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(help, style: TextStyle(color: HadiColors.ink3, fontSize: 12))),
            const SizedBox(height: 10),
            ...children,
          ]),
        ),
      );

  List<Widget> _basics() => [
        _section('Temel bilgiler', [
          _text('Ürün kimliği', 'id',
              enabled: _isNew,
              hint: 'boş bırakırsan addan üretilir · ornek_tisort',
              onChanged: (v) {
                _p['id'] = _slug(v);
                _touch();
              }),
          _text('Ürün adı', 'title', maxLength: 60),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DropdownButtonFormField<String>(
              initialValue: kStoreCategories.any((c) => c.$1 == _p['category']) ? '${_p['category']}' : null,
              decoration: const InputDecoration(labelText: 'Kategori', isDense: true),
              items: [for (final c in kStoreCategories) DropdownMenuItem(value: c.$1, child: Text('${c.$3} ${c.$2}'))],
              onChanged: (v) => setState(() {
                _p['category'] = v;
                _dirty = true;
                // Yeni üründe kategoriye göre çizimle hizalı hazır baskı alanları ve görünümler.
                final areas = storeCanonicalAreas('$v');
                if (_isNew && areas.isNotEmpty) {
                  _p['printAreas'] = areas;
                  _p['views'] = [for (final x in const ['front', 'back', 'wrap']) if (areas.any((a) => a['view'] == x)) x];
                }
              }),
            ),
          ),
          _text('Açıklama', 'desc', maxLines: 5, maxLength: 600),
          const Text('Rozetler', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            for (final b in _kBadges)
              FilterChip(
                label: Text(b),
                selected: _strings('badges').contains(b),
                onSelected: (v) => setState(() {
                  final l = _strings('badges');
                  v ? l.add(b) : l.remove(b);
                  _dirty = true;
                }),
              ),
          ]),
        ]),
      ];

  List<Widget> _colorsAndSizes() {
    final colors = _listOf('colors');
    final sizes = _strings('sizes');
    return [
      _section(
        'Renkler',
        [
          for (var i = 0; i < colors.length; i++)
            Padding(
              key: ObjectKey(colors[i]),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () async {
                    final c = await showStoreColorPicker(context, storeHexColor('${colors[i]['hex']}') ?? Colors.white);
                    if (c != null) _set('colors', colors..[i]['hex'] = storeColorHex(c));
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: storeHexColor('${colors[i]['hex']}') ?? HadiColors.mist, shape: BoxShape.circle, border: Border.all(color: HadiColors.line, width: 2)),
                    child: Icon(Icons.colorize_rounded, size: 16, color: HadiColors.onColor(storeHexColor('${colors[i]['hex']}') ?? Colors.white)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    initialValue: '${colors[i]['name'] ?? ''}',
                    decoration: const InputDecoration(labelText: 'Renk adı', isDense: true),
                    onChanged: (v) {
                      colors[i]['name'] = v;
                      if (_isNew || '${colors[i]['id'] ?? ''}'.isEmpty || colors[i]['_new'] == true) colors[i]['id'] = _slug(v);
                      _touch();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    key: ValueKey('hex-${colors[i]['hex']}-${identityHashCode(colors[i])}'),
                    initialValue: '${colors[i]['hex'] ?? ''}',
                    decoration: const InputDecoration(labelText: 'Kod', isDense: true),
                    onFieldSubmitted: (v) => _set('colors', colors..[i]['hex'] = v.trim().toUpperCase()),
                    onChanged: (v) {
                      if (storeHexColor(v) != null) {
                        colors[i]['hex'] = v.trim().toUpperCase();
                        _touch();
                      }
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Kaldır',
                  onPressed: colors.length <= 1 ? null : () => _set('colors', colors..removeAt(i)),
                  icon: Icon(Icons.delete_outline_rounded, color: HadiColors.error),
                ),
              ]),
            ),
        ],
        trailing: TextButton.icon(
          onPressed: () => _set('colors', colors..add({'id': '', 'name': '', 'hex': '#1D9AD6', '_new': true})),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Renk ekle'),
        ),
        help: 'Mockup bu renkle çizilir. Kayıtlı bir rengin adını değiştirmek kimliğini değiştirmez (eski siparişler bozulmaz).',
      ),
      _section('Bedenler', [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in sizes)
            InputChip(label: Text(s), onDeleted: () => _set('sizes', sizes..remove(s))),
          SizedBox(
            width: 120,
            child: TextField(
              decoration: const InputDecoration(hintText: 'Beden ekle', isDense: true),
              onSubmitted: (v) {
                final t = v.trim().toUpperCase();
                if (t.isNotEmpty && !sizes.contains(t)) _set('sizes', sizes..add(t));
              },
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [
          for (final p in _kSizePresets)
            ActionChip(label: Text(p.$1), onPressed: () => _set('sizes', [...p.$2])),
        ]),
        const SizedBox(height: 10),
        _text('Beden tablosu', 'sizeChart', maxLines: 6, maxLength: 1200, hint: 'S: göğüs 50 cm, boy 70 cm\nM: göğüs 53 cm, boy 72 cm…'),
      ], help: 'Boş = beden seçimi yok (kupa, rozet gibi).'),
    ];
  }

  List<Widget> _areas() {
    final views = _strings('views');
    final areas = _listOf('printAreas');
    return [
      _section('Görünümler ve baskı alanları', [
        Wrap(spacing: 6, children: [
          for (final v in _kViews)
            FilterChip(
              label: Text(v.$2),
              selected: views.contains(v.$1),
              onSelected: (on) => setState(() {
                on ? views.add(v.$1) : views.remove(v.$1);
                views.sort((a, b) => _kViews.indexWhere((x) => x.$1 == a).compareTo(_kViews.indexWhere((x) => x.$1 == b)));
                _dirty = true;
              }),
            ),
        ]),
        const SizedBox(height: 10),
        for (var i = 0; i < areas.length; i++)
          Container(
            key: ObjectKey(areas[i]),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: HadiColors.mist, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _kAreaIds.any((x) => x.$1 == areas[i]['id']) ? '${areas[i]['id']}' : null,
                    decoration: const InputDecoration(labelText: 'Alan', isDense: true),
                    items: [for (final a in _kAreaIds) DropdownMenuItem(value: a.$1, child: Text(a.$2))],
                    onChanged: (v) => _set('printAreas', areas..[i]['id'] = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: views.contains(areas[i]['view']) ? '${areas[i]['view']}' : null,
                    decoration: const InputDecoration(labelText: 'Görünüm', isDense: true),
                    items: [for (final v in views) DropdownMenuItem(value: v, child: Text(storeViewLabel(v)))],
                    onChanged: (v) => setState(() {
                      areas[i]['view'] = v;
                      if (v != null) _view = v;
                      _dirty = true;
                    }),
                  ),
                ),
                IconButton(
                  tooltip: 'Önizlemede göster',
                  onPressed: () => setState(() => _view = '${areas[i]['view']}'),
                  icon: const Icon(Icons.visibility_rounded),
                ),
                IconButton(
                  tooltip: 'Kaldır',
                  onPressed: () => _set('printAreas', areas..removeAt(i)),
                  icon: Icon(Icons.delete_outline_rounded, color: HadiColors.error),
                ),
              ]),
              if (storeHasCanonicalArea('${_p['category']}', '${areas[i]['id']}', '${areas[i]['view']}'))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Bu kategoride bu alanın çizimle hizalı hazır yeri var; önizleme ve baskı dosyası onu kullanır (mavi çerçeve). '
                      'Aşağıdaki değerler yalnızca kayıtta tutulur.', style: TextStyle(color: HadiColors.ink3, fontSize: 11.5)),
                ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final k in const [('x', 'Sol (x)'), ('y', 'Üst (y)'), ('w', 'Genişlik'), ('h', 'Yükseklik')])
                  _num(k.$2, areas[i], k.$1, decimal: true, width: 96, after: () => setState(() => _view = '${areas[i]['view']}')),
              ]),
            ]),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _set('printAreas', areas..add({'id': 'front', 'view': views.isEmpty ? 'front' : views.first, 'x': .3, 'y': .3, 'w': .4, 'h': .4})),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Baskı alanı ekle'),
          ),
        ),
      ], help: 'Değerler görselin oranı: 0 = sol/üst kenar, 1 = sağ/alt kenar. Önizlemede mavi kesikli çerçeve çizimle hizalı hazır alanı, '
          'mor çerçeve buradaki değerlerle çizilen alanı gösterir (yeni kategori ya da alan) ve canlı güncellenir.'),
    ];
  }

  List<Widget> _templates() {
    final templates = _listOf('templates');
    return [
      _section(
        'Hazır tasarımlar',
        [
          if (templates.isEmpty) Text('Henüz hazır tasarım yok. Üyeler boş üründen başlar.', style: TextStyle(color: HadiColors.ink2, fontSize: 13)),
          for (var i = 0; i < templates.length; i++)
            ListTile(
              key: ObjectKey(templates[i]),
              contentPadding: EdgeInsets.zero,
              leading: SizedBox(width: 48, height: 48, child: ClipRRect(borderRadius: BorderRadius.circular(10), child: storeDesignPreview(_p, storeMap(templates[i]['design']), width: 48))),
              title: Text('${templates[i]['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${storeList(storeMap(templates[i]['design'])['layers']).length} katman', style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
              onTap: () => setState(() => _template = i),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: 'Düzenle', onPressed: () => _editTemplate(i), icon: const Icon(Icons.edit_rounded)),
                IconButton(
                  tooltip: 'Kaldır',
                  onPressed: () => setState(() {
                    templates.removeAt(i);
                    _template = null;
                    _dirty = true;
                  }),
                  icon: Icon(Icons.delete_outline_rounded, color: HadiColors.error),
                ),
              ]),
            ),
        ],
        trailing: TextButton.icon(onPressed: () => _editTemplate(null), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Tasarım ekle')),
        help: 'Üyeler bunlardan birini seçip özelleştirebilir.',
      ),
    ];
  }

  Future<void> _editTemplate(int? i) async {
    final templates = _listOf('templates');
    final src = i == null
        ? {
            'id': 't${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}',
            'name': 'Yeni tasarım',
            'design': {'colorId': _colorId ?? '', 'layers': <Map<String, dynamic>>[]},
          }
        : _deepCopy(templates[i]);
    final r = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(
      builder: (_) => StoreTemplateEditor(product: _p, template: src, assets: widget.assets),
    ));
    if (r == null) return;
    setState(() {
      if (i == null) {
        templates.add(r);
        _template = templates.length - 1;
      } else {
        templates[i] = r;
        _template = i;
      }
      _dirty = true;
    });
  }

  List<Widget> _rules() {
    final fonts = _strings('fonts');
    return [
      _section('Özelleştirme', [
        _switch('Üye özelleştirebilir', 'customizable', sub: 'Kapalıysa yalnızca hazır tasarımlar satılır.', def: true),
        _switch('Yazı eklenebilir', 'allowText', def: true),
        Row(children: [
          _num('En çok karakter', _p, 'maxTextLen', width: 150),
          const SizedBox(width: 10),
          Expanded(child: Text('Yazılar sunucuda denetlenir (küfür, iletişim bilgisi, marka).', style: TextStyle(color: HadiColors.ink3, fontSize: 12))),
        ]),
        const SizedBox(height: 10),
        const Text('Yazı tipleri', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final f in widget.assets.fonts)
            FilterChip(
              label: Text(f.$2),
              selected: fonts.contains(f.$1),
              onSelected: (v) => setState(() {
                v ? fonts.add(f.$1) : fonts.remove(f.$1);
                _dirty = true;
              }),
            ),
        ]),
      ]),
    ];
  }

  List<Widget> _prices() => [
        _section('Satış ve fiyatlar', [
          _switch('Fiziksel satış açık', 'physical', sub: 'Kartla TL ya da satın alınmış Elmasla sipariş.', def: true),
          _switch('Dijital satış açık', 'digital', sub: 'Elmas ya da Akçe ile; profilde sergilenir, hediye edilebilir.', def: true),
          const SizedBox(height: 6),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _num('Fiyat (KDV dahil)', _p, 'priceTl', suffix: '₺', decimal: true, width: 170),
            _num('Fiziksel, Elmasla', _p, 'priceElmasPhysical', suffix: '💎', width: 170),
            _num('Dijital', _p, 'priceDigital', suffix: '💎', width: 140),
            _num('Üretim süresi', _p, 'leadDays', suffix: 'gün', width: 140),
            _num('Sıra', _p, 'sort', width: 100),
          ]),
          const SizedBox(height: 6),
          Text('Dijital fiyatın Akçe karşılığı güncel kurla hesaplanır (${akceText(storeNum(_p['priceDigital']) * CurrencyRate.current)}).',
              style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
        ]),
      ];

  List<Widget> _stock() {
    final colors = _listOf('colors');
    final sizes = _strings('sizes');
    final keys = <(String, String)>[
      for (final c in colors)
        if (sizes.isEmpty) ('${c['id']}|', '${c['name']}') else for (final s in sizes) ('${c['id']}|$s', '${c['name']} · $s'),
    ];
    final stock = _p['stock'] is Map ? storeMap(_p['stock']) : <String, dynamic>{};
    _p['stock'] = stock;
    return [
      _section('Stok', [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _stockOn,
          title: const Text('Stok takibi', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('Kapalıysa sınırsız (siparişe göre üretim).', style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
          onChanged: (v) => setState(() {
            _stockOn = v;
            _dirty = true;
          }),
        ),
        if (_stockOn)
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in keys)
              SizedBox(
                width: 150,
                child: TextFormField(
                  key: ValueKey('stock-${k.$1}'),
                  initialValue: stock[k.$1] == null ? '' : '${stock[k.$1]}',
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: k.$2, isDense: true, hintText: 'sınırsız'),
                  onChanged: (v) {
                    final n = int.tryParse(v.trim());
                    n == null ? stock.remove(k.$1) : stock[k.$1] = n;
                    _touch();
                  },
                ),
              ),
          ]),
      ]),
    ];
  }

  List<Widget> _visibility() => [
        _section('Yayın', [
          _switch('Etkin (mağazada görünür)', 'active', def: true),
          _switch('Öne çıkan', 'featured', sub: 'Mağazanın üstündeki vitrinde gösterilir.'),
        ]),
      ];

  @override
  Widget build(BuildContext context) {
    final form = [..._basics(), ..._colorsAndSizes(), ..._areas(), ..._templates(), ..._rules(), ..._prices(), ..._stock(), ..._visibility()];
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave()) {
          _dirty = false;
          nav.pop(false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'Yeni ürün' : '${widget.product?['title'] ?? 'Ürün'}', maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            if (!_isNew)
              IconButton(tooltip: 'Kaldır / pasifleştir', onPressed: _busy ? null : _delete, icon: Icon(Icons.delete_outline_rounded, color: HadiColors.error)),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded),
                label: const Text('Kaydet'),
              ),
            ),
          ],
        ),
        body: LayoutBuilder(builder: (context, cons) {
          if (cons.maxWidth >= 900) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 8, 40), children: form)),
              SizedBox(
                width: 380,
                child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(8, 12, 16, 24), child: StoreCard(child: _preview())),
              ),
            ]);
          }
          return ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 40), children: [
            ExpansionTile(
              initiallyExpanded: true,
              tilePadding: EdgeInsets.zero,
              title: const Text('Önizleme', style: TextStyle(fontWeight: FontWeight.w900)),
              children: [Padding(padding: const EdgeInsets.only(bottom: 12), child: _preview(width: (cons.maxWidth - 24).clamp(160.0, 340.0)))],
            ),
            ...form,
          ]);
        }),
      ),
    );
  }
}

// ------------------------------------------------------------------ hazır tasarım düzenleyici (katman listesi)

class StoreTemplateEditor extends StatefulWidget {
  const StoreTemplateEditor({super.key, required this.product, required this.template, required this.assets});
  final Map<String, dynamic> product;
  final Map<String, dynamic> template;
  final StoreAdminAssets assets;

  @override
  State<StoreTemplateEditor> createState() => _StoreTemplateEditorState();
}

class _StoreTemplateEditorState extends State<StoreTemplateEditor> {
  late final Map<String, dynamic> _t = widget.template;
  late final Map<String, dynamic> _d = () {
    final d = storeMap(_t['design']);
    d['layers'] = storeList(d['layers']);
    _t['design'] = d;
    return d;
  }();
  late String _view = storeProductViews(widget.product).first;
  int? _sel;

  List<Map<String, dynamic>> get _layers => _d['layers'] as List<Map<String, dynamic>>;
  List<Map<String, dynamic>> get _areas => storeList(widget.product['printAreas']);
  int get _maxText => storeNum(widget.product['maxTextLen']).toInt() > 0 ? storeNum(widget.product['maxTextLen']).toInt() : 24;

  String _viewOfArea(String area) => '${_areas.where((a) => '${a['id']}' == area).firstOrNull?['view'] ?? 'front'}';

  void _add(String type) {
    if (_layers.length >= 8) return storeToast(context, 'Bir tasarımda en çok 8 katman olabilir.');
    final area = '${_areas.where((a) => '${a['view']}' == _view).firstOrNull?['id'] ?? _areas.firstOrNull?['id'] ?? 'front'}';
    final l = <String, dynamic>{'type': type, 'area': area, 'x': .5, 'y': .5, 'scale': 1.0, 'rot': 0};
    switch (type) {
      case 'logo':
        l['logo'] = widget.assets.logos.firstOrNull?.$1 ?? 'hadi_wordmark';
      case 'sticker':
        l['sticker'] = widget.assets.stickers.firstOrNull?.$1 ?? '';
      default:
        l['text'] = 'HADİ';
        l['font'] = widget.assets.fonts.firstOrNull?.$1 ?? 'Bricolage';
        l['color'] = '#17344F';
        l['weight'] = 700;
    }
    setState(() {
      _layers.add(l);
      _sel = _layers.length - 1;
    });
  }

  void _save() {
    final name = '${_t['name'] ?? ''}'.trim();
    if (name.isEmpty) return storeToast(context, 'Tasarıma bir ad ver.');
    for (final l in _layers) {
      if (l['type'] == 'text' && ('${l['text'] ?? ''}'.trim().isEmpty || '${l['text']}'.length > _maxText)) {
        return storeToast(context, 'Yazı katmanları boş olamaz ve en çok $_maxText karakter olabilir.');
      }
    }
    Navigator.of(context).pop({..._t, 'name': name});
  }

  Widget _slider(String label, Map<String, dynamic> l, String k, double min, double max, {int? divisions, String Function(double)? fmt}) {
    final v = storeNum(l[k]).toDouble().clamp(min, max);
    return Row(children: [
      SizedBox(width: 74, child: Text(label, style: const TextStyle(fontSize: 12.5))),
      Expanded(child: Slider(value: v, min: min, max: max, divisions: divisions, onChanged: (x) => setState(() => l[k] = double.parse(x.toStringAsFixed(3))))),
      SizedBox(width: 44, child: Text(fmt?.call(v) ?? v.toStringAsFixed(2), style: TextStyle(color: HadiColors.ink3, fontSize: 12))),
    ]);
  }

  Widget _layerEditor(int i) {
    final l = _layers[i];
    final type = '${l['type']}';
    return Container(
      key: ObjectKey(l),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _sel == i ? HadiColors.wash(HadiColors.aktivite) : HadiColors.mist,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _sel == i ? HadiColors.aktivite : Colors.transparent),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() {
            _sel = _sel == i ? null : i;
            _view = _viewOfArea('${l['area']}');
          }),
          child: Row(children: [
            Text(switch (type) { 'logo' => '🔷', 'sticker' => '✨', _ => '🔤' }),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                switch (type) {
                  'logo' => 'Logo · ${widget.assets.logos.where((x) => x.$1 == l['logo']).firstOrNull?.$2 ?? l['logo']}',
                  'sticker' => 'Sticker · ${widget.assets.stickers.where((x) => x.$1 == l['sticker']).firstOrNull?.$2 ?? l['sticker']}',
                  _ => 'Yazı · “${l['text'] ?? ''}”',
                },
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: 'Öne getir',
              visualDensity: VisualDensity.compact,
              onPressed: i == _layers.length - 1 ? null : () => setState(() {
                _layers.insert(i + 1, _layers.removeAt(i));
                _sel = i + 1;
              }),
              icon: const Icon(Icons.flip_to_front_rounded, size: 20),
            ),
            IconButton(
              tooltip: 'Kaldır',
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() {
                _layers.removeAt(i);
                _sel = null;
              }),
              icon: Icon(Icons.delete_outline_rounded, size: 20, color: HadiColors.error),
            ),
          ]),
        ),
        if (_sel == i) ...[
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _areas.any((a) => '${a['id']}' == l['area']) ? '${l['area']}' : null,
            decoration: const InputDecoration(labelText: 'Baskı alanı', isDense: true),
            items: [
              for (final a in _areas)
                DropdownMenuItem(value: '${a['id']}', child: Text('${_kAreaIds.where((x) => x.$1 == a['id']).firstOrNull?.$2 ?? a['id']} (${storeViewLabel('${a['view']}')})')),
            ],
            onChanged: (v) => setState(() {
              l['area'] = v;
              _view = _viewOfArea('$v');
            }),
          ),
          const SizedBox(height: 8),
          if (type == 'logo')
            DropdownButtonFormField<String>(
              initialValue: widget.assets.logos.any((x) => x.$1 == l['logo']) ? '${l['logo']}' : null,
              decoration: const InputDecoration(labelText: 'Logo', isDense: true),
              items: [for (final x in widget.assets.logos) DropdownMenuItem(value: x.$1, child: Text(x.$2))],
              onChanged: (v) => setState(() => l['logo'] = v),
            ),
          if (type == 'sticker')
            widget.assets.stickers.isEmpty
                ? Text('Sticker listesi katalogdan yüklenemedi.', style: TextStyle(color: HadiColors.ink3, fontSize: 12))
                : DropdownButtonFormField<String>(
                    initialValue: widget.assets.stickers.any((x) => x.$1 == l['sticker']) ? '${l['sticker']}' : null,
                    decoration: const InputDecoration(labelText: 'Sticker', isDense: true),
                    items: [for (final x in widget.assets.stickers) DropdownMenuItem(value: x.$1, child: Text(x.$2))],
                    onChanged: (v) => setState(() => l['sticker'] = v),
                  ),
          if (type == 'text') ...[
            TextFormField(
              initialValue: '${l['text'] ?? ''}',
              maxLength: _maxText,
              decoration: const InputDecoration(labelText: 'Yazı', isDense: true),
              onChanged: (v) => setState(() => l['text'] = v),
            ),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: widget.assets.fonts.any((x) => x.$1 == l['font']) ? '${l['font']}' : null,
                  decoration: const InputDecoration(labelText: 'Yazı tipi', isDense: true),
                  items: [for (final x in widget.assets.fonts) DropdownMenuItem(value: x.$1, child: Text(x.$2))],
                  onChanged: (v) => setState(() => l['font'] = v),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Kalın'),
                selected: storeNum(l['weight']) >= 600,
                onSelected: (v) => setState(() => l['weight'] = v ? 700 : 400),
              ),
              const SizedBox(width: 8),
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () async {
                  final c = await showStoreColorPicker(context, storeHexColor('${l['color']}') ?? HadiColors.navy);
                  if (c != null) setState(() => l['color'] = storeColorHex(c));
                },
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: storeHexColor('${l['color']}') ?? HadiColors.navy, shape: BoxShape.circle, border: Border.all(color: HadiColors.line, width: 2)),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 6),
          _slider('Yatay', l, 'x', 0, 1),
          _slider('Dikey', l, 'y', 0, 1),
          _slider('Boyut', l, 'scale', .1, 2),
          _slider('Açı', l, 'rot', -180, 180, divisions: 72, fmt: (v) => '${v.round()}°'),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = storeList(widget.product['colors']);
    final views = storeProductViews(widget.product);
    final preview = Column(mainAxisSize: MainAxisSize.min, children: [
      LayoutBuilder(builder: (context, cons) {
        final w = cons.maxWidth.clamp(160.0, 360.0);
        return ClipRRect(borderRadius: BorderRadius.circular(16), child: storeDesignPreview(widget.product, _d, view: _view, width: w));
      }),
      const SizedBox(height: 8),
      Wrap(spacing: 6, alignment: WrapAlignment.center, children: [
        for (final v in views) ChoiceChip(label: Text(storeViewLabel(v)), selected: _view == v, onSelected: (_) => setState(() => _view = v)),
      ]),
    ]);
    final form = <Widget>[
      TextFormField(
        initialValue: '${_t['name'] ?? ''}',
        maxLength: 40,
        decoration: const InputDecoration(labelText: 'Tasarım adı', isDense: true),
        onChanged: (v) => _t['name'] = v,
      ),
      DropdownButtonFormField<String>(
        initialValue: colors.any((c) => '${c['id']}' == _d['colorId']) ? '${_d['colorId']}' : null,
        decoration: const InputDecoration(labelText: 'Varsayılan renk', isDense: true),
        items: [
          for (final c in colors)
            DropdownMenuItem(
              value: '${c['id']}',
              child: Row(children: [
                Container(width: 14, height: 14, decoration: BoxDecoration(color: storeHexColor('${c['hex']}'), shape: BoxShape.circle, border: Border.all(color: HadiColors.line))),
                const SizedBox(width: 8),
                Text('${c['name']}'),
              ]),
            ),
        ],
        onChanged: (v) => setState(() => _d['colorId'] = v),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Text('Katmanlar (${_layers.length}/8)', style: const TextStyle(fontWeight: FontWeight.w900))),
        PopupMenuButton<String>(
          tooltip: 'Katman ekle',
          onSelected: _add,
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'logo', child: Text('🔷 Logo')),
            const PopupMenuItem(value: 'text', child: Text('🔤 Yazı')),
            if (widget.assets.stickers.isNotEmpty) const PopupMenuItem(value: 'sticker', child: Text('✨ Sticker')),
          ],
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add_rounded, size: 18), SizedBox(width: 4), Text('Katman ekle')]),
          ),
        ),
      ]),
      Text('Sonraki katman üstte çizilir. Konum baskı alanının içinde: 0,5 / 0,5 = ortası.', style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
      const SizedBox(height: 8),
      if (_areas.isEmpty) Text('Önce ürüne bir baskı alanı ekle.', style: TextStyle(color: HadiColors.error)),
      for (var i = _layers.length - 1; i >= 0; i--) _layerEditor(i),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('${_t['name'] ?? 'Tasarım'}', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [Padding(padding: const EdgeInsets.only(right: 10), child: FilledButton(onPressed: _save, child: const Text('Tamam')))],
      ),
      body: LayoutBuilder(builder: (context, cons) {
        if (cons.maxWidth >= 860) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 400, child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: StoreCard(child: preview))),
            Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(8, 16, 16, 40), children: form)),
          ]);
        }
        return ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 40), children: [StoreCard(child: preview), const SizedBox(height: 12), ...form]);
      }),
    );
  }
}

// ------------------------------------------------------------------ renk seçici

/// Basit renk seçici: HADİ renkleri + yaygın kumaş renkleri, ton/doygunluk/parlaklık kaydırıcıları ve hex kodu.
Future<Color?> showStoreColorPicker(BuildContext context, Color initial) => showDialog<Color>(
      context: context,
      builder: (_) => _ColorPickerDialog(initial: initial),
    );

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial});
  final Color initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final _hex = TextEditingController(text: storeColorHex(widget.initial));

  static const _swatches = [
    Color(0xFFFFFFFF), Color(0xFFF4F1EA), Color(0xFFBDBDBD), Color(0xFF6E6E6E), Color(0xFF1A1A1A),
    HadiColors.navy, HadiColors.heyecan, HadiColors.aktivite, HadiColors.dostluk, HadiColors.iletisim, HadiColors.pink,
    Color(0xFF8B1E2D), Color(0xFF2E5E3A), Color(0xFFC9B08A), Color(0xFF7FA7D9), Color(0xFFF6D64A),
  ];

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _setColor(Color c, {bool fromHex = false}) => setState(() {
        _hsv = HSVColor.fromColor(c);
        if (!fromHex) _hex.text = storeColorHex(c);
      });

  Widget _bar(String label, double v, double max, ValueChanged<double> on) => Row(children: [
        SizedBox(width: 82, child: Text(label, style: const TextStyle(fontSize: 12.5))),
        Expanded(child: Slider(value: v, max: max, onChanged: on)),
      ]);

  @override
  Widget build(BuildContext context) {
    final c = _hsv.toColor();
    return AlertDialog(
      title: const Text('Renk seç'),
      content: SizedBox(
        width: 340,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(height: 56, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(12), border: Border.all(color: HadiColors.line))),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in _swatches)
              InkWell(
                onTap: () => _setColor(s),
                customBorder: const CircleBorder(),
                child: Container(width: 28, height: 28, decoration: BoxDecoration(color: s, shape: BoxShape.circle, border: Border.all(color: HadiColors.line))),
              ),
          ]),
          const SizedBox(height: 6),
          _bar('Ton', _hsv.hue, 360, (v) => _setColor(_hsv.withHue(v).toColor())),
          _bar('Doygunluk', _hsv.saturation, 1, (v) => _setColor(_hsv.withSaturation(v).toColor())),
          _bar('Parlaklık', _hsv.value, 1, (v) => _setColor(_hsv.withValue(v).toColor())),
          TextField(
            controller: _hex,
            decoration: const InputDecoration(labelText: 'Kod (#RRGGBB)', isDense: true),
            onChanged: (v) {
              final x = storeHexColor(v);
              if (x != null) _setColor(x, fromHex: true);
            },
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context, c), child: const Text('Seç')),
      ],
    );
  }
}
