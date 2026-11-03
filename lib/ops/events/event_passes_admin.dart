// HADİ — Geçiş biletleri (3 Kasım 2026; sunucu: hadimobile/functions/src/event_passes.ts, veri: hadi › data/event_pass_service.dart).
//
//   Kurucu Paneli › Geçiş biletleri ([canGrant] true): üye + etkinlik seç → tek kullanımlık bilet ver; kullanılmamış bileti geri al.
//   Crew › Geçiş biletleri: verilen ve KULLANILAN biletleri takip (kim, hangi etkinlik, ne zaman verildi / kullanıldı / ayrıldı).
//   Bilet, üye Katıl'a dokunup onayladığı an kullanılır; ayrılırsa iade yok ve aynı etkinlik için yeniden verilemez.
import 'package:flutter/material.dart';

import 'package:hadi/core/format.dart';
import 'package:hadi/data/event_admin_service.dart';
import 'package:hadi/data/event_pass_service.dart';
import 'package:hadi/data/member_models.dart';
import 'package:hadi/data/models.dart' show AppFailure;
import 'package:hadi/panel_ui/crew_ui.dart';
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/hadi_sheet.dart';

import '../admin/roles_admin.dart' show pickMemberForRole;

class EventPassesAdminScreen extends StatefulWidget {
  const EventPassesAdminScreen({super.key, this.canGrant = false, this.embedded = false, this.api, this.eventsApi});

  /// Bilet verme / geri alma (yalnızca ana kurucu; sunucu da denetler).
  final bool canGrant;
  final bool embedded;

  /// Test için.
  final EventPassApi? api;
  final EventAdminApi? eventsApi;

  @override
  State<EventPassesAdminScreen> createState() => _EventPassesAdminScreenState();
}

class _EventPassesAdminScreenState extends State<EventPassesAdminScreen> {
  EventPassApi get _api => widget.api ?? EventPassApi.instance;
  late String _status = widget.canGrant ? '' : 'used';
  List<EventPass>? _items;
  String? _err;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final g = ++_gen;
    setState(() {
      _items = null;
      _err = null;
    });
    try {
      final p = await _api.list(status: _status, limit: 200);
      if (mounted && g == _gen) setState(() => _items = p.items);
    } on AppFailure catch (e) {
      if (mounted && g == _gen) setState(() => _err = e.message);
    }
  }

  Future<void> _revoke(EventPass p) async {
    final ok = await crewConfirm(context,
        title: 'Bileti geri al', message: '${p.name} için "${p.eventTitle}" bileti geri alınsın mı? Üye artık ücretsiz katılamaz.', confirm: 'Geri al', danger: true);
    if (!ok || !mounted) return;
    try {
      await _api.revoke(uid: p.uid, eventId: p.eventId);
      if (mounted) crewToast(context, 'Bilet geri alındı.');
      _load();
    } on AppFailure catch (e) {
      if (mounted) crewToast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return CrewPage(
      title: 'Geçiş biletleri',
      subtitle: widget.canGrant ? 'Üyeye etkinlik için tek kullanımlık ücretsiz bilet ver, kullanılanları izle' : 'Kurucunun verdiği biletler: kim, hangi etkinlik, ne zaman kullandı',
      embedded: widget.embedded,
      maxWidth: 920,
      gap: CrewSpace.md,
      onRefresh: _load,
      toolbar: CrewFilterChips<String>(
        options: const [('used', 'Kullanılan'), ('active', 'Kullanılmayan'), ('revoked', 'Geri alınan'), ('', 'Tümü')],
        value: _status,
        onChanged: (v) {
          _status = v;
          _load();
        },
      ),
      children: [
        if (widget.canGrant) _GrantCard(api: _api, eventsApi: widget.eventsApi ?? EventAdminApi.instance, onGranted: _load),
        if (_err != null) CrewCard(child: CrewError(message: _err!, onRetry: _load)),
        if (items == null && _err == null) const CrewCard(child: CrewLoading()),
        if (items != null && items.isEmpty)
          const CrewCard(child: CrewEmpty(icon: Icons.confirmation_number_outlined, title: 'Bu süzgeçte bilet yok')),
        if (items != null && items.isNotEmpty)
          CrewCard(
            title: '${items.length} bilet',
            padding: const EdgeInsets.symmetric(horizontal: CrewSpace.lg, vertical: CrewSpace.md),
            children: [for (final p in items) _PassRow(pass: p, onRevoke: widget.canGrant && p.isActive ? () => _revoke(p) : null)],
          ),
      ],
    );
  }
}

class _PassRow extends StatelessWidget {
  const _PassRow({required this.pass, this.onRevoke});
  final EventPass pass;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final p = pass;
    final t = Theme.of(context).textTheme;
    final tone = switch (p.status) {
      EventPassStatus.used => HadiColors.dostluk,
      EventPassStatus.active => HadiColors.heyecan,
      EventPassStatus.revoked => HadiColors.ink3,
    };
    String at(DateTime? d) => d == null ? '—' : dateTimeLong(d);
    return Padding(
      key: ValueKey('bilet-${p.id}'),
      padding: const EdgeInsets.symmetric(vertical: CrewSpace.sm),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(radius: 20, backgroundImage: p.photoUrl == null ? null : NetworkImage(p.photoUrl!), child: p.photoUrl == null ? const Icon(Icons.person_rounded) : null),
        const SizedBox(width: CrewSpace.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(p.name.isEmpty ? p.uid : p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
              const SizedBox(width: CrewSpace.sm),
              CrewPill(p.statusLabel, color: tone),
            ]),
            const SizedBox(height: 2),
            Text('🎟️ ${p.eventTitle}${p.eventStartAt == null ? '' : ' · ${dateTimeLong(p.eventStartAt!)}'}', style: t.bodyMedium),
            const SizedBox(height: 2),
            Text(
              [
                'Verildi ${at(p.grantedAt)}${p.grantedByName.isEmpty ? '' : ' (${p.grantedByName})'}',
                if (p.usedAt != null) 'Kullanıldı ${at(p.usedAt)}',
                if (p.leftAt != null) 'Ayrıldı ${at(p.leftAt)} · iade yok',
                if (p.revokedAt != null) 'Geri alındı ${at(p.revokedAt)}',
              ].join(' · '),
              style: t.bodySmall?.copyWith(color: HadiColors.ink2),
            ),
            if (p.note.isNotEmpty) Text('Not: ${p.note}', style: t.bodySmall?.copyWith(color: HadiColors.ink3)),
          ]),
        ),
        if (onRevoke != null) TextButton(onPressed: onRevoke, child: const Text('Geri al')),
      ]),
    );
  }
}

/// Bilet ver: üye seç (yönetim araması) + yaklaşan etkinlik seç + not → ver.
class _GrantCard extends StatefulWidget {
  const _GrantCard({required this.api, required this.eventsApi, required this.onGranted});
  final EventPassApi api;
  final EventAdminApi eventsApi;
  final VoidCallback onGranted;

  @override
  State<_GrantCard> createState() => _GrantCardState();
}

class _GrantCardState extends State<_GrantCard> {
  MemberProfile? _member;
  AdminEventItem? _event;
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickMember() async {
    final m = await pickMemberForRole(context, title: 'Bilet verilecek üye');
    if (m != null && mounted) setState(() => _member = m);
  }

  Future<void> _pickEvent() async {
    final e = await showHadiSheet<AdminEventItem>(context: context, showDragHandle: true, isScrollControlled: true, builder: (_) => _EventPicker(api: widget.eventsApi));
    if (e != null && mounted) setState(() => _event = e);
  }

  Future<void> _grant() async {
    final m = _member, e = _event;
    if (m == null || e == null) return;
    final ok = await crewConfirm(context,
        title: 'Geçiş bileti ver',
        message: '${m.fullName} "${e.title}" etkinliğine ücretsiz katılabilecek. Bilet tek kullanımlıktır: üye katıldığı an kullanılır, çıkarsa iadesi yapılmaz. Üyeye bildirim gider.',
        confirm: 'Bileti ver');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.grant(uid: m.uid, eventId: e.id, note: _note.text);
      if (!mounted) return;
      crewToast(context, '${m.fullName} için bilet verildi.');
      setState(() {
        _member = null;
        _note.clear();
      });
      widget.onGranted();
    } on AppFailure catch (err) {
      if (mounted) crewToast(context, err.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _member, e = _event;
    return CrewCard(
      title: 'Bilet ver',
      subtitle: 'Üye etkinlikte Katıl\'a dokununca "biletin var, ücretsiz katılacaksın" görür; katıldığı an bilet kullanılır.',
      icon: Icons.confirmation_number_rounded,
      children: [
        ListTile(
          key: const ValueKey('bilet-uye'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_search_rounded),
          title: Text(m == null ? 'Üye seç' : m.fullName),
          subtitle: m == null ? const Text('Ad, rumuz ya da @kullanıcı adı ile ara') : null,
          trailing: TextButton(onPressed: _busy ? null : _pickMember, child: Text(m == null ? 'Seç' : 'Değiştir')),
        ),
        ListTile(
          key: const ValueKey('bilet-etkinlik'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_rounded),
          title: Text(e == null ? 'Etkinlik seç' : e.title),
          subtitle: Text(e == null
              ? 'Yaklaşan etkinlikler arasından'
              : [if (e.startAt != null) dateTimeLong(e.startAt!), '${e.attendeeCount}/${e.capacity} kişi', if (e.priceHp > 0) 'bilet ${e.priceHp} 💎'].join(' · ')),
          trailing: TextButton(onPressed: _busy ? null : _pickEvent, child: Text(e == null ? 'Seç' : 'Değiştir')),
        ),
        TextField(controller: _note, maxLength: 200, decoration: const InputDecoration(labelText: 'Not (isteğe bağlı, yalnızca yönetim görür)')),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const ValueKey('bilet-ver'),
            onPressed: _busy || m == null || e == null ? null : _grant,
            icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded),
            label: const Text('Bileti ver'),
          ),
        ),
      ],
    );
  }
}

class _EventPicker extends StatefulWidget {
  const _EventPicker({required this.api});
  final EventAdminApi api;

  @override
  State<_EventPicker> createState() => _EventPickerState();
}

class _EventPickerState extends State<_EventPicker> {
  List<AdminEventItem>? _items;
  String? _err;
  String _q = '';
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final g = ++_gen;
    try {
      final p = await widget.api.list(AdminEventQuery(q: _q), limit: 40);
      if (mounted && g == _gen) {
        setState(() {
          _items = [for (final e in p.items) if (e.status == 'published' && (e.startAt?.isAfter(DateTime.now()) ?? false)) e];
          _err = null;
        });
      }
    } on AppFailure catch (e) {
      if (mounted && g == _gen) setState(() => _err = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return SizedBox(
      height: MediaQuery.of(context).size.height * .75,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Etkinlik seç', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          TextField(
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Başlık, mekân ya da organizatör'),
            onChanged: (v) {
              _q = v.trim();
              _load();
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _err != null
                ? Center(child: Text(_err!))
                : items == null
                    ? const Center(child: CircularProgressIndicator())
                    : items.isEmpty
                        ? const Center(child: Text('Yaklaşan yayında etkinlik bulunamadı.'))
                        : ListView(children: [
                            for (final e in items)
                              ListTile(
                                title: Text(e.title),
                                subtitle: Text([if (e.startAt != null) dateTimeLong(e.startAt!), if (e.venueName.isNotEmpty) e.venueName, '${e.attendeeCount}/${e.capacity}'].join(' · ')),
                                onTap: () => Navigator.pop(context, e),
                              ),
                          ]),
          ),
        ]),
      ),
    );
  }
}
