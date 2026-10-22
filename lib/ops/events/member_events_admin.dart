// HADİ Crew
// Kaynak: hadimobile/lib/features/events/member_events.dart (21 Ekim 2026'da HADİ Crew'e taşındı).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hadi/core/format.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/data/event_models.dart';
import 'package:hadi/data/models.dart';
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/instant.dart';
import 'package:hadi/widgets/toast.dart';

Color _statusColor(EventProposal p) => switch (p.status) {
      'approved' || 'accepted' || 'done' => HadiColors.dostluk,
      'rejected' || 'declined' => HadiColors.error,
      'withdrawn' => HadiColors.ink3,
      _ => HadiColors.heyecan,
    };

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({required this.p, this.onOpenEvent, this.onWithdraw, this.actions});
  final EventProposal p;
  final VoidCallback? onOpenEvent, onWithdraw;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = _statusColor(p);
    final reason = p.isDraft ? p.rejectReason : p.note;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: HadiColors.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: HadiColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: HadiColors.wash(p.isDraft ? HadiColors.gold : HadiColors.aktivite), borderRadius: BorderRadius.circular(99)),
            child: Text(p.isDraft ? '👑 Etkinlik' : '💡 Öneri',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: HadiColors.readableOn(p.isDraft ? const Color(0xFF6E5414) : HadiColors.aktivite, HadiColors.wash(p.isDraft ? HadiColors.gold : HadiColors.aktivite)))),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: HadiColors.wash(c), borderRadius: BorderRadius.circular(99)),
            child: Text(p.statusLabel, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: HadiColors.readableOn(c, HadiColors.wash(c)))),
          ),
        ]),
        const SizedBox(height: 8),
        Text(p.title, style: text.titleMedium),
        if (p.isDraft && p.startAt != null) ...[
          const SizedBox(height: 2),
          Text([dateTimeLong(p.startAt!), if (p.city.isNotEmpty) p.city, if (p.capacity > 0) '${p.capacity} kişi'].join(' · '),
              style: text.bodySmall?.copyWith(color: HadiColors.ink3)),
        ],
        if (p.name.isNotEmpty && actions != null) ...[
          const SizedBox(height: 2),
          Text([if (p.username != null) '@${p.username}' else p.name, if (p.candidate) 'Üye adayı', if (p.volunteer) 'Ev sahibi olmaya gönüllü'].join(' · '),
              style: text.bodySmall?.copyWith(color: HadiColors.ink2, fontWeight: FontWeight.w700)),
        ],
        if (p.description.isNotEmpty && actions != null) ...[
          const SizedBox(height: 6),
          Text(p.description, maxLines: 6, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
        ],
        if (reason != null && reason.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: HadiColors.mist, borderRadius: BorderRadius.circular(12)),
            child: Text(p.isDraft ? 'Gerekçe: $reason' : 'Not: $reason', style: text.bodySmall?.copyWith(color: HadiColors.ink2)),
          ),
        ],
        if (p.createdAt != null) ...[
          const SizedBox(height: 6),
          Text('Gönderildi: ${dateTimeLong(p.createdAt!)}', style: text.bodySmall?.copyWith(color: HadiColors.ink3, fontSize: 11.5)),
        ],
        if (onOpenEvent != null || onWithdraw != null || (actions?.isNotEmpty ?? false)) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            if (onOpenEvent != null) FilledButton.tonal(onPressed: onOpenEvent, child: const Text('Etkinliği aç')),
            if (onWithdraw != null) OutlinedButton(onPressed: onWithdraw, child: const Text('Geri çek')),
            ...?actions,
          ]),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Yönetim: üye etkinlikleri onayı + öneriler
// ---------------------------------------------------------------------------

class MemberEventsAdminScreen extends StatefulWidget {
  const MemberEventsAdminScreen({super.key});

  @override
  State<MemberEventsAdminScreen> createState() => _MemberEventsAdminScreenState();
}

class _MemberEventsAdminScreenState extends State<MemberEventsAdminScreen> {
  MemberEventsAdminData? _d;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final d = await SessionScope.read(context).services.events.memberEventsAdmin();
      if (mounted) {
        setState(() {
          _d = d;
          _error = null;
        });
      }
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Liste yüklenemedi.');
    }
  }

  Future<void> _run(String id, Future<void> Function() f, String done) async {
    setState(() => _busy.add(id));
    try {
      await f();
      HapticFeedback.mediumImpact();
      if (mounted) showToast(context, done);
      await _load();
    } on AppFailure catch (e) {
      if (mounted) showToast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _approve(EventProposal p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Yayımlansın mı?'),
        content: Text('"${p.title}" gerçek etkinlik olarak yayımlanır ve "Üye etkinliği · ${p.username != null ? '@${p.username}' : p.name}" etiketi taşır. Üyeye bildirim gider.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Onayla ve yayımla')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(p.id, () => SessionScope.read(context).services.events.approveDraft(p.id), 'Etkinlik yayımlandı.');
  }

  Future<String?> _askText(String title, String hint, {bool required = true}) async {
    final ctrl = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true, minLines: 2, maxLines: 5, maxLength: 400, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () {
              if (required && ctrl.text.trim().length < 3) return;
              Navigator.pop(c, ctrl.text.trim());
            },
            child: const Text('Gönder'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return r;
  }

  Future<void> _reject(EventProposal p) async {
    final reason = await _askText('Ret gerekçesi', 'Üyeye iletilir. Örn: Tarih resmî tatille çakışıyor.');
    if (reason == null || !mounted) return;
    await _run(p.id, () => SessionScope.read(context).services.events.rejectDraft(p.id, reason), 'Üyeye bildirildi.');
  }

  Future<void> _suggestion(EventProposal p, String status) async {
    final note = status == 'declined' || status == 'accepted' ? await _askText('Üyeye not (isteğe bağlı)', 'Kısa bir not', required: false) : '';
    if (note == null || !mounted) return;
    await _run(p.id, () => SessionScope.read(context).services.events.setSuggestionStatus(p.id, status, note: note), 'Öneri güncellendi.');
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Üye etkinlikleri'),
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.center, tabs: [
            Tab(text: 'Onay bekleyen${d == null || d.pending.isEmpty ? '' : ' (${d.pending.length})'}'),
            const Tab(text: 'Öneriler'),
            const Tab(text: 'Kararlar'),
          ]),
        ),
        body: _error != null
            ? Center(child: Text(_error!, style: TextStyle(color: HadiColors.text(HadiColors.error))))
            : d == null
                ? const ListSkeleton(count: 6)
                : TabBarView(children: [
                    _list(d.pending, 'Onay bekleyen üye etkinliği yok.', (p) => [
                          FilledButton(onPressed: _busy.contains(p.id) ? null : () => _approve(p), child: const Text('Onayla')),
                          OutlinedButton(
                            onPressed: _busy.contains(p.id) ? null : () => _reject(p),
                            style: OutlinedButton.styleFrom(foregroundColor: HadiColors.text(HadiColors.error)),
                            child: const Text('Reddet'),
                          ),
                        ]),
                    _list(d.suggestions, 'Henüz öneri yok.', (p) => [
                          PopupMenuButton<String>(
                            enabled: !_busy.contains(p.id),
                            onSelected: (v) => _suggestion(p, v),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'reviewing', child: Text('İnceleniyor')),
                              PopupMenuItem(value: 'accepted', child: Text('Kabul edildi')),
                              PopupMenuItem(value: 'done', child: Text('Etkinlik oldu')),
                              PopupMenuItem(value: 'declined', child: Text('Şimdilik değil')),
                            ],
                            child: const Chip(avatar: Icon(Icons.edit_rounded, size: 16), label: Text('Durumu değiştir')),
                          ),
                        ]),
                    _list(d.recent, 'Henüz karar yok.', (p) => [
                          if (p.eventId != null) FilledButton.tonal(onPressed: () => context.push('/etkinlik/${p.eventId!}?kaynak=uye'), child: const Text('Etkinliği aç')),
                        ]),
                  ]),
      ),
    );
  }

  Widget _list(List<EventProposal> items, String empty, List<Widget> Function(EventProposal) actions) => RefreshIndicator(
        onRefresh: _load,
        child: items.isEmpty
            ? ListView(children: [Padding(padding: const EdgeInsets.only(top: 80), child: Center(child: Text(empty, style: TextStyle(color: HadiColors.ink3))))])
            : ListView.separated(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + MediaQuery.paddingOf(context).bottom),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _ProposalCard(p: items[i], actions: actions(items[i])),
              ),
      );
}
