// HADİ Crew — 2. El inceleme kuyruğu: ilan incelemesi (kural/YZ/dolandırıcılık nedenleriyle), itirazlar, şikâyetler,
// dolandırıcılık sinyalleri (hesap kısıtlama) ve anlaşmalı kargo kaydı (teslim adresi; erişim "Verime erişimler"e yazılır).
// Uyuşmazlıklar ayrı ekranda (sh_disputes_admin.dart). Her karar gerekçeli (askReason) ve sunucuda kayıtlı.
import 'package:flutter/material.dart';
import 'package:hadi/panel_ui/crew_ui.dart';
import 'package:hadi/theme/hadi_colors.dart';

import 'sh_admin_common.dart';
import 'sh_disputes_admin.dart' show ShDisputeDetailPage;
import 'sh_orders_admin.dart' show ShOrderDetailPage;

class ShQueueAdminTab extends StatefulWidget {
  const ShQueueAdminTab({super.key, this.embedded = true, this.initialKind = 'listing'});
  final bool embedded;
  final String initialKind;
  @override
  State<ShQueueAdminTab> createState() => _ShQueueAdminTabState();
}

class _ShQueueAdminTabState extends State<ShQueueAdminTab> {
  late String _kind = widget.initialKind;
  bool _done = false;
  List<Map<String, dynamic>>? _items;
  Map<String, dynamic>? _dash;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await shAdminCall(context, 'adminQueue', {'kind': _kind, 'status': _done ? 'done' : 'open'});
    if (!mounted) return;
    final d = await shAdminCall(context, 'adminDash');
    if (!mounted) return;
    setState(() {
      _items = r == null ? null : [for (final x in (r['items'] as List? ?? const [])) (x as Map).cast<String, dynamic>()];
      _err = r == null ? 'Kuyruk yüklenemedi.' : null;
      _dash = d;
    });
  }

  Future<void> _open(Map<String, dynamic> q) async {
    final kind = '${q['kind']}';
    final ref = '${q['ref']}';
    Widget page;
    switch (kind) {
      case 'listing' || 'appeal':
        page = ShListingReviewPage(id: ref, queue: q);
      case 'dispute':
        page = ShDisputeDetailPage(id: ref);
      case 'shipping':
        page = ShOrderDetailPage(id: ref, withAddress: true);
      case 'fraud':
        page = ShFraudPage(queue: q);
      default:
        page = ShReportPage(queue: q);
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final counts = ((_dash?['queues'] as Map?) ?? const {}).cast<String, dynamic>();
    final items = _items;
    return CrewPage(
      title: '2. El inceleme',
      subtitle: 'İlanlar, itirazlar, şikâyetler, dolandırıcılık ve kargo kaydı',
      embedded: widget.embedded,
      onRefresh: _load,
      actions: [
        IconButton(tooltip: 'Yenile', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ],
      toolbar: CrewToolbar(
        filters: CrewFilterChips<String>(
          options: [for (final k in kShQueueKinds) (k.$1, k.$2)],
          value: _kind,
          counts: {for (final k in kShQueueKinds) k.$1: (counts[k.$1] as num?)?.toInt() ?? 0},
          onChanged: (v) {
            setState(() => (_kind = v, _items = null));
            _load();
          },
        ),
        trailing: [
          FilterChip(
            label: const Text('Sonuçlananlar'),
            selected: _done,
            onSelected: (v) {
              setState(() => (_done = v, _items = null));
              _load();
            },
          ),
        ],
      ),
      children: [
        if (_dash != null) _DashCard(_dash!),
        if (items == null && _err == null) const CrewLoading(),
        if (_err != null) CrewError(message: _err!, onRetry: _load),
        if (items != null)
          CrewListCard(
            title: shKindLabel(_kind),
            subtitle: _done ? 'Sonuçlanan son 100 kayıt' : 'Bekleyen işler (en yeni üstte)',
            empty: CrewEmpty(title: 'Bekleyen iş yok', message: _done ? 'Bu türde sonuçlanan kayıt yok.' : 'Yeni bir kayıt geldiğinde burada ve panoda görünür.', icon: Icons.check_circle_outline_rounded),
            children: [
              for (final q in items)
                ListTile(
                  leading: Icon(shKindIcon('${q['kind']}')),
                  title: Text('${q['summary'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [for (final r in (q['reasons'] as List? ?? const [])) '$r'].join(' · ').isEmpty ? shWhen(q['createdAt']) : '${[for (final r in (q['reasons'] as List)) '$r'].join(' · ')}\n${shWhen(q['createdAt'])}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: (q['reasons'] as List? ?? const []).isNotEmpty,
                  trailing: _done ? CrewPill('Sonuçlandı', color: HadiColors.dostluk) : CrewPill(shPriorityLabel('${q['priority']}'), color: shPriorityColor('${q['priority']}')),
                  onTap: () => _open(q),
                ),
            ],
          ),
      ],
    );
  }
}

class _DashCard extends StatelessWidget {
  const _DashCard(this.d);
  final Map<String, dynamic> d;
  @override
  Widget build(BuildContext context) {
    final l = ((d['listings'] as Map?) ?? const {}).cast<String, dynamic>();
    final o = ((d['orders'] as Map?) ?? const {}).cast<String, dynamic>();
    final gmv = ((d['gmv30'] as Map?) ?? const {}).cast<String, dynamic>();
    final rev = ((d['revenue30'] as Map?) ?? const {}).cast<String, dynamic>();
    final t = Theme.of(context);
    Widget stat(String label, String value) => SizedBox(
          width: 170,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Text(label, style: t.textTheme.bodySmall),
          ]),
        );
    return CrewCard(
      title: 'Özet',
      icon: Icons.insights_rounded,
      children: [
        Wrap(spacing: CrewSpace.xl, runSpacing: CrewSpace.lg, children: [
          stat('Yayındaki ilan', '${l['active'] ?? 0}'),
          stat('İncelemede', '${l['review'] ?? 0}'),
          stat('Açık sipariş', '${o['open'] ?? 0}'),
          stat('30 gün · tamamlanan', '${o['completed30'] ?? 0}'),
          stat('30 gün · işlem hacmi', '${gmv['text'] ?? '—'}'),
          stat('30 gün · HADİ geliri (tahmini)', '${rev['text'] ?? '—'}'),
        ]),
      ],
    );
  }
}

/// İlan incelemesi / itiraz: fotoğraflar, metin, denetim nedenleri, dolandırıcılık puanı, satıcı bilgisi → karar.
class ShListingReviewPage extends StatefulWidget {
  const ShListingReviewPage({super.key, required this.id, this.queue});
  final String id;
  final Map<String, dynamic>? queue;
  @override
  State<ShListingReviewPage> createState() => _ShListingReviewPageState();
}

class _ShListingReviewPageState extends State<ShListingReviewPage> {
  Map<String, dynamic>? _d;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await shAdminCall(context, 'adminListing', {'id': widget.id});
    if (mounted) setState(() => _d = r);
  }

  Future<void> _decide(String decision, String label, {bool danger = false}) async {
    final note = await askReason(context, title: label, message: decision == 'approve' || decision == 'restore' ? 'İlan yayına alınır; satıcıya bildirim gider.' : 'Satıcıya gerekçe ile bildirilir.', confirm: label, danger: danger);
    if (note == null || !mounted) return;
    setState(() => _busy = true);
    final r = await shAdminCall(context, 'adminListingDecide', {'id': widget.id, 'decision': decision, 'note': note}, 'Kaydedildi.');
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final l = ((d?['listing'] as Map?) ?? const {}).cast<String, dynamic>();
    final s = ((d?['seller'] as Map?) ?? const {}).cast<String, dynamic>();
    final mod = ((l['moderation'] as Map?) ?? const {}).cast<String, dynamic>();
    final fraud = ((l['fraud'] as Map?) ?? const {}).cast<String, dynamic>();
    final facts = ((d?['sellerFacts'] as Map?) ?? const {}).cast<String, dynamic>();
    final appeal = ((l['appeal'] as Map?) ?? const {}).cast<String, dynamic>();
    final photos = [for (final p in (l['photos'] as List? ?? const [])) (p as Map).cast<String, dynamic>()];
    return CrewPage(
      title: 'İlan incelemesi',
      subtitle: '${l['title'] ?? ''}',
      maxWidth: CrewWidth.form,
      onRefresh: _load,
      bottomBar: d == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(CrewSpace.md),
                child: Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: CrewSpace.sm, runSpacing: CrewSpace.sm, children: [
                  PopupMenuButton<String>(
                    tooltip: 'Diğer',
                    enabled: !_busy,
                    onSelected: (_) => _decide('remove', 'Yayından kaldır', danger: true),
                    itemBuilder: (_) => const [PopupMenuItem(value: 'remove', child: Text('Yayından kaldır'))],
                  ),
                  OutlinedButton.icon(onPressed: _busy ? null : () => _decide('reject', 'Yayımlama', danger: true), icon: const Icon(Icons.block_rounded), label: const Text('Reddet')),
                  FilledButton.icon(onPressed: _busy ? null : () => _decide(l['status'] == 'rejected' || l['status'] == 'removed' ? 'restore' : 'approve', 'Yayına al'), icon: const Icon(Icons.check_rounded), label: const Text('Yayına al')),
                ]),
              ),
            ),
      children: d == null
          ? [const CrewLoading()]
          : [
              if (photos.isNotEmpty)
                CrewCard(
                  title: 'Fotoğraflar',
                  children: [
                    Wrap(spacing: CrewSpace.sm, runSpacing: CrewSpace.sm, children: [
                      for (final p in photos)
                        Stack(children: [
                          ShAdminThumb(url: '${p['url'] ?? ''}', size: 120),
                          if (p['defect'] == true) Positioned(left: 4, top: 4, child: CrewPill('Kusur', color: HadiColors.error)),
                        ]),
                    ]),
                  ],
                ),
              CrewCard(
                title: 'İlan',
                children: [
                  CrewInfoRow('Başlık', '${l['title'] ?? ''}'),
                  CrewInfoRow('Fiyat', '${l['priceText'] ?? ''}'),
                  CrewInfoRow('Kategori', '${l['categoryEmoji'] ?? ''} ${l['categoryLabel'] ?? ''}'),
                  CrewInfoRow('Durum', '${l['conditionLabel'] ?? ''}'),
                  CrewInfoRow('Satış türü', '${l['saleTypeLabel'] ?? l['saleType'] ?? ''}'),
                  CrewInfoRow('Teslim', '${l['deliveryLabel'] ?? l['delivery'] ?? ''}'),
                  CrewInfoRow('Görünürlük', '${l['visibilityLabel'] ?? l['visibility'] ?? ''}'),
                  CrewInfoRow('İlan durumu', '${l['statusLabel'] ?? l['status'] ?? ''}'),
                  CrewInfoRow('Açıklama', '${l['description'] ?? ''}'),
                  if ('${l['defectNote'] ?? ''}'.isNotEmpty) CrewInfoRow('Kusur', '${l['defectNote']}'),
                ],
              ),
              CrewCard(
                title: 'Denetim nedenleri',
                icon: Icons.rule_rounded,
                children: [
                  CrewInfoRow('Karar', '${mod['verdict'] ?? '—'}'),
                  for (final r in (mod['reasons'] as List? ?? const [])) CrewNote('$r', icon: Icons.label_outline_rounded),
                  if (mod['ai'] is Map) CrewInfoRow('Yapay zekâ', '${(mod['ai'] as Map)['verdict'] ?? ''} · ${(mod['ai'] as Map)['reason'] ?? ''}'),
                  if (fraud.isNotEmpty) CrewInfoRow('Dolandırıcılık puanı', '${fraud['score'] ?? 0}/100'),
                  for (final r in (fraud['reasons'] as List? ?? const [])) CrewNote('$r', icon: Icons.policy_outlined, color: HadiColors.error),
                  if (appeal.isNotEmpty) CrewNote('Satıcının itirazı: ${appeal['text'] ?? ''}', icon: Icons.gavel_rounded),
                ],
              ),
              CrewCard(
                title: 'Satıcı',
                children: [
                  CrewInfoRow('Ad', '${s['name'] ?? ''}'),
                  CrewInfoRow('Seviye', '${s['levelLabel'] ?? ''}${s['verified'] == true ? ' · kimliği doğrulandı' : ''}'),
                  CrewInfoRow('İstatistik', '${s['statsLine'] ?? ''}'),
                  CrewInfoRow('Kaybettiği uyuşmazlık', '${facts['disputesLost'] ?? 0}'),
                  CrewInfoRow('Platform dışı girişim (30 gün)', '${facts['offPlatform30'] ?? 0}'),
                  if (facts['restricted'] is Map) CrewInfoRow('Kısıtlı', '${(facts['restricted'] as Map)['reason'] ?? ''} · ${shWhen((facts['restricted'] as Map)['until'])}'),
                ],
              ),
            ],
    );
  }
}

/// Dolandırıcılık sinyali: hesap düzeyinde karar (temizle / kısıtla).
class ShFraudPage extends StatefulWidget {
  const ShFraudPage({super.key, required this.queue});
  final Map<String, dynamic> queue;
  @override
  State<ShFraudPage> createState() => _ShFraudPageState();
}

class _ShFraudPageState extends State<ShFraudPage> {
  final _days = TextEditingController(text: '30');
  bool _busy = false;

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  Future<void> _act(String action) async {
    final note = await askReason(context, title: action == 'restrict' ? 'Hesabı kısıtla' : 'Sinyali temizle', message: action == 'restrict' ? 'Yayındaki ilanları durdurulur; süre boyunca ilan açamaz ve satın alamaz.' : 'Kayıt kapanır; hesap etkilenmez.', danger: action == 'restrict');
    if (note == null || !mounted) return;
    setState(() => _busy = true);
    final r = await shAdminCall(context, 'adminFraudDecide', {'uid': widget.queue['uid'], 'action': action, 'days': int.tryParse(_days.text.trim()) ?? 30, 'note': note}, 'Kaydedildi.');
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.queue;
    final ref = '${q['ref'] ?? ''}';
    final listingId = RegExp(r'ilan (\S+)').firstMatch('${q['summary'] ?? ''}')?.group(1);
    return CrewPage(
      title: 'Dolandırıcılık sinyali',
      subtitle: '${q['summary'] ?? ref}',
      maxWidth: CrewWidth.form,
      children: [
        CrewCard(
          title: 'Nedenler',
          icon: Icons.policy_outlined,
          children: [for (final r in (q['reasons'] as List? ?? const [])) CrewNote('$r', icon: Icons.warning_amber_rounded, color: HadiColors.error)],
        ),
        if (listingId != null)
          CrewCard(
            title: 'İlgili ilan',
            action: TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ShListingReviewPage(id: listingId))),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('İlanı aç'),
            ),
            children: [CrewInfoRow('İlan', listingId)],
          ),
        CrewCard(
          title: 'Karar',
          children: [
            CrewFormGrid(children: [TextField(controller: _days, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Kısıtlama süresi', suffixText: 'gün'))]),
            Wrap(spacing: CrewSpace.sm, runSpacing: CrewSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton(onPressed: _busy ? null : () => _act('clear'), child: const Text('Sorun yok, temizle')),
              FilledButton(onPressed: _busy ? null : () => _act('restrict'), child: const Text('Hesabı kısıtla')),
              PopupMenuButton<String>(tooltip: 'Diğer', enabled: !_busy, onSelected: _act, itemBuilder: (_) => const [PopupMenuItem(value: 'unrestrict', child: Text('Kısıtlamayı kaldır'))]),
            ]),
          ],
        ),
      ],
    );
  }
}

/// Şikâyet: gerekçeyle kapat / ilanı kaldır / hesabı 30 gün kısıtla.
class ShReportPage extends StatelessWidget {
  const ShReportPage({super.key, required this.queue});
  final Map<String, dynamic> queue;

  Future<void> _act(BuildContext context, String action, String label) async {
    final note = await askReason(context, title: label, danger: action != 'dismiss');
    if (note == null || !context.mounted) return;
    final r = await shAdminCall(context, 'adminReportDecide', {'queueId': queue['id'], 'action': action, 'note': note}, 'Kaydedildi.');
    if (r != null && context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ref = '${queue['ref'] ?? ''}';
    final listingId = ref.startsWith('listing:') ? ref.substring(8) : null;
    return CrewPage(
      title: 'Şikâyet',
      subtitle: '${queue['summary'] ?? ''}',
      maxWidth: CrewWidth.form,
      children: [
        CrewCard(title: 'Şikâyet', children: [for (final r in (queue['reasons'] as List? ?? const [])) CrewNote('$r', icon: Icons.flag_outlined)]),
        if (listingId != null)
          CrewCard(
            title: 'İlan',
            action: TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ShListingReviewPage(id: listingId))),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('İlanı aç'),
            ),
            children: [CrewInfoRow('İlan', listingId)],
          ),
        CrewCard(title: 'Karar', children: [
          Wrap(spacing: CrewSpace.sm, runSpacing: CrewSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
            OutlinedButton(onPressed: () => _act(context, 'dismiss', 'Şikâyeti kapat'), child: const Text('Sorun yok, kapat')),
            if (listingId != null) FilledButton(onPressed: () => _act(context, 'remove', 'İlanı kaldır'), child: const Text('İlanı kaldır')),
            PopupMenuButton<String>(
              tooltip: 'Diğer',
              onSelected: (_) => _act(context, 'restrict', 'Hesabı 30 gün kısıtla'),
              itemBuilder: (_) => const [PopupMenuItem(value: 'restrict', child: Text('Hesabı 30 gün kısıtla'))],
            ),
          ]),
        ]),
      ],
    );
  }
}
