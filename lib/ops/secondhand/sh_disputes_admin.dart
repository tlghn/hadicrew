// HADİ Crew — 2. El uyuşmazlıkları: alıcının sorunu ve kanıt fotoğrafları, satıcının yanıtı ve kanıtları, ilan sohbeti, sipariş
// geçmişi → karar: ödemeyi satıcıya bırak · kısmi iade · tam iade · iade kargosuyla tam iade. Karar gerekçesi iki tarafa gider.
// Kanıt ve sohbete erişim "Verime erişimler"e yazılır (sunucu: secondhand_admin.ts › adminDispute).
import 'package:flutter/material.dart';
import 'package:hadi/panel_ui/crew_ui.dart';
import 'package:hadi/theme/hadi_colors.dart';

import 'sh_admin_common.dart';

class ShDisputesAdminTab extends StatefulWidget {
  const ShDisputesAdminTab({super.key, this.embedded = true});
  final bool embedded;
  @override
  State<ShDisputesAdminTab> createState() => _ShDisputesAdminTabState();
}

class _ShDisputesAdminTabState extends State<ShDisputesAdminTab> {
  String _status = 'open';
  List<Map<String, dynamic>>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await shAdminCall(context, 'adminDisputes', {'status': _status == 'all' ? '' : _status});
    if (mounted) setState(() => _items = r == null ? const [] : [for (final x in (r['disputes'] as List? ?? const [])) (x as Map).cast<String, dynamic>()]);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return CrewPage(
      title: '2. El uyuşmazlıkları',
      subtitle: '"Tarif edildiği gibi değil" bildirimleri ve kararlar',
      embedded: widget.embedded,
      onRefresh: _load,
      toolbar: CrewToolbar(
        filters: CrewFilterChips<String>(
          options: const [('open', 'Yeni'), ('replied', 'Satıcı yanıtladı'), ('decided', 'Karara bağlandı'), ('all', 'Tümü')],
          value: _status,
          onChanged: (v) {
            setState(() => (_status = v, _items = null));
            _load();
          },
        ),
      ),
      children: [
        if (items == null) const CrewLoading(),
        if (items != null)
          CrewListCard(
            empty: const CrewEmpty(title: 'Uyuşmazlık yok', message: 'Alıcı inceleme süresinde sorun bildirince burada görünür.', icon: Icons.handshake_outlined),
            children: [
              for (final d in items)
                ListTile(
                  leading: const Icon(Icons.report_outlined),
                  title: Text('${(d['order'] as Map?)?['title'] ?? d['id']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${d['reason'] ?? ''} · ${(d['order'] as Map?)?['buyerName'] ?? ''} → ${(d['order'] as Map?)?['sellerName'] ?? ''} · ${shWhen(d['createdAt'])}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: CrewPill(
                    d['status'] == 'decided' ? 'Karar verildi' : d['replied'] == true ? 'Yanıt geldi' : 'Satıcı yanıtı bekleniyor',
                    color: d['status'] == 'decided' ? HadiColors.dostluk : d['replied'] == true ? HadiColors.heyecan : HadiColors.aktivite,
                  ),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ShDisputeDetailPage(id: '${d['id']}')));
                    _load();
                  },
                ),
            ],
          ),
      ],
    );
  }
}

class ShDisputeDetailPage extends StatefulWidget {
  const ShDisputeDetailPage({super.key, required this.id});
  final String id;
  @override
  State<ShDisputeDetailPage> createState() => _ShDisputeDetailPageState();
}

class _ShDisputeDetailPageState extends State<ShDisputeDetailPage> {
  Map<String, dynamic>? _d;
  String _outcome = 'release';
  final _refund = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _refund.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await shAdminCall(context, 'adminDispute', {'id': widget.id});
    if (mounted) setState(() => _d = r);
  }

  Future<void> _decide() async {
    const labels = {'release': 'Ödemeyi satıcıya bırak', 'partial': 'Kısmi iade yap', 'refund': 'Tam iade yap', 'return': 'İade kargosu ile tam iade'};
    final note = await askReason(context, title: labels[_outcome]!, message: 'Gerekçe alıcıya ve satıcıya bildirilir.', confirm: 'Karar ver', danger: _outcome != 'release');
    if (note == null || !mounted) return;
    setState(() => _busy = true);
    final r = await shAdminCall(context, 'adminDisputeDecide', {
      'id': widget.id, 'outcome': _outcome, if (_outcome == 'partial') 'refundTl': num.tryParse(_refund.text.replaceAll(',', '.').trim()), 'note': note,
    }, 'Karar kaydedildi; taraflara bildirildi.');
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) _load();
  }

  Widget _photos(List<dynamic>? list) {
    final items = [for (final e in list ?? const []) (e as Map).cast<String, dynamic>()];
    if (items.isEmpty) return const CrewNote('Fotoğraf eklenmemiş.');
    return Wrap(spacing: CrewSpace.sm, runSpacing: CrewSpace.sm, children: [
      for (final e in items)
        InkWell(
          onTap: e['url'] == null ? null : () => showDialog<void>(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.network('${e['url']}')))),
          child: ShAdminThumb(url: e['url'] as String?, emoji: '🖼️', size: 110),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final ds = ((d?['dispute'] as Map?) ?? const {}).cast<String, dynamic>();
    final o = ((d?['order'] as Map?) ?? const {}).cast<String, dynamic>();
    final q = ((o['quote'] as Map?) ?? const {}).cast<String, dynamic>();
    final decided = ds['status'] == 'decided';
    return CrewPage(
      title: 'Uyuşmazlık',
      subtitle: '${(o['items'] as List?)?.firstOrNull is Map ? ((o['items'] as List).first as Map)['title'] : widget.id}',
      maxWidth: CrewWidth.form,
      onRefresh: _load,
      children: d == null
          ? [const CrewLoading()]
          : [
              CrewCard(
                title: 'Sipariş',
                children: [
                  CrewInfoRow('Durum', '${o['statusLabel'] ?? o['status'] ?? ''}'),
                  CrewInfoRow('Alıcı → satıcı', '${o['buyerName'] ?? ''} → ${o['sellerName'] ?? ''}'),
                  CrewInfoRow('Ürün bedeli', shTl((q['itemsK'] as num?) ?? 0)),
                  CrewInfoRow('Alıcının ödediği', shTl((q['totalK'] as num?) ?? 0)),
                  CrewInfoRow('Teslim', '${o['delivery'] == 'meetup' ? 'Elden' : 'Kargo'} · teslim ${shWhen(o['deliveredAt'])}'),
                  for (final h in (o['history'] as List? ?? const [])) CrewNote('${shWhen((h as Map)['at'])} · ${h['ev']} · ${h['to'] ?? ''}', icon: Icons.history_rounded),
                ],
              ),
              CrewCard(
                title: 'Alıcının bildirimi',
                icon: Icons.report_outlined,
                children: [
                  CrewInfoRow('Neden', '${ds['reason'] ?? ''}'),
                  CrewInfoRow('Açıklama', '${ds['details'] ?? ''}'),
                  _photos(ds['evidence'] as List?),
                ],
              ),
              CrewCard(
                title: 'Satıcının yanıtı',
                icon: Icons.reply_rounded,
                children: [
                  CrewInfoRow('Yanıt', '${ds['sellerReply'] ?? 'Henüz yanıt yok (son tarih ${shWhen(ds['replyDue'])})'}'),
                  _photos(ds['sellerEvidence'] as List?),
                ],
              ),
              if ((d['messages'] as List? ?? const []).isNotEmpty)
                CrewListCard(
                  title: 'İlan sohbeti',
                  subtitle: 'Son mesajlar (telefon/IBAN gizli)',
                  children: [
                    for (final m in (d['messages'] as List))
                      ListTile(dense: true, leading: Text('${(m as Map)['from']}'), title: Text('${m['text']}'), trailing: Text(shWhen(m['at']), style: Theme.of(context).textTheme.bodySmall)),
                  ],
                ),
              CrewCard(
                title: decided ? 'Karar' : 'Karar ver',
                icon: Icons.gavel_rounded,
                children: decided
                    ? [
                        CrewInfoRow('Sonuç', '${(ds['decision'] as Map?)?['outcome'] ?? ''}'),
                        CrewInfoRow('Gerekçe', '${(ds['decision'] as Map?)?['note'] ?? ''}'),
                        if ((ds['decision'] as Map?)?['refundK'] != null) CrewInfoRow('İade', shTl(((ds['decision'] as Map)['refundK'] as num?) ?? 0)),
                      ]
                    : [
                        RadioGroup<String>(
                          groupValue: _outcome,
                          onChanged: (v) => setState(() => _outcome = v ?? 'release'),
                          child: const Column(children: [
                            RadioListTile(value: 'release', title: Text('Ödemeyi satıcıya bırak'), subtitle: Text('Ürün tarif edildiği gibi.')),
                            RadioListTile(value: 'partial', title: Text('Kısmi iade'), subtitle: Text('Küçük kusur: bir kısmı alıcıya iade, kalanı satıcıya.')),
                            RadioListTile(value: 'refund', title: Text('Tam iade (ürün alıcıda kalır)'), subtitle: Text('Ürün değersiz / sahte / hiç gelmedi.')),
                            RadioListTile(value: 'return', title: Text('İade kargosuyla tam iade'), subtitle: Text('Alıcı ürünü HADİ iade kodu ile geri gönderir; satıcıya ulaşınca iade.')),
                          ]),
                        ),
                        if (_outcome == 'partial')
                          CrewFormGrid(children: [TextField(controller: _refund, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'İade tutarı', suffixText: '₺'))]),
                        Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: _busy ? null : _decide, child: const Text('Karar ver'))),
                      ],
              ),
            ],
    );
  }
}
