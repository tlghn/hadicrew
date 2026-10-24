// HADİ Destek 2.0 — Destek masası (yetkili: kurucu, yönetici, moderatör).
// Sekmeler: Kuyruk (bekleme sayacı, önem, atama) · Hazır cevaplar · Durum bandı · Boşluklar (👎 / cevaplanamayan) · Sınırlar.
// Talep açılınca TicketThreadScreen(staff: true): hazır cevap, AI taslak → düzenle → gönder, durum, atama.
// Sunucu: supportDesk (support_tickets.ts); sınırlar: support › adminLimitsGet/adminLimitsSet (support.ts, D1).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hadi/core/motion.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/data/models.dart' show AppFailure;
import 'package:hadi/data/support_desk_service.dart';
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/instant.dart';
import 'package:hadi/widgets/toast.dart';
import 'package:hadi/features/support/support_status.dart' show supportStatusStyle;
import 'package:hadi/features/support/support_tickets_member.dart' show DeskStatusChip, TicketThreadScreen;
import 'package:hadi/core/service_switches.dart';
import 'desk_csat_strip.dart';

String _err(Object e, String fb) => e is AppFailure ? e.message : fb;

class SupportDeskAdmin extends StatefulWidget {
  const SupportDeskAdmin({super.key});
  @override
  State<SupportDeskAdmin> createState() => _SupportDeskAdminState();
}

class _SupportDeskAdminState extends State<SupportDeskAdmin> {
  int _tab = 0;
  static const _tabs = [
    (Icons.inbox_rounded, 'Kuyruk'),
    (Icons.bolt_rounded, 'Hazır cevaplar'),
    (Icons.campaign_rounded, 'Durum bandı'),
    (Icons.psychology_alt_rounded, 'Boşluklar'),
    (Icons.speed_rounded, 'Sınırlar'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        height: 52,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          itemCount: _tabs.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => ChoiceChip(
            avatar: Icon(_tabs[i].$1, size: 18),
            label: Text(_tabs[i].$2),
            selected: _tab == i,
            onSelected: (_) {
              HapticFeedback.selectionClick();
              setState(() => _tab = i);
            },
          ),
        ),
      ),
      Expanded(
        child: AnimatedSwitcher(
          duration: Motion.medium,
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(.03, 0), end: Offset.zero).animate(a), child: c)),
          child: KeyedSubtree(
            key: ValueKey(_tab),
            child: switch (_tab) {
              0 => const _Queue(),
              1 => const _CannedEditor(),
              2 => const _BannerEditor(),
              3 => const _Gaps(),
              _ => const _Limits(),
            },
          ),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- kuyruk

class _Queue extends StatefulWidget {
  const _Queue();
  @override
  State<_Queue> createState() => _QueueState();
}

class _QueueState extends State<_Queue> {
  String _status = 'active';
  String? _assigned;
  String _q = '';
  List<DeskTicket>? _items;
  List<({String uid, String name})> _staff = const [];
  String? _error;
  Timer? _tick, _debounce;

  @override
  void initState() {
    super.initState();
    _items = InstantCache.peek<List<DeskTicket>>('desk:queue');
    _load();
    // Bekleme sayaçları canlı kalsın; liste dakikada bir tazelenir.
    _tick = Timer.periodic(const Duration(seconds: 30), (t) {
      if (!mounted) return;
      setState(() {});
      if (t.tick % 2 == 0) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final r = await SupportDesk.instance.list(status: _status, assigned: _assigned, q: _q);
      if (!mounted) return;
      if (_status == 'active' && _assigned == null && _q.isEmpty) InstantCache.put('desk:queue', r.items);
      setState(() {
        _items = r.items;
        _staff = r.staff;
        _error = null;
      });
    } catch (e) {
      if (mounted && !silent) setState(() => _error = _err(e, 'Kuyruk yüklenemedi.'));
    }
  }

  void _filter(void Function() f) {
    HapticFeedback.selectionClick();
    setState(() {
      f();
      _items = null;
    });
    _load();
  }

  Future<void> _assign(DeskTicket t) async {
    final to = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sc) => ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 16), children: [
        const ListTile(title: Text('Kime atansın?', style: TextStyle(fontWeight: FontWeight.w900))),
        ListTile(leading: const Icon(Icons.pan_tool_alt_rounded), title: const Text('Üstüme al'), onTap: () => Navigator.pop(sc, '')),
        for (final s in _staff) ListTile(leading: const Icon(Icons.support_agent_rounded), title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis), onTap: () => Navigator.pop(sc, s.uid)),
      ]),
    );
    if (to == null) return;
    try {
      final n = await SupportDesk.instance.assign(t.id, to: to.isEmpty ? null : to);
      if (mounted) showToast(context, '#${t.code} → $n');
      _load(silent: true);
    } catch (e) {
      if (mounted) showToast(context, _err(e, 'Atanamadı.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    // Operasyon › Destek masası (support_desk_plus): Açık / Bekliyor / Çözüldü süzgeçleri ve CSAT şeridi.
    final plus = !ServiceSwitches.instance.isHidden('support_desk_plus');
    return Column(children: [
      if (plus) const DeskCsatStrip(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: TextField(
          onChanged: (v) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 350), () => _filter(() => _q = v.trim()));
          },
          decoration: const InputDecoration(
            hintText: 'Kod, özet ya da üye adı',
            prefixIcon: Icon(Icons.search_rounded, size: 20),
          ),
        ),
      ),
      SizedBox(
        height: 46,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(16, 8, 16, 2), children: [
          for (final (v, l) in plus
              ? const [('active', 'Çözülmemiş'), ('open', 'Açık'), ('waiting', 'Bekliyor'), ('resolved', 'Çözüldü'), ('all', 'Tümü')]
              : const [('active', 'Açık'), ('resolved', 'Çözülen'), ('all', 'Tümü')])
            Padding(padding: const EdgeInsets.only(right: 6), child: FilterChip(label: Text(l), selected: _status == v, onSelected: (_) => _filter(() => _status = v))),
          const SizedBox(width: 6),
          for (final (v, l) in [(null, 'Herkes'), ('me', 'Bana atanan'), ('none', 'Atanmamış')])
            Padding(padding: const EdgeInsets.only(right: 6), child: FilterChip(label: Text(l), selected: _assigned == v, onSelected: (_) => _filter(() => _assigned = v))),
        ]),
      ),
      Expanded(
        child: _error != null && items == null
            ? InlineError(message: _error!, onRetry: _load)
            : items == null
                ? const ListSkeleton(padding: EdgeInsets.all(12))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: items.isEmpty
                        ? ListView(children: const [
                            SizedBox(height: 80),
                            Icon(Icons.celebration_rounded, size: 48, color: HadiColors.dostluk),
                            SizedBox(height: 8),
                            Center(child: Text('Kuyruk boş. Harika iş! 🎉', style: TextStyle(fontWeight: FontWeight.w800))),
                          ])
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: items.length,
                            itemBuilder: (_, i) => FadeSlideIn(
                              key: ValueKey(items[i].id),
                              delay: Motion.stagger(i),
                              child: _QueueCard(
                                t: items[i],
                                onOpen: () async {
                                  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TicketThreadScreen(id: items[i].id, staff: true)));
                                  _load(silent: true);
                                },
                                onAssign: () => _assign(items[i]),
                              ),
                            ),
                          ),
                  ),
      ),
    ]);
  }
}

Color _sevColor(String s) => switch (s) {
      'critical' => HadiColors.error,
      'high' => HadiColors.heyecan,
      'medium' => HadiColors.aktivite,
      _ => HadiColors.ink3,
    };

String _sevLabel(String s) => switch (s) {
      'critical' => 'Acil',
      'high' => 'Yüksek',
      'medium' => 'Orta',
      _ => 'Düşük',
    };

String _wait(Duration d) {
  if (d.inMinutes < 1) return 'şimdi';
  if (d.inMinutes < 60) return '${d.inMinutes} dk';
  if (d.inHours < 24) return '${d.inHours} sa ${d.inMinutes % 60} dk';
  return '${d.inDays} gün ${d.inHours % 24} sa';
}

/// SLA hedefi (önem derecesine göre): acil 15 dk, yüksek 1 sa, orta 4 sa, düşük 24 sa.
Duration _slaFor(String s) => switch (s) {
      'critical' => const Duration(minutes: 15),
      'high' => const Duration(hours: 1),
      'medium' => const Duration(hours: 4),
      _ => const Duration(hours: 24),
    };

class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.t, required this.onOpen, required this.onAssign});
  final DeskTicket t;
  final VoidCallback onOpen, onAssign;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sev = _sevColor(t.severity);
    final waiting = t.waitingSince == null || t.resolved ? null : DateTime.now().difference(t.waitingSince!);
    final sla = _slaFor(t.severity);
    final ratio = waiting == null ? 0.0 : (waiting.inSeconds / sla.inSeconds).clamp(0.0, 1.0);
    final late = waiting != null && waiting > sla;
    final slaColor = late ? HadiColors.error : (ratio > .6 ? HadiColors.heyecan : HadiColors.dostluk);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: Theme.of(context).brightness == Brightness.dark ? null : cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: late ? HadiColors.error.withValues(alpha: .5) : cs.outlineVariant)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 5, color: sev),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('#${t.code}', style: const TextStyle(fontWeight: FontWeight.w900, fontFamily: 'monospace')),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: sev.withValues(alpha: .12), borderRadius: BorderRadius.circular(99)),
                      child: Text(_sevLabel(t.severity), style: TextStyle(color: HadiColors.readableOn(sev, sev.withValues(alpha: .12)), fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                    if (t.source == 'safety') ...[const SizedBox(width: 4), const Icon(Icons.shield_rounded, size: 15, color: HadiColors.error)],
                    if (t.source == 'report') ...[const SizedBox(width: 4), const Icon(Icons.bug_report_rounded, size: 15, color: HadiColors.heyecan)],
                    if (t.attachments.isNotEmpty) ...[const SizedBox(width: 4), Icon(Icons.image_rounded, size: 15, color: HadiColors.ink3)],
                    const Spacer(),
                    DeskStatusChip(status: t.status),
                  ]),
                  const SizedBox(height: 4),
                  Text(t.summary.isEmpty ? '(özet yok)' : t.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.3)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(Icons.person_rounded, size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Flexible(child: Text(t.name.isEmpty ? 'Üye' : t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12))),
                    if (t.unread > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: HadiColors.pink, borderRadius: BorderRadius.circular(99)),
                        child: Text('${t.unread} yeni', style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                      ),
                    ],
                    const Spacer(),
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(t.assignedName == null ? Icons.person_add_alt_rounded : Icons.support_agent_rounded, size: 16),
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 110),
                        child: Text(t.assignedName ?? 'Ata', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                      ),
                      onPressed: onAssign,
                    ),
                  ]),
                  if (waiting != null) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(late ? Icons.alarm_rounded : Icons.timer_outlined, size: 14, color: slaColor),
                      const SizedBox(width: 4),
                      Text(late ? 'Bekliyor ${_wait(waiting)} · SLA aşıldı' : 'Bekliyor ${_wait(waiting)}',
                          style: TextStyle(color: slaColor, fontSize: 12, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: ratio),
                            duration: Motion.slow,
                            curve: Curves.easeOutCubic,
                            builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 4, color: slaColor, backgroundColor: slaColor.withValues(alpha: .15)),
                          ),
                        ),
                      ),
                    ]),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- hazır cevaplar

class _CannedEditor extends StatefulWidget {
  const _CannedEditor();
  @override
  State<_CannedEditor> createState() => _CannedEditorState();
}

class _CannedEditorState extends State<_CannedEditor> {
  List<DeskCanned>? _items;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await SupportDesk.instance.canned();
      if (mounted) {
        setState(() {
          _items = l;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _err(e, 'Hazır cevaplar yüklenemedi.'));
    }
  }

  Future<void> _edit([int? i]) async {
    final cur = i == null ? null : _items![i];
    final title = TextEditingController(text: cur?.title ?? '');
    final text = TextEditingController(text: cur?.text ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        scrollable: true,
        title: Text(cur == null ? 'Yeni hazır cevap' : 'Hazır cevabı düzenle'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, maxLength: 60, decoration: const InputDecoration(labelText: 'Başlık')),
          TextField(controller: text, minLines: 3, maxLines: 8, maxLength: 1500, decoration: const InputDecoration(labelText: 'Metin', helperText: '{ad} → üyenin adı')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Kaydet')),
        ],
      ),
    );
    if (ok != true || title.text.trim().isEmpty || text.text.trim().isEmpty) return;
    final next = [...?_items];
    final c = DeskCanned(id: cur?.id ?? 'c${DateTime.now().millisecondsSinceEpoch}', title: title.text.trim(), text: text.text.trim());
    if (i == null) {
      next.add(c);
    } else {
      next[i] = c;
    }
    await _save(next);
  }

  Future<void> _save(List<DeskCanned> next) async {
    final prev = _items;
    setState(() {
      _items = next;
      _saving = true;
    });
    try {
      await SupportDesk.instance.setCanned(next);
      HapticFeedback.lightImpact();
    } catch (e) {
      if (mounted) {
        setState(() => _items = prev);
        showToast(context, _err(e, 'Kaydedilemedi.'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (_error != null && items == null) return InlineError(message: _error!, onRetry: _load);
    if (items == null) return const ListSkeleton(padding: EdgeInsets.all(12));
    return Stack(children: [
      ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        itemCount: items.length,
        onReorder: (a, b) {
          final next = [...items];
          final x = next.removeAt(a);
          next.insert(b > a ? b - 1 : b, x);
          _save(next);
        },
        header: items.isEmpty
            ? const Padding(padding: EdgeInsets.all(24), child: Text('Sık yazdığın cevapları ekle; talepte ⚡ ile tek dokunuşla eklenir.', textAlign: TextAlign.center))
            : null,
        itemBuilder: (_, i) => Card(
          key: ValueKey(items[i].id),
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .6))),
          child: ListTile(
            leading: const Icon(Icons.bolt_rounded, color: HadiColors.heyecan),
            title: Text(items[i].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(items[i].text, maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: () => _edit(i),
            trailing: IconButton(
              tooltip: 'Sil',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _save([...items]..removeAt(i)),
            ),
          ),
        ),
      ),
      Positioned(
        right: 16,
        bottom: 16 + MediaQuery.paddingOf(context).bottom,
        child: FloatingActionButton.extended(
          heroTag: 'canned-add',
          onPressed: _saving ? null : () => _edit(),
          icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2)) : const Icon(Icons.add_rounded),
          label: const Text('Ekle'),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- durum bandı

class _BannerEditor extends StatefulWidget {
  const _BannerEditor();
  @override
  State<_BannerEditor> createState() => _BannerEditorState();
}

class _BannerEditorState extends State<_BannerEditor> {
  final _text = TextEditingController();
  String _level = 'info';
  int? _hours; // null → süresiz
  bool _busy = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    SupportDesk.instance.status(force: true).then((s) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        if (s != null) {
          _text.text = s.text;
          _level = s.level;
        }
      });
    }, onError: (Object _) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save({bool clear = false}) async {
    if (!clear && _text.text.trim().isEmpty) return showToast(context, 'Önce bandın metnini yaz.');
    setState(() => _busy = true);
    try {
      await SupportDesk.instance.setStatusBanner(
        text: clear ? '' : _text.text.trim(),
        level: _level,
        until: clear || _hours == null ? null : DateTime.now().add(Duration(hours: _hours!)),
      );
      await SupportDesk.instance.status(force: true);
      if (clear) _text.clear();
      HapticFeedback.mediumImpact();
      if (mounted) showToast(context, clear ? 'Durum bandı kaldırıldı.' : 'Durum bandı yayında.');
    } catch (e) {
      if (mounted) showToast(context, _err(e, 'Kaydedilemedi.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const ListSkeleton(count: 3, padding: EdgeInsets.all(12));
    final s = SessionScope.read(context);
    final canEdit = s.isAdmin;
    final st = supportStatusStyle(_level);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      Text('Bilinen bir sorun varsa (ör. ödeme gecikmesi) üyeler destek ekranının üstünde görür.', style: TextStyle(color: HadiColors.ink2, height: 1.35)),
      const SizedBox(height: 12),
      // Canlı önizleme
      AnimatedContainer(
        duration: Motion.medium,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: st.bg, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(st.icon, color: st.fg),
          const SizedBox(width: 10),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: _text,
              builder: (_, v, _) => Text(v.text.trim().isEmpty ? 'Önizleme' : v.text.trim(), maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: st.fg, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      TextField(controller: _text, enabled: canEdit, maxLength: 300, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Metin')),
      const SizedBox(height: 4),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'info', label: Text('Bilgi'), icon: Icon(Icons.info_rounded)),
          ButtonSegment(value: 'warn', label: Text('Uyarı'), icon: Icon(Icons.warning_amber_rounded)),
          ButtonSegment(value: 'critical', label: Text('Kritik'), icon: Icon(Icons.report_rounded)),
        ],
        selected: {_level},
        onSelectionChanged: canEdit ? (v) => setState(() => _level = v.first) : null,
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (h, l) in [(null, 'Süresiz'), (1, '1 saat'), (4, '4 saat'), (24, '1 gün'), (72, '3 gün')])
          ChoiceChip(label: Text(l), selected: _hours == h, onSelected: canEdit ? (_) => setState(() => _hours = h) : null),
      ]),
      const SizedBox(height: 16),
      if (!canEdit)
        Text('Durum bandını kurucu ve yöneticiler değiştirebilir.', style: TextStyle(color: HadiColors.ink3))
      else
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : () => _save(clear: true), icon: const Icon(Icons.layers_clear_rounded), label: const Text('Kaldır'))),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white)) : const Icon(Icons.campaign_rounded),
              label: const Text('Yayınla'),
            ),
          ),
        ]),
    ]);
  }
}

// ---------------------------------------------------------------- boşluklar

class _Gaps extends StatefulWidget {
  const _Gaps();
  @override
  State<_Gaps> createState() => _GapsState();
}

class _GapsState extends State<_Gaps> {
  ({List<({String question, String reply, bool unknown})> items, List<({String sample, int count})> groups})? _d;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await SupportDesk.instance.gaps();
      if (mounted) {
        setState(() {
          _d = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _err(e, 'Liste yüklenemedi.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (_error != null && d == null) return InlineError(message: _error!, onRetry: _load);
    if (d == null) return const ListSkeleton(padding: EdgeInsets.all(12));
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
        Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text('👎 alan ve botun cevaplayamadığı sorular. Sık tekrar edenler bilgi bankasına (docs/app_kb.md) eklenmeli.', style: TextStyle(color: HadiColors.ink2, height: 1.35)),
        ),
        if (d.groups.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.fromLTRB(4, 4, 4, 6), child: Text('Bilgi bankasına eklenecekler', style: TextStyle(fontWeight: FontWeight.w900))),
          for (final (i, g) in d.groups.indexed)
            FadeSlideIn(
              delay: Motion.stagger(i),
              child: Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 6),
                color: HadiColors.iletisim.withValues(alpha: .08),
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: HadiColors.iletisim, child: Text('${g.count}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
                  title: Text(g.sample, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    tooltip: 'Kopyala',
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: g.sample));
                      showToast(context, 'Kopyalandı');
                    },
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
        ],
        const Padding(padding: EdgeInsets.fromLTRB(4, 4, 4, 6), child: Text('Son sorular', style: TextStyle(fontWeight: FontWeight.w900))),
        if (d.items.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Şimdilik boşluk yok 👏'))),
        for (final x in d.items)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outlineVariant.withValues(alpha: .6))),
            child: ExpansionTile(
              shape: const Border(),
              leading: Icon(x.unknown ? Icons.help_outline_rounded : Icons.thumb_down_alt_outlined, color: x.unknown ? HadiColors.aktivite : HadiColors.heyecan),
              title: Text(x.question, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(x.unknown ? 'Cevaplanamadı' : '👎 aldı', style: const TextStyle(fontSize: 12)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [if (x.reply.isNotEmpty) SelectableText('Bot: ${x.reply}', style: TextStyle(color: cs.onSurfaceVariant))],
            ),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- günlük mesaj sınırları

class _Limits extends StatefulWidget {
  const _Limits();
  @override
  State<_Limits> createState() => _LimitsState();
}

class _LimitsState extends State<_Limits> {
  final _daily = TextEditingController();
  final _premium = TextEditingController();
  final _reason = TextEditingController();
  bool _loaded = false, _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _daily.dispose();
    _premium.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final l = await SupportDesk.instance.limits();
      if (!mounted) return;
      setState(() {
        _daily.text = l.daily > 0 ? '${l.daily}' : '';
        _premium.text = l.premium > 0 ? '${l.premium}' : '';
        _loaded = true;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loaded = true;
          _error = _err(e, 'Sınırlar alınamadı.');
        });
      }
    }
  }

  Future<void> _save() async {
    final d = int.tryParse(_daily.text.trim());
    final p = int.tryParse(_premium.text.trim());
    final r = _reason.text.trim();
    if (d == null || p == null || d < 5 || d > 1000 || p > 5000) return showToast(context, 'Temel 5–1000, Premium en çok 5000 olmalı.');
    if (p < d) return showToast(context, 'Premium sınırı temel sınırdan düşük olamaz.');
    if (r.length < 3) return showToast(context, 'Gerekçe zorunlu (kayda geçer).');
    setState(() => _busy = true);
    try {
      await SupportDesk.instance.setLimits(daily: d, premium: p, reason: r);
      _reason.clear();
      HapticFeedback.mediumImpact();
      if (mounted) showToast(context, 'Sınırlar kaydedildi.');
    } catch (e) {
      if (mounted) showToast(context, _err(e, 'Kaydedilemedi.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const ListSkeleton(count: 3, padding: EdgeInsets.all(12));
    final s = SessionScope.read(context);
    final canEdit = s.isFounder && s.isPrimary;
    Widget field(TextEditingController c, String label, IconData icon) => TextField(
          controller: c,
          enabled: canEdit,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
          decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), suffixText: 'mesaj / gün'),
        );
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      Text('HADİ Destek botuna bir üyenin günde gönderebileceği mesaj sayısı. Premium üyelerin sınırı daha yüksektir; kurucular sınırsızdır.', style: TextStyle(color: HadiColors.ink2, height: 1.35)),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: InlineError(message: _error!, onRetry: _load, compact: true)),
      const SizedBox(height: 14),
      FadeSlideIn(child: field(_daily, 'Temel üye', Icons.person_rounded)),
      const SizedBox(height: 10),
      FadeSlideIn(delay: Motion.stagger(1), child: field(_premium, 'Premium üye', Icons.workspace_premium_rounded)),
      const SizedBox(height: 10),
      if (canEdit) ...[
        TextField(controller: _reason, maxLength: 200, decoration: const InputDecoration(labelText: 'Gerekçe (zorunlu, kayda geçer)')),
        const SizedBox(height: 6),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white)) : const Icon(Icons.save_rounded),
          label: const Text('Kaydet'),
        ),
      ] else
        Text('Sınırları yalnızca ana kurucu değiştirebilir.', style: TextStyle(color: HadiColors.ink3)),
    ]);
  }
}
