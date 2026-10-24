// HADİ Crew
// Kaynak: hadimobile/lib/features/feed/content_hide.dart (21 Ekim 2026'da HADİ Crew'e taşındı).
import 'package:flutter/material.dart';
import 'package:hadi/core/capabilities.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/data/models.dart';
import 'package:hadi/features/feed/content_hide.dart';
import 'package:hadi/panel_ui/crew_ui.dart';
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/hadi_sheet.dart';
import 'package:hadi/core/ui_gate.dart';

/// Gönderi "…" menüsüne eklenecek satır: "Gizle (tüm uygulamada)" / "Gizlemeyi kaldır".
/// Yetki yoksa boş liste döner. [sheet]: açık menünün context'i (kapatılır).
List<Widget> contentHideTiles(BuildContext context, BuildContext sheet, HideTarget t, {required bool hidden, VoidCallback? onChanged}) {
  final s = SessionScope.read(context);
  if (!canHideContent(s)) return const [];
  return [
    ListTile(
      leading: Icon(hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: hidden ? HadiColors.dostluk : HadiColors.error),
      title: Text(hidden ? 'Gizlemeyi kaldır' : 'Gizle (tüm uygulamada)', style: TextStyle(color: hidden ? null : HadiColors.error)),
      subtitle: Text(hidden ? 'Herkes yeniden görebilir.' : 'Yalnızca sahibi görür; sahibine gerekçesiyle bildirilir.'),
      onTap: () async {
        Navigator.pop(sheet);
        final ok = hidden ? await unhideContentFlow(context, t) : await hideContentFlow(context, t);
        if (ok) onChanged?.call();
      },
    ),
  ];
}

/// Gerekçe seç → onayla → gizle. Başarılıysa true.
Future<bool> hideContentFlow(BuildContext context, HideTarget t) async {
  final services = SessionScope.read(context).services;
  final messenger = ScaffoldMessenger.of(context);
  final custom = TextEditingController();
  final reason = await showHadiSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Text('Bu ${t.noun} tüm uygulamada gizlensin mi?', style: Theme.of(c).textTheme.titleLarge),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text('Akış, keşfet, profil, arama ve etiketlerden kalkar; yalnızca sahibi "Gizlendi" bandıyla görür. '
              'Sahibine seçtiğin gerekçe bildirilir ve itiraz edebilir.', style: TextStyle(color: HadiColors.ink3)),
        ),
        for (final r in kHideReasons) ListTile(dense: true, leading: const Icon(Icons.rule_rounded, size: 20), title: Text(r), onTap: () => Navigator.pop(c, r)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: custom,
                maxLength: 300,
                decoration: const InputDecoration(hintText: 'Başka bir gerekçe yaz…', counterText: ''),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                final v = custom.text.trim();
                if (v.length >= 3) Navigator.pop(c, v);
              },
              child: const Text('Gizle'),
            ),
          ]),
        ),
      ]),
    ),
  );
  custom.dispose();
  if (reason == null) return false;
  try {
    await ContentHide.hide(services, t, reason);
    messenger.showSnackBar(SnackBar(content: Text('${t.noun[0].toUpperCase()}${t.noun.substring(1)} tüm uygulamada gizlendi.')));
    return true;
  } on AppFailure catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
}

/// Onayla → gizlemeyi kaldır. Başarılıysa true.
Future<bool> unhideContentFlow(BuildContext context, HideTarget t) async {
  final services = SessionScope.read(context).services;
  final messenger = ScaffoldMessenger.of(context);
  final ok = await uiOnce(context, () => showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Gizleme kaldırılsın mı?'),
      content: Text('Bu ${t.noun} yeniden herkese görünür olur; sahibine haber verilir.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kaldır')),
      ],
    ),
  ));
  if (ok != true) return false;
  try {
    await ContentHide.unhide(services, t);
    messenger.showSnackBar(const SnackBar(content: Text('Gizleme kaldırıldı.')));
    return true;
  } on AppFailure catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
}

/// Kurucu paneli › Gizlenen gönderiler: liste, itirazlar ve "Gizlemeyi kaldır".
class HiddenContentScreen extends StatefulWidget {
  const HiddenContentScreen({super.key, this.embedded = false});

  /// true: başka bir sekmenin içinde (Scaffold'suz).
  final bool embedded;

  @override
  State<HiddenContentScreen> createState() => _HiddenContentScreenState();
}

class _HiddenContentScreenState extends State<HiddenContentScreen> {
  late Future<List<HiddenItem>> _f = _load();

  /// 0: Modere edilecek (karar bekleyen) · 1: Karara bağlanan / tümü · 2: İtirazlar
  int _tab = 0;
  String? _busyKey;

  /// "Gizli kalsın" / "Geri aç" (isteğe bağlı not).
  Future<void> _decide(HiddenItem x, {required bool keep}) async {
    final note = TextEditingController();
    final ok = await uiOnce(context, () => showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(keep ? 'Gizli kalsın mı?' : 'Geri açılsın mı?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(keep
              ? '${x.label} herkese kapalı kalır. Sahibi itiraz edebilir.'
              : '${x.label} yeniden herkese görünür; sahibine bildirilir.'),
          const SizedBox(height: 8),
          TextField(controller: note, maxLength: 300, decoration: const InputDecoration(hintText: 'Not (isteğe bağlı)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(keep ? 'Gizli kalsın' : 'Geri aç')),
        ],
      ),
    ));
    final text = note.text.trim();
    note.dispose();
    if (ok != true || !mounted) return;
    setState(() => _busyKey = x.key);
    try {
      await ContentHide.review(SessionScope.read(context).services, x.target, keep: keep, note: text);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(keep ? 'Karar kaydedildi: gizli kalacak.' : 'Geri açıldı.')));
      _reload();
    } on AppFailure catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<List<HiddenItem>> _load() => ContentHide.list(SessionScope.read(context).services);

  void _reload() => setState(() { _f = _load(); });

  Widget _thumb(HiddenItem x) => x.thumb != null
      ? Image.network(x.thumb!, fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: HadiColors.mist))
      : ColoredBox(color: HadiColors.mist, child: Icon(Icons.notes_rounded, color: HadiColors.ink3));

  Widget _item(HiddenItem x, Session s) {
    final t = Theme.of(context).textTheme;
    final (pill, color) = x.pending
        ? ('Karar bekliyor', HadiColors.heyecan)
        : x.review == 'kept'
            ? ('Gizli kalıyor', HadiColors.error)
            : ('Gizli', HadiColors.ink3);
    return CrewQueueCard(
      thumb: _thumb(x),
      title: '${x.label} · ${x.ownerName}',
      pill: CrewPill(pill, color: color),
      meta: '${x.pending ? 'İşaretleyen' : 'Gizleyen'}: ${x.byName}${x.at != null ? ' · ${_date(x.at!)}' : ''}',
      details: [
        if (x.preview.isNotEmpty) Text(x.preview, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
        Text('Gerekçe: ${x.reason}', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        if (x.review == 'kept')
          Text('Karar: gizli kalsın · ${x.reviewByName ?? ''}${x.reviewAt != null ? ' · ${_date(x.reviewAt!)}' : ''}${(x.reviewNote ?? '').isNotEmpty ? ' · ${x.reviewNote}' : ''}',
              style: t.bodySmall),
        if (x.appeal != null) CrewQuote('İtiraz: ${x.appeal}'),
        if (x.pending && x.by == s.uid && !s.isFounder)
          Text('Sen işaretledin: başka bir yetkili karara bağlamalı.', style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
      ],
      actions: [
        if (x.pending && !(x.by == s.uid && !s.isFounder)) ...[
          OutlinedButton.icon(
            icon: const Icon(Icons.visibility_rounded, size: 18),
            label: const Text('Geri aç'),
            onPressed: _busyKey == x.key ? null : () => _decide(x, keep: false),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.gpp_good_rounded, size: 18),
            label: const Text('Gizli kalsın'),
            style: FilledButton.styleFrom(backgroundColor: HadiColors.fillForWhite(HadiColors.error), foregroundColor: Colors.white),
            onPressed: _busyKey == x.key ? null : () => _decide(x, keep: true),
          ),
        ],
        if (!x.pending)
          TextButton.icon(
            icon: const Icon(Icons.visibility_rounded, size: 18),
            label: const Text('Gizlemeyi kaldır'),
            onPressed: () async {
              if (await unhideContentFlow(context, x.target)) _reload();
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<HiddenItem>>(
      future: _f,
      builder: (context, snap) {
        final s = SessionScope.read(context);
        List<Widget> children;
        Map<int, int>? counts;
        if (snap.hasError) {
          children = [CrewCard(child: CrewError(message: snap.error is AppFailure ? '${snap.error}' : 'Bağlantını kontrol edip tekrar dene.', onRetry: _reload))];
        } else if (!snap.hasData) {
          children = const [CrewCard(child: CrewLoading())];
        } else {
          final all = snap.data!;
          final pend = all.where((x) => x.pending).toList();
          final done = all.where((x) => !x.pending).toList();
          final apps = all.where((x) => x.appeal != null).toList();
          counts = {0: pend.length, 1: done.length, 2: apps.length};
          final items = switch (_tab) { 0 => pend, 1 => done, _ => apps };
          children = [
            if (items.isEmpty)
              CrewCard(
                child: CrewEmpty(
                  icon: Icons.verified_user_outlined,
                  title: _tab == 0 ? 'Karar bekleyen içerik yok' : _tab == 1 ? 'Karara bağlanan içerik yok' : 'İtiraz yok',
                  message: _tab == 0 ? 'Bir gönderi işaretlenince burada görünür.' : null,
                ),
              ),
            for (final x in items) _item(x, s),
          ];
        }
        return CrewPage(
          title: 'Modere edilecek gönderiler',
          subtitle: 'İşaretlenenler, kararlar ve itirazlar',
          embedded: widget.embedded,
          maxWidth: 960,
          gap: CrewSpace.md,
          onRefresh: () async => _reload(),
          actions: [IconButton(tooltip: 'Yenile', onPressed: _reload, icon: const Icon(Icons.refresh_rounded))],
          toolbar: CrewFilterChips<int>(
            options: const [(0, 'Modere edilecek'), (1, 'Karara bağlanan'), (2, 'İtirazlar')],
            value: _tab,
            counts: counts,
            onChanged: (v) => setState(() => _tab = v),
          ),
          children: children,
        );
      },
    );
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Gönderi gizleme yetkisi: kurucular ve `content.hide` yetenekli roller.
bool canHideContent(Session s) => s.isFounder || s.can(Cap.contentHide);
