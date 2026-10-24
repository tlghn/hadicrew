// HADİ Crew — Bildirim Stüdyosu ana ekranı (24 Ekim 2026). Sekmeler: Kampanyalar · Onay bekleyenler · Kayıtlı kitleler · Denetim
// kaydı. "Yeni bildirim" düzenleyiciyi açar (ns_composer.dart). Kampanya → rapor (huni, düğmeler, A/B, dönüşüm, atlananlar) ve
// eylemler (onayla/reddet, duraklat, sürdür, iptal, geri çek, kopyala). Yetki: notify.send / notify.approve / kurucu.
// Arayüz: package:hadi/panel_ui/crew_ui.dart (Crew/Kurucu paneli ortak bileşenleri; tema CrewThemeScope'tan).
import 'package:flutter/material.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/data/ops_api.dart';
import 'package:hadi/panel_ui/crew_ui.dart';
import 'package:hadi/theme/hadi_colors.dart';

import 'ns_api.dart';
import 'ns_composer.dart';

bool canNotifySend(Session s) => s.isFounder || s.isAdmin || s.can('notify.send') || s.can('notify.approve');
bool canNotifyApprove(Session s) => s.isFounder || s.can('notify.approve');

String _errText(Object e) => '$e'.replaceFirst('AppFailure: ', '');

class NotifyStudioScreen extends StatefulWidget {
  const NotifyStudioScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<NotifyStudioScreen> createState() => _NotifyStudioScreenState();
}

class _NotifyStudioScreenState extends State<NotifyStudioScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this, initialIndex: widget.initialTab);
  Map<String, dynamic>? _boot;
  String? _err;
  int _rev = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final b = await NsApi.bootstrap(SessionScope.read(context).services);
      if (mounted) setState(() => (_boot = b, _err = null));
    } catch (e) {
      if (mounted) setState(() => _err = _errText(e));
    }
  }

  Map<String, dynamic> get _cfg => OpsApi.map(_boot?['config']);

  Future<void> _compose([NsDraft? d]) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NsComposerPage(initial: d, config: _cfg)));
    if (!mounted) return;
    setState(() => _rev++);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_err != null) return CrewPage(title: 'Bildirim stüdyosu', body: CrewError(message: _err!, onRetry: _load));
    if (_boot == null) return const CrewPage(title: 'Bildirim stüdyosu', body: CrewLoading());
    final pending = (_boot?['pending'] as num?)?.toInt() ?? 0;
    final me = OpsApi.map(_boot?['me']);
    final aud = OpsApi.map(_boot?['audience']);
    final built = OpsApi.time(aud['builtAt']);
    return CrewPage(
      title: 'Bildirim stüdyosu',
      subtitle: 'Uygulama içi bildirim ve kart · ${aud['total'] ?? '-'} üye${built == null ? '' : ' · kitle verisi ${OpsApi.dur(DateTime.now().difference(built))} önce'}',
      actions: [
        FilledButton.icon(onPressed: me['send'] == true ? () => _compose() : null, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Yeni bildirim')),
      ],
      bottom: TabBar(controller: _tabs, isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
        const Tab(text: 'Kampanyalar'),
        Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Text('Onay bekleyenler'), if (pending > 0) ...[const SizedBox(width: CrewSpace.sm - 2), Badge(label: Text('$pending'))]])),
        const Tab(text: 'Kayıtlı kitleler'),
        const Tab(text: 'Denetim kaydı'),
      ]),
      body: TabBarView(controller: _tabs, children: [
        _CampaignList(key: ValueKey('all$_rev'), status: 'all', onEdit: _compose, onChanged: _load, config: _cfg),
        _CampaignList(key: ValueKey('p$_rev'), status: 'pending', onEdit: _compose, onChanged: _load, approver: me['approve'] == true, config: _cfg),
        _Audiences(key: ValueKey('a$_rev')),
        const _AuditLog(),
      ]),
    );
  }
}

// ================================================================== kampanya listesi

class _CampaignList extends StatefulWidget {
  const _CampaignList({super.key, required this.status, required this.onEdit, required this.onChanged, required this.config, this.approver = false});
  final String status;
  final Future<void> Function(NsDraft d) onEdit;
  final VoidCallback onChanged;
  final Map<String, dynamic> config;
  final bool approver;

  @override
  State<_CampaignList> createState() => _CampaignListState();
}

class _CampaignListState extends State<_CampaignList> {
  Future<List<NsItem>>? _f;
  String _filter = 'all';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= _fetch();
  }

  Future<List<NsItem>> _fetch() => NsApi.list(SessionScope.read(context).services, widget.status == 'pending' ? 'pending' : _filter);
  Future<void> _reload() async => setState(() => _f = _fetch());

  Future<void> _open(NsItem x) async {
    final s = SessionScope.read(context).services;
    if (x.status == 'draft' || x.status == 'rejected') {
      final m = await NsApi.get(s, x.id);
      await widget.onEdit(NsDraft.from(m));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NsReportScreen(cid: x.id, approver: widget.approver, onCopy: widget.onEdit)));
    await _reload();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.status == 'pending';
    return FutureBuilder<List<NsItem>>(
      future: _f,
      builder: (context, snap) {
        final head = pending
            ? null
            : CrewFilterChips<String>(
                options: const [('all', 'Tümü'), ('active', 'Süren / planlı'), ('drafts', 'Taslaklar')],
                value: _filter,
                onChanged: (x) => setState(() => (_filter = x, _f = _fetch())),
              );
        Widget content;
        if (snap.hasError) {
          content = CrewError(message: _errText(snap.error!), onRetry: _reload);
        } else if (!snap.hasData) {
          content = const CrewLoading();
        } else if (snap.data!.isEmpty) {
          content = CrewEmpty(
            icon: pending ? Icons.task_alt_rounded : Icons.campaign_outlined,
            title: pending ? 'Onay bekleyen bildirim yok' : 'Henüz bildirim yok',
            message: pending ? 'Eşik üstü kitleye giden bildirimler burada ikinci onayı bekler.' : '"Yeni bildirim" ile kategori, kitle ve içeriği seçerek başla.',
          );
        } else {
          content = Column(spacing: CrewSpace.md, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final it in snap.data!) _CampaignTile(it: it, approver: widget.approver, onOpen: () => _open(it)),
          ]);
        }
        return CrewPage(
          title: '',
          embedded: true,
          onRefresh: _reload,
          toolbar: head == null ? null : CrewToolbar(filters: head),
          children: [
            if (pending) const CrewNote('Kendi hazırladığını onaylayamazsın (dört göz). Onay ve ret gerekçesiyle denetim kaydına yazılır.'),
            content,
          ],
        );
      },
    );
  }
}

Color _statusColor(String s) => switch (s) {
      'sent' => HadiColors.dostluk,
      'sending' || 'recurring' || 'scheduled' || 'approved' => HadiColors.aktivite,
      'pending_approval' || 'paused' => HadiColors.heyecan,
      'cancelled' || 'rejected' || 'failed' => HadiColors.error,
      _ => HadiColors.ink3,
    };

CrewPill _statusPill(String s, {bool retracted = false}) => CrewPill('${kNsStatus[s] ?? s}${retracted ? ' · geri çekildi' : ''}', color: _statusColor(s));

class _CampaignTile extends StatelessWidget {
  const _CampaignTile({required this.it, required this.onOpen, this.approver = false});
  final NsItem it;
  final VoidCallback onOpen;
  final bool approver;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final cat = kNsCategories[it.category];
    final sent = it.stat('sent'), opened = it.stat('opened');
    return Material(
      color: crewCardColor(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: cs.outlineVariant)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(CrewSpace.lg),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 72,
                height: 72,
                child: it.image != null
                    ? Image.network(it.image!, fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: crewCanvas(context)))
                    : ColoredBox(color: crewCanvas(context), child: Center(child: Text(cat?.emoji ?? '📣', style: const TextStyle(fontSize: 30)))),
              ),
            ),
            const SizedBox(width: CrewSpace.lg),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: CrewSpace.sm, runSpacing: CrewSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  _statusPill(it.status, retracted: it.retracted),
                  Text('${cat?.emoji ?? ''} ${cat?.label ?? it.category}', style: t.bodySmall),
                  if (it.ab) Text('A/B${it.abWinner != null ? ' · kazanan ${it.abWinner}' : ''}', style: t.bodySmall),
                  if (it.scheduleMode == 'recurring') Icon(Icons.repeat_rounded, size: 16, color: cs.onSurfaceVariant),
                ]),
                const SizedBox(height: CrewSpace.sm),
                Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
                const SizedBox(height: 2),
                Text(it.body.replaceAll('{ad}', 'Elif'), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: CrewSpace.sm),
                Text(
                  [
                    it.audienceText,
                    if (it.resolved != null) '${it.resolved} kişi',
                    if (it.nextAt != null) 'sıradaki ${_dt(it.nextAt!)}',
                    if (sent > 0 && !crewWide(context)) '%${(opened * 100 / sent).toStringAsFixed(1)} açıldı',
                    it.by,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall,
                ),
              ]),
            ),
            if (sent > 0 && crewWide(context)) ...[
              const SizedBox(width: CrewSpace.lg),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('%${(opened * 100 / sent).toStringAsFixed(1)}', style: t.titleLarge),
                Text('açılma', style: t.bodySmall),
                const SizedBox(height: CrewSpace.xs),
                Text('$sent gönderildi', style: t.bodySmall),
              ]),
            ],
            if (it.status == 'pending_approval' && approver) ...[
              const SizedBox(width: CrewSpace.md),
              const Icon(Icons.how_to_reg_rounded, color: HadiColors.heyecan),
            ],
          ]),
        ),
      ),
    );
  }
}

String _two(int n) => n.toString().padLeft(2, '0');
String _dt(DateTime x) => '${_two(x.day)}.${_two(x.month)} ${_two(x.hour)}:${_two(x.minute)}';

// ================================================================== rapor

class NsReportScreen extends StatefulWidget {
  const NsReportScreen({super.key, required this.cid, this.approver = false, this.onCopy});
  final String cid;
  final bool approver;
  final Future<void> Function(NsDraft d)? onCopy;

  @override
  State<NsReportScreen> createState() => _NsReportScreenState();
}

class _NsReportScreenState extends State<NsReportScreen> {
  Future<Map<String, dynamic>>? _f;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= NsApi.report(SessionScope.read(context).services, widget.cid);
  }

  Future<void> _act(String op, {bool reason = false, required String title, String? message, bool danger = false}) async {
    String? note;
    if (reason) {
      note = await crewAskReason(context, title: title, message: message, confirm: 'Onayla', danger: danger);
      if (note == null) return;
    } else if (!await crewConfirm(context, title: title, message: message, danger: danger)) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final s = SessionScope.read(context).services;
    try {
      await NsApi.act(s, op, widget.cid, note: note);
      if (mounted) {
        crewToast(context, 'Tamam.');
        setState(() => _f = NsApi.report(s, widget.cid));
      }
    } catch (e) {
      if (mounted) crewToast(context, _errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Widget> _actions(NsItem it, int sent) {
    final st = it.status;
    final primary = <Widget>[
      if (st == 'pending_approval' && widget.approver)
        FilledButton.icon(
          onPressed: _busy ? null : () => _act('approve', title: 'Onaylansın mı?', message: '${it.resolved ?? '-'} kişiye gidecek. Onayın denetim kaydına yazılır.'),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Onayla ve gönder'),
        ),
      if (const ['sending', 'recurring', 'scheduled'].contains(st))
        OutlinedButton.icon(onPressed: _busy ? null : () => _act('pause', title: 'Duraklatılsın mı?'), icon: const Icon(Icons.pause_rounded, size: 18), label: const Text('Duraklat')),
      if (st == 'paused') OutlinedButton.icon(onPressed: _busy ? null : () => _act('resume', title: 'Sürdürülsün mü?'), icon: const Icon(Icons.play_arrow_rounded, size: 18), label: const Text('Sürdür')),
    ];
    final more = <PopupMenuEntry<String>>[
      if (st == 'pending_approval' && widget.approver) const PopupMenuItem(value: 'reject', child: Text('Reddet')),
      if (const ['sending', 'recurring', 'scheduled', 'paused', 'pending_approval', 'approved'].contains(st)) const PopupMenuItem(value: 'cancel', child: Text('İptal et')),
      if (sent > 0 && !it.retracted) const PopupMenuItem(value: 'retract', child: Text('Geri çek (kart ve zil kaydı)')),
      if (widget.onCopy != null) const PopupMenuItem(value: 'copy', child: Text('Kopyasını oluştur')),
    ];
    return [
      ...primary,
      if (more.isNotEmpty)
        PopupMenuButton<String>(
          tooltip: 'Diğer işlemler',
          itemBuilder: (_) => more,
          onSelected: (x) async {
            switch (x) {
              case 'reject':
                await _act('reject', reason: true, title: 'Reddet', message: 'Hazırlayana gerekçeyle döner.', danger: true);
              case 'cancel':
                await _act('cancel', title: 'İptal edilsin mi?', message: 'Henüz gitmemiş bildirimler gönderilmez.', danger: true);
              case 'retract':
                await _act('retract', reason: true, title: 'Geri çekilsin mi?', message: 'Uygulamadaki kart ve zil listesindeki kayıt silinir. Telefona düşmüş bildirim geri alınamaz.', danger: true);
              case 'copy':
                final m = await NsApi.get(SessionScope.read(context).services, widget.cid);
                if (!mounted) return;
                Navigator.of(context).pop();
                await widget.onCopy!(NsDraft.from(m).copyAsNew());
            }
          },
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _f,
      builder: (context, snap) {
        if (snap.hasError) return CrewPage(title: 'Bildirim raporu', body: CrewError(message: _errText(snap.error!)));
        if (!snap.hasData) return const CrewPage(title: 'Bildirim raporu', body: CrewLoading());
        final t = Theme.of(context).textTheme;
        final r = snap.data!;
        final it = NsItem(OpsApi.map(r['campaign']));
        final fn = OpsApi.map(r['funnel']);
        final clicks = OpsApi.map(r['clicks']);
        final byV = OpsApi.map(r['byVariant']);
        final ab = OpsApi.map(r['ab']);
        final skip = OpsApi.map(r['skip']);
        final conv = OpsApi.map(r['conversion']);
        int n(Object? x) => (x as num?)?.toInt() ?? 0;
        final sent = n(fn['sent']);
        final total = n(fn['targeted']);
        final cat = kNsCategories[it.category];
        return CrewPage(
          title: 'Bildirim raporu',
          subtitle: it.name.isEmpty ? it.title : it.name,
          actions: _actions(it, sent),
          onRefresh: () async => setState(() => _f = NsApi.report(SessionScope.read(context).services, widget.cid)),
          children: [
            CrewCard(children: [
              Wrap(spacing: CrewSpace.sm, runSpacing: CrewSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _statusPill(it.status, retracted: it.retracted),
                Text('${cat?.emoji ?? ''} ${cat?.label ?? ''}', style: t.bodyMedium),
              ]),
              Text(it.title, style: t.titleLarge),
              Text(it.body.replaceAll('{ad}', 'Elif'), style: t.bodyLarge),
              CrewInfoRow('Kitle', it.audienceText),
              CrewInfoRow('Hazırlayan', it.by),
              if (it.nextAt != null) CrewInfoRow('Sıradaki gönderim', _dt(it.nextAt!)),
            ]),
            Wrap(spacing: CrewSpace.lg, runSpacing: CrewSpace.lg, children: [
              _Kpi('Gönderildi', '$sent', sub: 'hedef $total'),
              _Kpi('Açılma oranı', sent > 0 ? '%${(n(fn['opened']) * 100 / sent).toStringAsFixed(1)}' : '—', sub: '${n(fn['opened'])} kişi dokundu'),
              for (final (i, l) in (clicks['labels'] as List? ?? const []).indexed) _Kpi('"$l"', '${n(clicks['b$i'])}', sub: 'düğme dokunuşu'),
              if (conv.isNotEmpty)
                _Kpi(conv['kind'] == 'event' ? 'Etkinliğe katıldı' : 'Satın aldı', '${n(conv['n'])}', sub: '${r['conversionHours']} saat içinde · açanlardan ${n(conv['sampled'])} kişiye bakıldı'),
            ]),
            CrewCard(title: 'Huni', icon: Icons.filter_alt_outlined, children: [
              _Bar('Hedeflenen', total, total, HadiColors.ink3),
              _Bar('Gönderildi (zil listesi)', sent, total, HadiColors.aktivite),
              _Bar('Telefona / tarayıcıya ulaştı', n(fn['pushed']), total, HadiColors.iletisim),
              _Bar('Açıldı', n(fn['opened']), total, HadiColors.dostluk),
              if (n(fn['queued']) + n(fn['held']) > 0) _Bar('Kuyrukta (sessiz saat, sıklık, A/B)', n(fn['queued']) + n(fn['held']), total, HadiColors.heyecan),
              _Bar('Gönderilmedi', n(fn['skipped']), total, HadiColors.error),
              if (skip.isNotEmpty) CrewNote('Gönderilmeme nedenleri: ${skip.entries.map((e) => '${kNsSkip[e.key] ?? e.key} ${e.value}').join(' · ')}'),
              const CrewNote('"Ulaştı" FCM\'nin kabul ettiği gönderimdir; cihaza fiilen düşmeyi Firebase Konsolu › Messaging teslim raporu gösterir.'),
            ]),
            if (byV.length > 1)
              CrewCard(title: 'A/B karşılaştırması', icon: Icons.compare_arrows_rounded, subtitle: ab['winner'] == null ? 'Kazanan örneklem süresi dolunca açılma oranına göre seçilir.' : null, children: [
                CrewFormGrid(children: [
                  for (final k in const ['A', 'B'])
                    CrewItemCard(
                      title: 'Varyant $k',
                      trailing: ab['winner'] == k ? const CrewPill('Kazanan', color: HadiColors.dostluk, icon: Icons.emoji_events_outlined) : null,
                      child: Column(spacing: CrewSpace.xs, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        CrewInfoRow('Gönderildi', '${n(OpsApi.map(byV[k])['sent'])}', labelWidth: 110),
                        CrewInfoRow('Açıldı', '${n(OpsApi.map(byV[k])['opened'])} (%${n(OpsApi.map(byV[k])['sent']) > 0 ? (n(OpsApi.map(byV[k])['opened']) * 100 / n(OpsApi.map(byV[k])['sent'])).toStringAsFixed(1) : '0'})', labelWidth: 110),
                        CrewInfoRow('Dokunuş', '${n(OpsApi.map(byV[k])['clicks'])}', labelWidth: 110),
                        if (conv.isNotEmpty) CrewInfoRow('Dönüşüm', '${n(OpsApi.map(conv['byVariant'])[k])}', labelWidth: 110),
                      ]),
                    ),
                ]),
                if (ab['confident'] == false) const CrewNote('Örneklem küçük: fark rastlantı olabilir.', color: HadiColors.heyecan),
              ]),
          ],
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar(this.label, this.value, this.max, this.color);
  final String label;
  final int value, max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(children: [
      Expanded(flex: 2, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium)),
      const SizedBox(width: CrewSpace.md),
      Expanded(
        flex: 3,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: max <= 0 ? 0 : (value / max).clamp(0, 1).toDouble(), minHeight: 12, color: color, backgroundColor: crewCanvas(context)),
        ),
      ),
      SizedBox(width: 72, child: Text('$value', textAlign: TextAlign.right, style: t.titleSmall)),
    ]);
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, {this.sub});
  final String label, value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 270),
      child: CrewCard(children: [
        Text(value, style: t.headlineMedium),
        Text(label, style: t.titleSmall),
        if (sub != null) Text(sub!, style: t.bodySmall),
      ]),
    );
  }
}

// ================================================================== kayıtlı kitleler

class _Audiences extends StatefulWidget {
  const _Audiences({super.key});

  @override
  State<_Audiences> createState() => _AudiencesState();
}

class _AudiencesState extends State<_Audiences> {
  Future<List<Map<String, dynamic>>>? _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= NsApi.audiences(SessionScope.read(context).services);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: _f,
        builder: (context, snap) {
          final s = SessionScope.read(context).services;
          return CrewPage(
            title: '',
            embedded: true,
            onRefresh: () async => setState(() => _f = NsApi.audiences(s)),
            children: [
              if (!snap.hasData)
                const CrewLoading()
              else
                CrewListCard(
                  title: 'Kayıtlı kitleler',
                  subtitle: 'Sık kullanılan süzgeç ve listeler; her gönderimde yeniden hesaplanır.',
                  empty: const CrewEmpty(icon: Icons.bookmark_border_rounded, title: 'Kayıtlı kitle yok', message: 'Bildirim hazırlarken süzgeçle bir kitle kurup "Kitleyi kaydet"e bas.'),
                  children: [
                    for (final a in snap.data!)
                      ListTile(
                        leading: const Icon(Icons.bookmark_rounded),
                        title: Text('${a['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${a['text'] ?? ''} · ~${a['count'] ?? '-'} kişi · ${a['by'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          tooltip: 'Sil',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () async {
                            if (!await crewConfirm(context, title: '"${a['name']}" silinsin mi?', danger: true)) return;
                            await NsApi.deleteAudience(s, '${a['id']}');
                            setState(() => _f = NsApi.audiences(s));
                          },
                        ),
                      ),
                  ],
                ),
            ],
          );
        },
      );
}

// ================================================================== denetim kaydı

class _AuditLog extends StatefulWidget {
  const _AuditLog();

  @override
  State<_AuditLog> createState() => _AuditLogState();
}

class _AuditLogState extends State<_AuditLog> {
  Future<Map<String, dynamic>>? _f;
  static const _labels = {
    'send': 'gönderdi', 'submit': 'onaya gönderdi', 'approve': 'onayladı', 'reject': 'reddetti', 'cancel': 'iptal etti', 'pause': 'duraklattı', 'resume': 'sürdürdü',
    'retract': 'geri çekti', 'test': 'test gönderdi', 'config': 'ayarları değiştirdi', 'rebuild': 'kitle verisini yeniledi', 'audience.save': 'kitle kaydetti',
    'audience.delete': 'kitle sildi', 'moderation.reject': 'denetimden geçemedi',
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= NsApi.audit(SessionScope.read(context).services);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: _f,
        builder: (context, snap) {
          final l = snap.hasData ? OpsApi.list(snap.data!['items']) : const <Map<String, dynamic>>[];
          return CrewPage(
            title: '',
            embedded: true,
            onRefresh: () async => setState(() => _f = NsApi.audit(SessionScope.read(context).services)),
            children: [
              if (!snap.hasData)
                const CrewLoading()
              else
                CrewListCard(
                  title: 'Denetim kaydı',
                  subtitle: 'Kim, ne zaman, hangi kitleye, hangi içerikle — her işlem.',
                  empty: const CrewEmpty(title: 'Kayıt yok'),
                  children: [
                    for (final x in l)
                      ListTile(
                        leading: Text(kNsCategories['${x['category']}']?.emoji ?? '🗂️', style: const TextStyle(fontSize: 22)),
                        title: Text('${x['actorName'] ?? ''} ${_labels['${x['action']}'] ?? x['action']}${x['title'] != null ? ': "${x['title']}"' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          [
                            if (x['audienceText'] != null) '${x['audienceText']}',
                            if (x['resolvedCount'] != null) '${x['resolvedCount']} kişi',
                            if (x['reason'] != null && '${x['reason']}'.isNotEmpty) 'gerekçe: ${x['reason']}',
                            if (OpsApi.time(x['at']) != null) _dt(OpsApi.time(x['at'])!),
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
            ],
          );
        },
      );
}
