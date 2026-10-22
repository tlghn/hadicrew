import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/theme/hadi_colors.dart';

import 'crew_api.dart';
import 'dashboard.dart' show crewDashNotifier;
import 'sections.dart';

/// Geniş ekran eşiği: üstünde solda kalıcı kenar çubuğu, altında alt menü.
const double kWide = 920;

/// Bölüm aç: geniş ekranda kenar çubuğuyla aynı yerde (geri oku yok), telefonda üste (geri ile döner).
void openSection(BuildContext context, CrewSection section) {
  if (MediaQuery.sizeOf(context).width >= kWide) {
    context.go(section.path);
  } else {
    context.push(section.path);
  }
}

/// Bölüm sayacı (panodaki son veriden): İşletmeler başvuru + etkinlik toplamı.
int? sectionCount(CrewSection s, CrewDash? d) {
  if (d == null || s.countKey == null) return null;
  if (s.id == 'isletmeler') {
    final a = d.count('businessApps'), b = d.count('businessEvents');
    if (a == null && b == null) return null;
    return (a ?? 0) + (b ?? 0);
  }
  return d.count(s.countKey!);
}

/// Kök: geniş ekranda kenar çubuğu + içerik; telefonda alt menülü sekmeler (Pano · Kuyruklar · Üyeler · Tümü).
class CrewShell extends StatelessWidget {
  const CrewShell({super.key, required this.tab, this.section});

  /// pano | kuyruklar | tumu | (bölüm kimliği)
  final String tab;
  final CrewSection? section;

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= kWide;
    final current = section ?? sectionById('pano')!;
    if (wide) {
      final body = switch (tab) {
        'kuyruklar' => const QueuesPage(),
        'tumu' => const AllSectionsPage(),
        _ => KeyedSubtree(key: ValueKey('b-${current.id}'), child: current.build()),
      };
      return Scaffold(
        body: Row(children: [
          _Sidebar(current: tab == 'kuyruklar' || tab == 'tumu' ? tab : current.id, session: s),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    // Telefon: kök sekmeler alt menülü; bir bölüm açıldıysa tam ekran (geri ile döner).
    final members = sectionById('uyeler')!;
    final showMembers = members.visible(s);
    final tabs = <(String, IconData, String)>[
      ('pano', Icons.space_dashboard_rounded, 'Pano'),
      ('kuyruklar', Icons.inbox_rounded, 'Kuyruklar'),
      if (showMembers) ('uyeler', Icons.manage_accounts_rounded, 'Üyeler'),
      ('tumu', Icons.apps_rounded, 'Tümü'),
    ];
    final index = tabs.indexWhere((t) => t.$1 == (section?.id ?? tab));
    final body = switch (tab) {
      'kuyruklar' => const QueuesPage(),
      'tumu' => const AllSectionsPage(),
      _ => KeyedSubtree(key: ValueKey('b-${current.id}'), child: current.build()),
    };
    // Bölüm üstte açıldıysa (geri ile döner) alt menü gösterilmez; doğrudan bağlantıyla açıldıysa menü kalır.
    if (index < 0 && Navigator.of(context).canPop()) return body;
    return Scaffold(
      body: body,
      bottomNavigationBar: ValueListenableBuilder<CrewDash?>(
        valueListenable: crewDashNotifier,
        builder: (context, d, _) => NavigationBar(
          selectedIndex: index < 0 ? tabs.length - 1 : index,
          onDestinationSelected: (i) {
            final id = tabs[i].$1;
            context.go(id == 'pano' ? '/' : (id == 'kuyruklar' || id == 'tumu') ? '/$id' : '/b/$id');
          },
          destinations: [
            for (final t in tabs)
              NavigationDestination(
                icon: t.$1 == 'kuyruklar' && (d?.pendingTotal ?? 0) > 0
                    ? Badge(label: Text('${d!.pendingTotal > 99 ? '99+' : d.pendingTotal}'), child: Icon(t.$2))
                    : Icon(t.$2),
                label: t.$3,
              ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.current, required this.session});
  final String current;
  final Session session;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = visibleSections(session);
    return SizedBox(
      width: 280,
      child: Material(
        color: cs.surfaceContainerLow,
        child: SafeArea(
          child: ValueListenableBuilder<CrewDash?>(
            valueListenable: crewDashNotifier,
            builder: (context, d, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
                child: Row(children: [
                  Expanded(child: Text('HADİ Crew', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                  IconButton(tooltip: 'Çıkış yap', onPressed: () => session.signOut(), icon: const Icon(Icons.logout_rounded, size: 20)),
                ]),
              ),
              Expanded(
                child: ListView(padding: const EdgeInsets.fromLTRB(10, 0, 10, 16), children: [
                  for (final g in CrewGroup.values)
                    if (list.any((x) => x.group == g)) ...[
                      if (g != CrewGroup.genel)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
                          child: Text(g.label.toUpperCase(),
                              style: TextStyle(fontSize: 11, letterSpacing: .6, fontWeight: FontWeight.w800, color: HadiColors.ink3)),
                        ),
                      for (final x in list.where((x) => x.group == g)) _NavTile(section: x, selected: x.id == current, count: sectionCount(x, d)),
                    ],
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.section, required this.selected, required this.count});
  final CrewSection section;
  final bool selected;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: cs.primaryContainer,
        selectedColor: cs.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(section.icon, size: 20),
        title: Text(section.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        trailing: (count ?? 0) > 0 ? _CountPill(count!) : null,
        onTap: () => context.go(section.id == 'pano' ? '/' : section.path),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill(this.n);
  final int n;

  @override
  Widget build(BuildContext context) {
    final f = HadiColors.brandFill(HadiColors.heyecan);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: f.bg, borderRadius: BorderRadius.circular(99)),
      child: Text(n > 99 ? '99+' : '$n', style: TextStyle(color: f.fg, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }
}

/// Kuyruklar: bekleyen işi olan bölümler, sayılarıyla.
class QueuesPage extends StatelessWidget {
  const QueuesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    final list = [for (final x in visibleSections(s)) if (x.queue) x];
    return Scaffold(
      appBar: AppBar(title: const Text('Kuyruklar')),
      body: ValueListenableBuilder<CrewDash?>(
        valueListenable: crewDashNotifier,
        builder: (context, d, _) => ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text('Yetkinde bir kuyruk yok.', textAlign: TextAlign.center, style: TextStyle(color: HadiColors.ink2)),
            ),
          for (final x in list) _SectionTile(section: x, count: sectionCount(x, d)),
          if (d == null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Sayılar Pano açıldığında yüklenir.', textAlign: TextAlign.center, style: TextStyle(color: HadiColors.ink3, fontSize: 12.5)),
            ),
        ]),
      ),
    );
  }
}

/// Tümü: yetkili olunan bütün bölümler, gruplu.
class AllSectionsPage extends StatelessWidget {
  const AllSectionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    final list = visibleSections(s);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tümü'),
        actions: [IconButton(tooltip: 'Çıkış yap', onPressed: () => s.signOut(), icon: const Icon(Icons.logout_rounded))],
      ),
      body: ValueListenableBuilder<CrewDash?>(
        valueListenable: crewDashNotifier,
        builder: (context, d, _) => ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: [
          for (final g in CrewGroup.values)
            if (g != CrewGroup.genel && list.any((x) => x.group == g)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
                child: Text(g.label, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: HadiColors.ink2)),
              ),
              for (final x in list.where((x) => x.group == g)) _SectionTile(section: x, count: sectionCount(x, d)),
            ],
        ]),
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({required this.section, required this.count});
  final CrewSection section;
  final int? count;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 8),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: ListTile(
          leading: Icon(section.icon, color: HadiColors.aktivite),
          title: Text(section.title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(section.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if ((count ?? 0) > 0) _CountPill(count!),
            const Icon(Icons.chevron_right_rounded),
          ]),
          onTap: () => openSection(context, section),
        ),
      );
}
