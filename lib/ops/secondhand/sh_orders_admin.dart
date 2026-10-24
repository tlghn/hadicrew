// HADİ Crew — 2. El siparişleri ve ödemeler: durum süzgeci, sipariş ayrıntısı (kart kalemleri: bloke / onaylı / iade),
// anlaşmalı kargo kaydı (teslim adresi yalnızca "Adresi göster" ile açılır; erişim "Verime erişimler"e yazılır), elle olay
// (kargoya verildi, teslim edildi, iade ulaştı, iptal) ve Ödemeler: serbest bırakılan / bekleyen tutarlar, IBAN'ı eksik satıcılar.
import 'package:flutter/material.dart';
import 'package:hadi/panel_ui/crew_ui.dart';
import 'package:hadi/theme/hadi_colors.dart';

import 'sh_admin_common.dart';

class ShOrdersAdminTab extends StatefulWidget {
  const ShOrdersAdminTab({super.key, this.embedded = true});
  final bool embedded;
  @override
  State<ShOrdersAdminTab> createState() => _ShOrdersAdminTabState();
}

class _ShOrdersAdminTabState extends State<ShOrdersAdminTab> {
  String _view = 'orders';
  String _status = '';
  List<Map<String, dynamic>>? _orders;
  Map<String, dynamic>? _pay;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_view == 'orders') {
      final r = await shAdminCall(context, 'adminOrders', {'status': _status});
      if (mounted) setState(() => _orders = r == null ? const [] : [for (final x in (r['orders'] as List? ?? const [])) (x as Map).cast<String, dynamic>()]);
    } else {
      final r = await shAdminCall(context, 'adminPayouts');
      if (mounted) setState(() => _pay = r ?? const {});
    }
  }

  @override
  Widget build(BuildContext context) => CrewPage(
        title: '2. El siparişleri',
        subtitle: 'Emanetteki ödemeler, kargo kaydı ve satıcı ödemeleri',
        embedded: widget.embedded,
        onRefresh: _load,
        toolbar: CrewToolbar(
          filters: CrewFilterChips<String>(
            options: const [('orders', 'Siparişler'), ('payouts', 'Ödemeler')],
            value: _view,
            onChanged: (v) {
              setState(() => (_view = v, _orders = null, _pay = null));
              _load();
            },
          ),
          trailing: [
            if (_view == 'orders')
              PopupMenuButton<String>(
                tooltip: 'Durum',
                initialValue: _status,
                onSelected: (v) {
                  setState(() => (_status = v, _orders = null));
                  _load();
                },
                itemBuilder: (_) => [for (final s in kShOrderStatuses) PopupMenuItem(value: s.$1, child: Text(s.$2))],
                child: Chip(avatar: const Icon(Icons.filter_list_rounded, size: 18), label: Text(kShOrderStatuses.firstWhere((s) => s.$1 == _status).$2)),
              ),
          ],
        ),
        children: _view == 'orders' ? _ordersList() : _payouts(),
      );

  List<Widget> _ordersList() {
    final o = _orders;
    if (o == null) return const [CrewLoading()];
    return [
      CrewListCard(
        empty: const CrewEmpty(title: 'Sipariş yok', message: 'Bu durumda sipariş bulunmuyor.', icon: Icons.receipt_long_outlined),
        children: [
          for (final x in o)
            ListTile(
              leading: ShAdminThumb(url: ((x['items'] as List?)?.firstOrNull as Map?)?['cover'] as String?, size: 44),
              title: Text('${((x['items'] as List?)?.firstOrNull as Map?)?['title'] ?? x['id']}', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${x['buyerName'] ?? ''} → ${x['sellerName'] ?? ''} · ${shTl(((x['quote'] as Map?)?['totalK'] as num?) ?? 0)} · ${shWhen(x['createdAt'])}', maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: CrewPill('${x['statusLabel'] ?? x['status']}', color: shOrderColor('${x['status']}')),
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ShOrderDetailPage(id: '${x['id']}')));
                _load();
              },
            ),
        ],
      ),
    ];
  }

  List<Widget> _payouts() {
    final p = _pay;
    if (p == null) return const [CrewLoading()];
    final released = [for (final x in (p['released'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
    final held = [for (final x in (p['held'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
    final missing = [for (final x in (p['sellersMissingPayout'] as List? ?? const [])) '$x'];
    return [
      const CrewNote('Satıcı payı iyzico\'da "bloke" (onaylanmamış kalem) durur; alıcı onaylayınca, süre dolunca, QR okutulunca ya da uyuşmazlık kararıyla onaylanır ve iyzico satıcının IBAN\'ına aktarır. HADİ üçüncü kişi parası tutmaz.'),
      if (missing.isNotEmpty)
        CrewCard(
          title: 'IBAN / kimlik bilgisi eksik satıcılar',
          icon: Icons.account_balance_outlined,
          tone: HadiColors.heyecan,
          children: [CrewNote('${missing.length} satıcının açık siparişi var ama alt üye işyeri kaydı hazır değil: ${missing.take(10).join(', ')}', icon: Icons.warning_amber_rounded)],
        ),
      CrewListCard(
        title: 'Bekleyen (emanette)',
        subtitle: 'Açık siparişler · satıcıya geçecek tutar',
        empty: const CrewEmpty(title: 'Emanette ödeme yok'),
        children: [
          for (final x in held)
            ListTile(
              title: Text('${x['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${x['sellerName'] ?? ''}${x['inspectUntil'] != null ? ' · inceleme bitişi ${shWhen(x['inspectUntil'])}' : ''}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [CrewPill('${x['status']}', color: shOrderColor('${x['status']}')), const SizedBox(width: CrewSpace.sm), Text(shTl((x['netK'] as num?) ?? 0))]),
            ),
        ],
      ),
      CrewListCard(
        title: 'Serbest bırakılan',
        subtitle: 'Son tamamlanan siparişler · iyzico kalem durumu',
        empty: const CrewEmpty(title: 'Henüz tamamlanan satış yok'),
        children: [
          for (final x in released)
            ListTile(
              title: Text('${x['title']}', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${x['sellerName'] ?? ''} · ${shWhen(x['completedAt'])}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                CrewPill(x['cardState'] == 'approved' ? 'Onaylandı' : x['cardState'] == 'held' ? 'Onay kuyrukta' : '${x['cardState']}', color: x['cardState'] == 'approved' ? HadiColors.dostluk : HadiColors.heyecan),
                const SizedBox(width: CrewSpace.sm),
                Text(shTl((x['netK'] as num?) ?? 0)),
              ]),
            ),
        ],
      ),
    ];
  }
}

class ShOrderDetailPage extends StatefulWidget {
  const ShOrderDetailPage({super.key, required this.id, this.withAddress = false});
  final String id;
  final bool withAddress;
  @override
  State<ShOrderDetailPage> createState() => _ShOrderDetailPageState();
}

class _ShOrderDetailPageState extends State<ShOrderDetailPage> {
  Map<String, dynamic>? _d;
  late bool _addr = widget.withAddress;
  String? _carrier;
  final _tracking = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tracking.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await shAdminCall(context, 'adminOrder', {'id': widget.id, 'withAddress': _addr});
    if (mounted) setState(() => _d = r);
  }

  Future<void> _event(String ev, String label) async {
    final note = await askReason(context, title: label, danger: ev == 'cancel');
    if (note == null || !mounted) return;
    final r = await shAdminCall(context, 'adminOrderEvent', {'id': widget.id, 'event': ev, 'note': note}, 'Kaydedildi.');
    if (r != null) _load();
  }

  Future<void> _saveShipment() async {
    if (_carrier == null || _tracking.text.trim().length < 4) return crewToast(context, 'Kargo firmasını ve takip numarasını gir.');
    final r = await shAdminCall(context, 'adminShipment', {'id': widget.id, 'carrier': _carrier, 'trackingCode': _tracking.text.trim()}, 'Kargo kaydı hazır; satıcıya bildirildi.');
    if (r != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final o = ((d?['order'] as Map?) ?? const {}).cast<String, dynamic>();
    final q = ((o['quote'] as Map?) ?? const {}).cast<String, dynamic>();
    final sh = ((o['shipment'] as Map?) ?? const {}).cast<String, dynamic>();
    final ship = ((o['ship'] as Map?) ?? const {}).cast<String, dynamic>();
    final card = ((d?['card'] as Map?) ?? const {}).cast<String, dynamic>();
    final carriers = shAdminOf(context).config.carriers.isEmpty ? const [('yurtici', 'Yurtiçi Kargo'), ('aras', 'Aras Kargo'), ('mng', 'MNG Kargo'), ('ptt', 'PTT Kargo')] : shAdminOf(context).config.carriers;
    final status = '${o['status'] ?? ''}';
    return CrewPage(
      title: 'Sipariş',
      subtitle: '${((o['items'] as List?)?.firstOrNull as Map?)?['title'] ?? widget.id}',
      maxWidth: CrewWidth.form,
      onRefresh: _load,
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Elle işlem',
          onSelected: (v) => _event(v, const {'ship': 'Kargoya verildi olarak işaretle', 'deliver': 'Teslim edildi olarak işaretle', 'return_received': 'İade ürün ulaştı', 'cancel': 'Siparişi iptal et (tam iade)'}[v]!),
          itemBuilder: (_) => [
            if (status == 'paid' && o['delivery'] == 'shipping') const PopupMenuItem(value: 'ship', child: Text('Kargoya verildi')),
            if (status == 'shipped') const PopupMenuItem(value: 'deliver', child: Text('Teslim edildi')),
            if (status == 'returning') const PopupMenuItem(value: 'return_received', child: Text('İade ürün ulaştı')),
            if (status == 'paid' || status == 'shipped') const PopupMenuItem(value: 'cancel', child: Text('İptal et (tam iade)')),
          ],
        ),
      ],
      children: d == null
          ? [const CrewLoading()]
          : [
              CrewCard(
                title: 'Özet',
                action: CrewPill('${o['statusLabel'] ?? status}', color: shOrderColor(status)),
                children: [
                  CrewInfoRow('Alıcı → satıcı', '${o['buyerName'] ?? ''} → ${o['sellerName'] ?? ''}'),
                  CrewInfoRow('Teslim', o['delivery'] == 'meetup' ? 'Elden · ${(o['meetup'] as Map?)?['ilce'] ?? ''}' : 'Anlaşmalı kargo'),
                  CrewInfoRow('Ürün', shTl((q['itemsK'] as num?) ?? 0)),
                  CrewInfoRow('Komisyon', shTl((q['commissionK'] as num?) ?? 0)),
                  CrewInfoRow('Alıcı koruma ücreti', shTl((q['buyerFeeK'] as num?) ?? 0)),
                  CrewInfoRow('Kargo (alıcıdan / maliyet)', '${shTl((q['shippingK'] as num?) ?? 0)} / ${shTl((q['shippingCostK'] as num?) ?? 0)}'),
                  CrewInfoRow('Toplam', shTl((q['totalK'] as num?) ?? 0)),
                  CrewInfoRow('Ödeme', 'Kart •••• ${(o['card'] as Map?)?['last4'] ?? ''} · ${(o['card'] as Map?)?['ref'] ?? ''}'),
                  CrewInfoRow('Ödendi / kargo / teslim', '${shWhen(o['paidAt'])} · ${shWhen(o['shippedAt'])} · ${shWhen(o['deliveredAt'])}'),
                ],
              ),
              if (card.isNotEmpty)
                CrewTableCard(
                  title: 'iyzico kalemleri',
                  table: DataTable(columns: const [DataColumn(label: Text('Kalem')), DataColumn(label: Text('Tutar'), numeric: true), DataColumn(label: Text('Durum')), DataColumn(label: Text('İade'), numeric: true)], rows: [
                    for (final i in (card['items'] as List? ?? const []))
                      DataRow(cells: [
                        DataCell(Text(const {'item': 'Ürün (satıcı)', 'fee': 'Alıcı koruması (HADİ)', 'ship': 'Kargo (HADİ)'}['${(i as Map)['key']}'] ?? '${i['key']}')),
                        DataCell(Text(shTl((i['priceK'] as num?) ?? 0))),
                        DataCell(Text(const {'held': 'Bloke', 'approved': 'Onaylandı', 'refunded': 'İade edildi'}['${i['state']}'] ?? '${i['state']}')),
                        DataCell(Text(shTl((i['refundedK'] as num?) ?? 0))),
                      ]),
                  ]),
                ),
              if (o['delivery'] == 'shipping')
                CrewCard(
                  title: 'Anlaşmalı kargo kaydı',
                  icon: Icons.local_shipping_outlined,
                  action: _addr ? null : TextButton.icon(onPressed: () {
                    setState(() => _addr = true);
                    _load();
                  }, icon: const Icon(Icons.visibility_outlined, size: 18), label: const Text('Adresi göster')),
                  children: [
                    CrewInfoRow('HADİ kargo kodu', '${sh['hadiCode'] ?? '—'}'),
                    CrewInfoRow('Kayıt', sh['label'] == 'ready' ? 'Hazır · ${sh['carrierName'] ?? sh['carrier'] ?? ''} ${sh['trackingCode'] ?? ''}' : 'Bekliyor'),
                    if (_addr && ship.isNotEmpty) ...[
                      CrewInfoRow('Alıcı', '${ship['recipient'] ?? ''} · ${ship['phone'] ?? ''}'),
                      CrewInfoRow('Adres', ship['masked'] == true ? '${ship['ilce'] ?? ''}/${ship['il'] ?? ''} (maskelendi)' : '${ship['line'] ?? ''}'),
                      if ('${ship['tarif'] ?? ''}'.isNotEmpty) CrewInfoRow('Tarif', '${ship['tarif']}'),
                      const CrewNote('Bu erişim alıcının "Verime erişimler" sayfasına yazıldı. Adresi yalnızca kargo kaydı için kullan.'),
                    ],
                    if (sh['label'] != 'ready') ...[
                      CrewFormGrid(children: [
                        DropdownButtonFormField<String>(
                          initialValue: _carrier,
                          items: [for (final c in carriers) DropdownMenuItem(value: c.$1, child: Text(c.$2))],
                          onChanged: (v) => setState(() => _carrier = v),
                          decoration: const InputDecoration(labelText: 'Kargo firması'),
                        ),
                        TextField(controller: _tracking, decoration: const InputDecoration(labelText: 'Takip numarası')),
                      ]),
                      Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: _saveShipment, child: const Text('Kaydı tamamla'))),
                    ],
                  ],
                ),
              if ((o['history'] as List? ?? const []).isNotEmpty)
                CrewListCard(title: 'Geçmiş', children: [
                  for (final h in (o['history'] as List)) ListTile(dense: true, title: Text('${(h as Map)['ev']} → ${h['to'] ?? ''}'), subtitle: Text('${h['by'] ?? ''}'), trailing: Text(shWhen(h['at']))),
                ]),
            ],
    );
  }
}
