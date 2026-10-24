// HADİ Crew / Kurucu Paneli — Mağaza siparişleri kuyruğu (store › adminOrders, adminOrderUpdate).
// Akış: Yeni (ödendi) → Üretime al → Kargoya ver (firma + takip no; bağlantı şablondan) → Teslim edildi.
// İptal/iade gerekçe ister (üyeye iletilir, kayda geçer). Baskı dosyası tarayıcıda çizilir (renderStoreDesignPng):
// her kalem × her görünüm (ön/arka/sargı) için ayrı PNG, adında sipariş no. Sipariş fişi yeni sekmede yazdırılır.
// Adres yalnızca yönetim yanıtında gelir; teslimden 30 gün sonra sunucu maskeler (masked: true).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hadi/core/format.dart';
import 'package:hadi/core/money.dart';
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/hadi_sheet.dart';
import 'package:hadi/widgets/reason_dialog.dart';
import 'package:hadi/widgets/skeleton.dart';

import 'store_admin_common.dart';
import 'store_preview_bridge.dart';
import 'store_web_file.dart';

class StoreOrdersAdminTab extends StatefulWidget {
  const StoreOrdersAdminTab({super.key, this.embedded = true});
  final bool embedded;

  @override
  State<StoreOrdersAdminTab> createState() => _StoreOrdersAdminTabState();
}

/// Süzgeç sekmeleri: ad + sunucuya giden durumlar (boş = tümü).
const _kFilters = <(String, List<String>)>[
  ('Yeni · ödendi', ['paid']),
  ('Üretimde', ['in_production']),
  ('Kargoda', ['shipped']),
  ('Teslim edildi', ['delivered']),
  ('Hediye adresi bekliyor', ['awaiting_address']),
  ('İptal / İade', ['cancelled', 'refunded']),
  ('Tümü', []),
];

class _StoreOrdersAdminTabState extends State<StoreOrdersAdminTab> {
  int _filter = 0;
  List<Map<String, dynamic>>? _orders;
  String? _error;
  String? _openId;

  /// Ürünler (önizleme için; pasifler dahil) ve ayarlar (kargo firmaları).
  Map<String, Map<String, dynamic>> _products = {};
  Map<String, dynamic> _config = {};

  @override
  void initState() {
    super.initState();
    _loadMeta();
    _load();
  }

  Future<void> _loadMeta() async {
    try {
      final products = storeAdminProducts(context);
      final config = storeAdminConfig(context);
      final p = await products, c = await config;
      if (!mounted) return;
      setState(() {
        _products = {for (final x in p) '${x['id']}': x};
        _config = c;
      });
    } catch (_) {
      // Önizleme ve firma listesi olmadan da kuyruk çalışır.
    }
  }

  Future<void> _load() async {
    final statuses = _kFilters[_filter].$2;
    try {
      final parts = statuses.isEmpty
          ? [await storeAdminOrders(context)]
          : await Future.wait([for (final s in statuses) storeAdminOrders(context, status: s)]);
      final all = [for (final r in parts) ...r];
      all.sort((a, b) => (storeTime(b['createdAt'])?.millisecondsSinceEpoch ?? 0).compareTo(storeTime(a['createdAt'])?.millisecondsSinceEpoch ?? 0));
      if (!mounted) return;
      setState(() {
        _orders = all;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _orders = const [];
          _error = storeError(e);
        });
      }
    }
  }

  void _pick(int i) {
    if (i == _filter) return;
    setState(() {
      _filter = i;
      _orders = null;
      _openId = null;
    });
    _load();
  }

  Widget _filters() => SizedBox(
        height: 48,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), children: [
          for (var i = 0; i < _kFilters.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(label: Text(_kFilters[i].$1), selected: _filter == i, onSelected: (_) => _pick(i)),
            ),
        ]),
      );

  Widget _list({required bool wide}) {
    final list = _orders;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 32), children: [
        if (list == null) ...const [ListTileSkeleton(), ListTileSkeleton(), ListTileSkeleton()],
        if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: TextStyle(color: HadiColors.ink2))),
        if (list != null && list.isEmpty && _error == null)
          Padding(padding: const EdgeInsets.all(28), child: Text('Bu durumda sipariş yok 🎉', textAlign: TextAlign.center, style: TextStyle(color: HadiColors.ink3))),
        for (final o in list ?? const <Map<String, dynamic>>[])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _OrderTile(
              order: o,
              selected: wide && _openId == '${o['id']}',
              onTap: () async {
                if (wide) {
                  setState(() => _openId = '${o['id']}');
                  return;
                }
                await Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: Text('Sipariş ${_shortId(o['id'])}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    body: _OrderDetail(order: o, products: _products, config: _config, onChanged: _load),
                  ),
                ));
                await _load();
              },
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = LayoutBuilder(builder: (context, cons) {
      final wide = cons.maxWidth >= 980;
      if (!wide) return Column(children: [_filters(), Expanded(child: _list(wide: false))]);
      final open = (_orders ?? const <Map<String, dynamic>>[]).where((o) => '${o['id']}' == _openId).firstOrNull;
      return Column(children: [
        _filters(),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: 380, child: _list(wide: true)),
            const VerticalDivider(width: 1),
            Expanded(
              child: open == null
                  ? Center(child: Text('Ayrıntı için soldan bir sipariş seç.', style: TextStyle(color: HadiColors.ink3)))
                  : _OrderDetail(key: ValueKey('o-${open['id']}-${open['status']}'), order: open, products: _products, config: _config, onChanged: _load),
            ),
          ]),
        ),
      ]);
    });
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(
              title: const Text('Mağaza siparişleri', maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [IconButton(tooltip: 'Yenile', onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
            ),
            body: body,
          );
  }
}

String _shortId(Object? id) {
  final s = '${id ?? ''}';
  return s.length > 8 ? '#${s.substring(0, 8).toUpperCase()}' : '#${s.toUpperCase()}';
}

String _buyerName(Map<String, dynamic> o) => '${o['buyerName'] ?? o['fromName'] ?? o['name'] ?? o['uidName'] ?? o['uid'] ?? '—'}';

int _itemCount(Map<String, dynamic> o) {
  var n = 0;
  for (final it in storeList(o['items'])) {
    n += storeNum(it['qty'] ?? 1).toInt();
  }
  return n;
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order, required this.onTap, this.selected = false});
  final Map<String, dynamic> order;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final items = storeList(o['items']);
    final status = '${o['status'] ?? ''}';
    final gift = (o['giftTo'] ?? '').toString().isNotEmpty;
    final pay = storeMap(o['pay']);
    return Material(
      color: selected ? HadiColors.wash(HadiColors.aktivite) : HadiColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? HadiColors.aktivite : HadiColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(_shortId(o['id']), style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(width: 8),
              if (gift) const Text('🎁 '),
              Expanded(child: Text(storeWhen(o['createdAt']), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: HadiColors.ink3, fontSize: 12))),
              StoreStatusChip(status),
            ]),
            const SizedBox(height: 6),
            Text(
              items.map((it) => '${storeNum(it['qty'] ?? 1).toInt()}× ${it['title'] ?? it['productId']}').join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              [
                _buyerName(o),
                if (gift) '→ ${o['giftToName'] ?? 'hediye'}',
                '${_itemCount(o)} adet',
                storeTotalText(storeMap(o['total']), method: '${pay['method'] ?? ''}'),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: HadiColors.ink2, fontSize: 12.5),
            ),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ ayrıntı

class _OrderDetail extends StatefulWidget {
  const _OrderDetail({super.key, required this.order, required this.products, required this.config, required this.onChanged});
  final Map<String, dynamic> order;
  final Map<String, Map<String, dynamic>> products;
  final Map<String, dynamic> config;
  final Future<void> Function() onChanged;

  @override
  State<_OrderDetail> createState() => _OrderDetailState();
}

class _OrderDetailState extends State<_OrderDetail> {
  late Map<String, dynamic> _o = widget.order;
  bool _busy = false, _rendering = false;

  String get _id => '${_o['id']}';
  String get _status => '${_o['status'] ?? ''}';

  Map<String, dynamic> _productOf(Map<String, dynamic> it) =>
      widget.products['${it['productId']}'] ?? {'id': it['productId'], 'title': it['title'], 'category': it['category'], 'views': const ['front']};

  String _colorName(Map<String, dynamic> product, Map<String, dynamic> it) {
    if ('${it['colorName'] ?? ''}'.isNotEmpty) return '${it['colorName']}';
    final cid = '${it['colorId'] ?? storeMap(it['design'])['colorId'] ?? ''}';
    final c = storeList(product['colors']).where((c) => '${c['id']}' == cid).firstOrNull;
    return c == null ? cid : '${c['name']}';
  }

  Future<void> _update(String status, {String? carrier, String? carrierName, String? trackingNo, String? trackingUrl, String? note, String done = 'Sipariş güncellendi.'}) async {
    setState(() => _busy = true);
    try {
      await storeAdminOrderUpdate(context, _id, status: status, carrier: carrier, carrierName: carrierName, trackingNo: trackingNo, trackingUrl: trackingUrl, note: note);
      if (!mounted) return;
      setState(() => _o = {
            ..._o,
            'status': status,
            'carrier': ?carrier,
            'carrierName': ?carrierName,
            'trackingNo': ?trackingNo,
            'trackingUrl': ?trackingUrl,
            'statusLog': [...storeList(_o['statusLog']), {'status': status, 'at': DateTime.now().millisecondsSinceEpoch, 'note': ?note}],
          });
      storeToast(context, done);
      await widget.onChanged();
    } catch (e) {
      if (mounted) storeToast(context, storeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toProduction() => _update('in_production', done: 'Sipariş üretime alındı.');

  Future<void> _delivered() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Teslim edildi olarak işaretle'),
        content: const Text('Kargo firması teslimatı doğruladıysa işaretle. Üyeye bildirim gider.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Teslim edildi')),
        ],
      ),
    );
    if (ok == true) await _update('delivered', done: 'Teslim edildi olarak işaretlendi.');
  }

  Future<void> _cancel() async {
    final reason = await askReason(
      context,
      title: 'İptal et ve iade et',
      message: 'Ödeme tamamen iade edilir (Elmas cüzdana, kart ödemesi iade kuyruğuna). Gerekçe üyeye iletilir ve kayda geçer.',
      confirm: 'İptal et ve iade et',
      danger: true,
      hint: 'Örn. "Seçilen renk tedarikçide kalmadı, üyeyle konuşuldu."',
    );
    if (reason == null || reason.trim().isEmpty) return;
    await _update('cancelled', note: reason.trim(), done: 'Sipariş iptal edildi; iade başlatıldı.');
  }

  Future<void> _ship() async {
    final carriers = storeList(widget.config['carriers']);
    final r = await showHadiSheet<({String carrier, String name, String no, String url, String note})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _ShipSheet(carriers: carriers, initialCarrier: '${_o['carrier'] ?? ''}', initialNo: '${_o['trackingNo'] ?? ''}'),
    );
    if (r == null) return;
    await _update('shipped', carrier: r.carrier, carrierName: r.name.isEmpty ? null : r.name, trackingNo: r.no.isEmpty ? null : r.no, trackingUrl: r.url, note: r.note.isEmpty ? null : r.note, done: 'Kargoya verildi; üyeye takip bağlantısı gönderildi.');
  }

  /// Baskı dosyaları: her kalem × tasarımında katman olan her görünüm.
  Future<void> _downloadPrint() async {
    setState(() => _rendering = true);
    var n = 0;
    try {
      final items = storeList(_o['items']);
      for (var i = 0; i < items.length; i++) {
        final it = items[i];
        final p = _productOf(it);
        final design = storeMap(it['design']);
        for (final view in _viewsWithLayers(p, design)) {
          final png = await storeDesignPng(p, design, view: view);
          final name = 'hadi-siparis-${_id}_${i + 1}-${it['productId']}-$view.png'.replaceAll(RegExp(r'[^A-Za-z0-9_.\-]'), '_');
          storeDownloadBytes(png, name);
          n++;
          // Tarayıcı art arda indirmeleri engellemesin.
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
      }
      if (mounted) storeToast(context, n == 0 ? 'Basılacak tasarım yok.' : '$n baskı dosyası indirildi.');
    } catch (e) {
      if (mounted) storeToast(context, 'Baskı dosyası hazırlanamadı: ${e is UnsupportedError ? e.message : storeError(e)}');
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  /// Katmanların bulunduğu görünümler (baskı alanı → görünüm). Tasarım boşsa ürünün ilk görünümü (düz baskı / renk).
  List<String> _viewsWithLayers(Map<String, dynamic> product, Map<String, dynamic> design) {
    final areaView = {for (final a in storeList(product['printAreas'])) '${a['id']}': '${a['view'] ?? 'front'}'};
    final views = <String>[];
    for (final l in storeList(design['layers'])) {
      final v = areaView['${l['area']}'] ?? 'front';
      if (!views.contains(v)) views.add(v);
    }
    if (views.isEmpty) views.add(storeProductViews(product).first);
    final order = storeProductViews(product);
    views.sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
    return views;
  }

  String _receiptText() {
    final o = _o;
    final ship = storeMap(o['ship']);
    final pay = storeMap(o['pay']);
    final b = StringBuffer()
      ..writeln('HADİ Mağaza — Sipariş ${_shortId(o['id'])}')
      ..writeln('Sipariş no: ${o['id']}')
      ..writeln('Tarih: ${storeWhen(o['createdAt'])}')
      ..writeln('Durum: ${storeStatusLabel(_status)}')
      ..writeln();
    for (final it in storeList(o['items'])) {
      final p = _productOf(it);
      final size = '${it['size'] ?? storeMap(it['design'])['size'] ?? ''}';
      b.writeln('• ${storeNum(it['qty'] ?? 1).toInt()} × ${it['title'] ?? p['title']} — renk: ${_colorName(p, it)}${size.isNotEmpty ? ', beden: $size' : ''}');
    }
    b.writeln();
    if (ship.isNotEmpty) {
      b
        ..writeln('Alıcı: ${ship['recipient'] ?? ''}')
        ..writeln('Telefon: ${ship['phone'] ?? ''}')
        ..writeln('Adres: ${ship['line'] ?? [ship['ilce'], ship['il']].where((x) => x != null).join('/')}');
      if ('${ship['tarif'] ?? ''}'.isNotEmpty) b.writeln('Tarif: ${ship['tarif']}');
    }
    if ('${o['note'] ?? ''}'.isNotEmpty) b.writeln('Not: ${o['note']}');
    b.writeln('Ödeme: ${pay['method'] == 'elmas' ? 'Elmas' : 'Kart'} · ${storeTotalText(storeMap(o['total']), method: '${pay['method'] ?? ''}')}');
    if ('${o['carrier'] ?? ''}'.isNotEmpty) b.writeln('Kargo: ${_carrierName(o['carrier'])} · ${o['trackingNo'] ?? ''}');
    return b.toString();
  }

  String _carrierName(Object? id) {
    if ('${_o['carrierName'] ?? ''}'.isNotEmpty) return '${_o['carrierName']}';
    final c = storeList(widget.config['carriers']).where((c) => '${c['id']}' == '$id').firstOrNull;
    return c == null ? '${id ?? ''}' : '${c['name']}';
  }

  void _print() {
    final o = _o;
    final ship = storeMap(o['ship']);
    final pay = storeMap(o['pay']);
    final e = storeHtmlEscape;
    final rows = StringBuffer();
    for (final it in storeList(o['items'])) {
      final p = _productOf(it);
      final size = '${it['size'] ?? storeMap(it['design'])['size'] ?? ''}';
      final layers = storeList(storeMap(it['design'])['layers']);
      final texts = [for (final l in layers) if ('${l['text'] ?? ''}'.isNotEmpty) '“${l['text']}”'].join(', ');
      rows.write('<tr><td>${storeNum(it['qty'] ?? 1).toInt()}</td><td><b>${e('${it['title'] ?? p['title']}')}</b>'
          '${texts.isNotEmpty ? '<br><small>Yazı: ${e(texts)}</small>' : ''}</td>'
          '<td>${e(_colorName(p, it))}</td><td>${e(size.isEmpty ? '—' : size)}</td>'
          '<td>${e(layers.length.toString())} katman</td><td><input type="checkbox"></td></tr>');
    }
    final html = '''<!doctype html><html lang="tr"><head><meta charset="utf-8"><title>Sipariş ${e(_shortId(o['id']))}</title>
<style>body{font-family:system-ui,-apple-system,"Segoe UI",sans-serif;margin:28px;color:#17344F}h1{font-size:22px;margin:0}
.muted{color:#5b6b7b;font-size:13px}table{width:100%;border-collapse:collapse;margin-top:16px}td,th{border-bottom:1px solid #ddd;padding:8px;text-align:left;font-size:14px;vertical-align:top}
.box{border:2px solid #17344F;border-radius:10px;padding:14px;margin-top:18px;font-size:15px;line-height:1.5}.grid{display:flex;gap:24px;flex-wrap:wrap}
@media print{button{display:none}body{margin:12mm}}</style></head><body>
<button onclick="window.print()" style="float:right;padding:8px 14px">Yazdır</button>
<h1>HADİ Mağaza · Sipariş ${e(_shortId(o['id']))}</h1>
<div class="muted">Sipariş no: ${e('${o['id']}')} · ${e(storeWhen(o['createdAt']))} · ${e(storeStatusLabel(_status))}</div>
<table><thead><tr><th>Adet</th><th>Ürün</th><th>Renk</th><th>Beden</th><th>Tasarım</th><th>✓</th></tr></thead><tbody>$rows</tbody></table>
<div class="grid">
<div class="box" style="flex:2"><b>Teslimat</b><br>${ship.isEmpty ? 'Adres yok' : '${e('${ship['recipient'] ?? ''}')}<br>${e('${ship['phone'] ?? ''}')}<br>${e('${ship['line'] ?? ''}')}${'${ship['tarif'] ?? ''}'.isNotEmpty ? '<br><i>${e('${ship['tarif']}')}</i>' : ''}'}</div>
<div class="box" style="flex:1"><b>Ödeme</b><br>${pay['method'] == 'elmas' ? 'Elmas' : 'Kart'}<br>${e(storeTotalText(storeMap(o['total']), method: '${pay['method'] ?? ''}'))}
${'${o['carrier'] ?? ''}'.isNotEmpty ? '<br><br><b>Kargo</b><br>${e(_carrierName(o['carrier']))}<br>${e('${o['trackingNo'] ?? ''}')}' : ''}</div>
</div>
${'${o['note'] ?? ''}'.isNotEmpty ? '<div class="box"><b>Hediye notu</b><br>${e('${o['note']}')}</div>' : ''}
<script>window.addEventListener('load',function(){setTimeout(function(){window.print()},300)})</script>
</body></html>''';
    if (!storeOpenPrintable(html)) {
      Clipboard.setData(ClipboardData(text: _receiptText()));
      storeToast(context, 'Yeni sekme açılamadı (açılır pencere engeli). Fiş metni panoya kopyalandı.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
    final items = storeList(o['items']);
    final ship = storeMap(o['ship']);
    final pay = storeMap(o['pay']);
    final gift = '${o['giftTo'] ?? ''}'.isNotEmpty;
    final log = storeList(o['statusLog']);
    final status = _status;
    final canProduce = status == 'paid';
    final canShip = status == 'paid' || status == 'in_production';
    final canDeliver = status == 'shipped';
    final canCancel = const ['paid', 'in_production', 'awaiting_address'].contains(status);

    return LayoutBuilder(builder: (context, cons) {
      final pv = (cons.maxWidth - 64).clamp(160.0, 300.0);
      return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 40), children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SelectableText('Sipariş ${_shortId(o['id'])}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
              Text('${storeWhen(o['createdAt'])} · ${o['id']}', style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
            ]),
          ),
          StoreStatusChip(status),
        ]),
        const SizedBox(height: 12),
        // İşlemler
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (canProduce) FilledButton.icon(onPressed: _busy ? null : _toProduction, icon: const Icon(Icons.precision_manufacturing_rounded), label: const Text('Üretime al')),
          if (canShip) FilledButton.tonalIcon(onPressed: _busy ? null : _ship, icon: const Icon(Icons.local_shipping_rounded), label: const Text('Kargoya ver')),
          if (status == 'shipped')
            OutlinedButton.icon(onPressed: _busy ? null : _ship, icon: const Icon(Icons.edit_location_alt_rounded), label: const Text('Kargo bilgisini düzelt')),
          if (canDeliver) FilledButton.icon(onPressed: _busy ? null : _delivered, icon: const Icon(Icons.done_all_rounded), label: const Text('Teslim edildi')),
          OutlinedButton.icon(
            onPressed: _rendering ? null : _downloadPrint,
            icon: _rendering ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_rounded),
            label: const Text('Baskı dosyasını indir'),
          ),
          OutlinedButton.icon(onPressed: _print, icon: const Icon(Icons.print_rounded), label: const Text('Sipariş fişini yazdır')),
          if (canCancel)
            TextButton.icon(
              onPressed: _busy ? null : _cancel,
              style: TextButton.styleFrom(foregroundColor: HadiColors.error),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('İptal et ve iade et'),
            ),
        ]),
        if (status == 'awaiting_address')
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: StoreCard(
              color: HadiColors.wash(HadiColors.pink),
              child: Text('Hediye alıcısı henüz teslimat adresini seçmedi. Seçince sipariş "Yeni" olarak kuyruğa düşer; süre dolarsa gönderene iade edilir.',
                  style: TextStyle(color: HadiColors.ink2, fontSize: 13)),
            ),
          ),
        if ('${o['trackingNo'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: StoreCard(
              child: Row(children: [
                const Text('🚚 ', style: TextStyle(fontSize: 18)),
                Expanded(child: SelectableText('${_carrierName(o['carrier'])} · ${o['trackingNo']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                if ('${o['trackingUrl'] ?? ''}'.startsWith('https://'))
                  TextButton(onPressed: () => launchUrl(Uri.parse('${o['trackingUrl']}'), mode: LaunchMode.externalApplication), child: const Text('Takip et')),
              ]),
            ),
          ),

        StoreSectionTitle('Ürünler (${_itemCount(o)} adet)'),
        for (final it in items) _itemCard(it, pv),

        StoreSectionTitle('Kişiler'),
        StoreCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _kv('Sipariş veren', _buyerName(o)),
            if (gift) _kv('Hediye alıcısı', '${o['giftToName'] ?? o['giftTo']}${o['anonymous'] == true ? ' (gönderen gizli)' : ''}'),
            if ('${o['note'] ?? ''}'.isNotEmpty) _kv(gift ? 'Hediye notu' : 'Not', '${o['note']}'),
          ]),
        ),

        StoreSectionTitle('Teslimat adresi',
            trailing: ship.isEmpty || ship['masked'] == true
                ? null
                : TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: [ship['recipient'], ship['phone'], ship['line'], if ('${ship['tarif'] ?? ''}'.isNotEmpty) 'Tarif: ${ship['tarif']}']
                          .where((x) => x != null && '$x'.isNotEmpty)
                          .join('\n')));
                      storeToast(context, 'Adres panoya kopyalandı.');
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Kopyala'),
                  )),
        StoreCard(
          child: ship.isEmpty
              ? Text(status == 'awaiting_address' ? 'Alıcının adres seçmesi bekleniyor.' : 'Adres bilgisi yok.', style: TextStyle(color: HadiColors.ink2))
              : ship['masked'] == true
                  ? Text('Adres gizlilik gereği maskelendi (${[ship['ilce'], ship['il']].where((x) => x != null && '$x'.isNotEmpty).join('/')}).',
                      style: TextStyle(color: HadiColors.ink2))
                  : SelectableText.rich(TextSpan(children: [
                      TextSpan(text: '${ship['recipient'] ?? ''}\n', style: const TextStyle(fontWeight: FontWeight.w800)),
                      TextSpan(text: '${ship['phone'] ?? ''}\n'),
                      TextSpan(text: '${ship['line'] ?? ''}'),
                      if ('${ship['tarif'] ?? ''}'.isNotEmpty) TextSpan(text: '\nTarif: ${ship['tarif']}', style: TextStyle(color: HadiColors.ink2)),
                    ])),
        ),

        const StoreSectionTitle('Ödeme'),
        StoreCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _kv('Yöntem', pay['method'] == 'elmas' ? '💎 Satın alınmış Elmas' : '💳 Kart (iyzico)'),
            _kv('Ürünler', _subtotal(o, '${pay['method'] ?? ''}')),
            _kv('Kargo', _shipText(storeMap(o['shipping']), '${pay['method'] ?? ''}')),
            _kv('Toplam', storeTotalText(storeMap(o['total']), method: '${pay['method'] ?? ''}'), bold: true),
            if ('${pay['brand'] ?? ''}${pay['last4'] ?? ''}'.isNotEmpty) _kv('Kart', '${pay['brand'] ?? ''} •••• ${pay['last4'] ?? ''}'.trim()),
            if ('${pay['ref'] ?? pay['cpId'] ?? ''}'.isNotEmpty) _kv('Ödeme kaydı', '${pay['ref'] ?? pay['cpId']}'),
          ]),
        ),

        const StoreSectionTitle('Durum geçmişi'),
        StoreCard(
          child: log.isEmpty
              ? Text('Kayıt yok.', style: TextStyle(color: HadiColors.ink2))
              : Column(children: [
                  for (var i = 0; i < log.length; i++) _logRow(log[i], last: i == log.length - 1),
                ]),
        ),
      ]);
    });
  }

  String _subtotal(Map<String, dynamic> o, String method) {
    num tl = 0, el = 0;
    for (final it in storeList(o['items'])) {
      final q = storeNum(it['qty'] ?? 1);
      tl += storeNum(it['unitTl']) * q;
      el += storeNum(it['unitElmas']) * q;
    }
    return method == 'elmas' ? elmasText(el) : money(tl);
  }

  String _shipText(Map<String, dynamic> s, String method) {
    final v = method == 'elmas' ? storeNum(s['elmas']) : storeNum(s['tl']);
    if (v == 0) return 'Ücretsiz';
    return method == 'elmas' ? elmasText(v) : money(v);
  }

  Widget _kv(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(k, style: TextStyle(color: HadiColors.ink3, fontSize: 13))),
          Expanded(child: SelectableText(v, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w600))),
        ]),
      );

  Widget _logRow(Map<String, dynamic> l, {required bool last}) {
    final s = '${l['status'] ?? ''}';
    final c = storeStatusColor(s);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 22,
          child: Column(children: [
            Container(width: 12, height: 12, margin: const EdgeInsets.only(top: 4), decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            if (!last) Expanded(child: Container(width: 2, color: HadiColors.line)),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(storeStatusLabel(s), style: const TextStyle(fontWeight: FontWeight.w800)),
              Text([storeWhen(l['at']), if ('${l['byName'] ?? l['by'] ?? ''}'.isNotEmpty) '${l['byName'] ?? l['by']}'].join(' · '),
                  style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
              if ('${l['note'] ?? ''}'.isNotEmpty) Text('${l['note']}', style: TextStyle(color: HadiColors.ink2, fontSize: 13)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _itemCard(Map<String, dynamic> it, double pv) {
    final p = _productOf(it);
    final design = storeMap(it['design']);
    final views = _viewsWithLayers(p, design);
    final allViews = storeProductViews(p);
    final shown = [...views, for (final v in allViews) if (!views.contains(v) && v != 'wrap') v];
    final size = '${it['size'] ?? design['size'] ?? ''}';
    final texts = [for (final l in storeList(design['layers'])) if ('${l['text'] ?? ''}'.isNotEmpty) '${l['text']}'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: StoreCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(storeCategoryEmoji('${p['category'] ?? it['category'] ?? ''}'), style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Expanded(child: Text('${it['title'] ?? p['title'] ?? it['productId']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5))),
            Text('× ${storeNum(it['qty'] ?? 1).toInt()}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          ]),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _pill('Renk: ${_colorName(p, it)}', dot: storeHexColor('${storeList(p['colors']).where((c) => '${c['id']}' == '${it['colorId'] ?? design['colorId']}').firstOrNull?['hex'] ?? ''}')),
            if (size.isNotEmpty) _pill('Beden: $size'),
            _pill('${storeList(design['layers']).length} katman'),
            if (storeNum(it['unitTl']) > 0) _pill('Birim ${money(storeNum(it['unitTl']))}'),
            if (storeNum(it['unitElmas']) > 0) _pill('Birim ${elmasText(storeNum(it['unitElmas']))}'),
          ]),
          if (texts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SelectableText('Yazılar: ${texts.map((t) => '“$t”').join(', ')}', style: TextStyle(color: HadiColors.ink2, fontSize: 13)),
            ),
          const SizedBox(height: 10),
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final v in shown)
              Column(mainAxisSize: MainAxisSize.min, children: [
                ClipRRect(borderRadius: BorderRadius.circular(14), child: storeDesignPreview(p, design, view: v, width: pv)),
                const SizedBox(height: 4),
                Text(storeViewLabel(v), style: TextStyle(color: HadiColors.ink3, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
          ]),
        ]),
      ),
    );
  }

  Widget _pill(String t, {Color? dot}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: HadiColors.mist, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot != null) ...[
            Container(width: 12, height: 12, decoration: BoxDecoration(color: dot, shape: BoxShape.circle, border: Border.all(color: HadiColors.line))),
            const SizedBox(width: 5),
          ],
          Text(t, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        ]),
      );
}

// ------------------------------------------------------------------ kargoya ver

class _ShipSheet extends StatefulWidget {
  const _ShipSheet({required this.carriers, required this.initialCarrier, required this.initialNo});
  final List<Map<String, dynamic>> carriers;
  final String initialCarrier, initialNo;

  @override
  State<_ShipSheet> createState() => _ShipSheetState();
}

class _ShipSheetState extends State<_ShipSheet> {
  late String? _carrier = widget.carriers.any((c) => '${c['id']}' == widget.initialCarrier)
      ? widget.initialCarrier
      : (widget.carriers.isNotEmpty ? '${widget.carriers.first['id']}' : null);
  late final _no = TextEditingController(text: widget.initialNo);
  final _url = TextEditingController();
  final _other = TextEditingController();
  final _note = TextEditingController();

  /// Bağlantı elle değiştirildiyse şablondan yeniden yazılmaz.
  bool _urlTouched = false;

  @override
  void initState() {
    super.initState();
    _refreshUrl();
  }

  @override
  void dispose() {
    for (final c in [_no, _url, _other, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _refreshUrl() {
    if (_urlTouched) return;
    final tpl = '${widget.carriers.where((c) => '${c['id']}' == _carrier).firstOrNull?['urlTemplate'] ?? ''}';
    final no = _no.text.trim();
    _url.text = tpl.isEmpty || no.isEmpty ? '' : tpl.replaceAll('{no}', Uri.encodeComponent(no));
  }

  void _submit() {
    final no = _no.text.trim();
    final url = _url.text.trim();
    final carrier = _carrier ?? '';
    final other = _other.text.trim();
    if (carrier.isEmpty) return storeToast(context, 'Kargo firmasını seç.');
    if (carrier == 'other' && other.isEmpty) return storeToast(context, 'Kargo firmasının adını yaz.');
    if (no.isNotEmpty && !RegExp(r'^[A-Za-z0-9-]{3,40}$').hasMatch(no.replaceAll(' ', ''))) {
      return storeToast(context, 'Takip numarası 3–40 karakter olmalı (harf, rakam, tire).');
    }
    if (no.isEmpty && url.isEmpty) return storeToast(context, 'Takip numarasını yaz.');
    if (carrier == 'other' && url.isEmpty) return storeToast(context, 'Listede olmayan firma için takip bağlantısını da yaz.');
    if (url.isNotEmpty && !url.startsWith('https://')) return storeToast(context, 'Takip bağlantısı https:// ile başlamalı.');
    Navigator.pop(context, (carrier: carrier, name: carrier == 'other' ? other : '', no: no.replaceAll(' ', ''), url: url, note: _note.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Kargoya ver', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Üyeye takip bağlantısıyla bildirim gider.', style: TextStyle(color: HadiColors.ink2, fontSize: 13)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _carrier,
            decoration: const InputDecoration(labelText: 'Kargo firması'),
            items: [
              for (final c in widget.carriers) DropdownMenuItem(value: '${c['id']}', child: Text('${c['name']}')),
              const DropdownMenuItem(value: 'other', child: Text('Diğer…')),
            ],
            onChanged: (v) => setState(() {
              _carrier = v;
              _urlTouched = false;
              _refreshUrl();
            }),
          ),
          if (_carrier == 'other')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(controller: _other, decoration: const InputDecoration(labelText: 'Firma adı')),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _no,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Takip numarası'),
            onChanged: (_) => setState(_refreshUrl),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Takip bağlantısı',
              helperText: _urlTouched ? 'Elle düzenlendi.' : 'Firmanın şablonundan otomatik; gerekirse düzenle.',
              suffixIcon: _urlTouched
                  ? IconButton(
                      tooltip: 'Şablondan yeniden oluştur',
                      onPressed: () => setState(() {
                        _urlTouched = false;
                        _refreshUrl();
                      }),
                      icon: const Icon(Icons.restart_alt_rounded),
                    )
                  : null,
            ),
            onChanged: (_) => setState(() => _urlTouched = true),
          ),
          const SizedBox(height: 8),
          TextField(controller: _note, maxLength: 200, decoration: const InputDecoration(labelText: 'Not (isteğe bağlı, kayda geçer)')),
          const SizedBox(height: 4),
          FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.local_shipping_rounded), label: const Text('Kargoya verildi')),
        ]),
      ),
    );
  }
}
