import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/panel_ui/crew_ui.dart' show crewCanvas, crewCardColor;
import 'package:hadi/theme/hadi_colors.dart';

import '../panel_kit/command_palette.dart';
import '../panel_kit/panel_ai.dart' show panelAiAsker;
import '../panel_kit/panel_nav_menu.dart';
import '../panel_kit/panel_prefs.dart';
import 'crew_api.dart';
import 'crew_counts.dart';
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

/// Bu cihazdaki Crew gezinme tercihleri (sabitlenenler, son kullanılanlar, kategori aç/kapa).
PanelPrefs get crewPrefs => PanelPrefs.of('crew');

/// Komut paleti (Ctrl/Cmd+K): yalnızca kişinin GÖREBİLDİĞİ bölümler aranır ve YZ'ye gider.
Future<void> openCrewSearch(BuildContext context) async {
  final s = SessionScope.read(context);
  final id = await showPanelPalette(context, entries: crewEntries(s), prefs: crewPrefs, askAi: panelAiAsker('crew'));
  if (id == null || !context.mounted) return;
  final x = sectionById(id);
  if (x == null) return;
  if (x.id == 'pano') {
    context.go('/');
  } else {
    openSection(context, x);
  }
}

/// Son açılan bölüm/sekme (bölüme her girişte sayılar bir kez tazelenir; yeniden çizimlerde değil).
String? _lastShown;

/// Çıkış: rozet yenilemesini durdurur ve sayıları siler (sonraki kişi eski sayıları görmez).
Future<void> crewSignOut(Session s) {
  CrewCounts.instance.stop();
  _lastShown = null;
  return s.signOut();
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
    // Rozet sayıları: oturum boyunca tek kaynak (crew_counts.dart). Bir bölüme / sekmeye girince hemen tazelenir.
    final shown = section?.id ?? tab;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = CrewCounts.instance;
      final wasRunning = c.running;
      c.ensureStarted(s.uid, () => CrewApi.counts(s.services));
      if (wasRunning && _lastShown != shown) c.refreshSoon(Duration.zero);
      _lastShown = shown;
    });
    // Son kullanılanlar (bu cihazda, son 5) ve menüde kategorisi açık olsun.
    if (section != null && section!.id != 'pano') {
      final id = section!.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        crewPrefs.touch(id);
        PanelNavMenu.reveal(crewPrefs, [crewEntry(section!)], id);
      });
    }
    return PanelHotkeys(onOpen: () => openCrewSearch(context), child: _build(context, s, wide, current));
  }

  Widget _build(BuildContext context, Session s, bool wide, CrewSection current) {
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
          // Bölüm, masadaki bir sayfa gibi: en fazla 1120 px, ortada; yanlarda zemin ve ince çizgi.
          // (Satırlar ekran boyu uzayıp dağılmasın; her bölüm ayrı ayrı daraltılmak zorunda kalmasın.)
          Expanded(
            child: ColoredBox(
              color: crewCanvas(context),
              child: LayoutBuilder(builder: (context, c) {
                const max = 1120.0;
                if (c.maxWidth <= max + 48) return body;
                return Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: max),
                    decoration: BoxDecoration(
                      border: Border.symmetric(vertical: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                    ),
                    child: body,
                  ),
                );
              }),
            ),
          ),
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
                icon: t.$1 == 'kuyruklar' && queueTotal(visibleSections(s), d) > 0
                    ? Badge(label: Text(_n99(queueTotal(visibleSections(s), d))), child: Icon(t.$2))
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
    return ValueListenableBuilder<CrewDash?>(
      valueListenable: crewDashNotifier,
      builder: (context, d, _) => PanelNavMenu(
        title: 'HADİ Crew',
        width: 284,
        entries: crewEntries(session, includeGeneral: false),
        selectedId: current,
        prefs: crewPrefs,
        onSearch: () => openCrewSearch(context),
        onSelect: (id) => context.go(sectionById(id)?.path ?? '/'),
        count: (e) {
          final x = sectionById(e.id);
          return x == null ? null : sectionCount(x, d);
        },
        actions: [IconButton(tooltip: 'Çıkış yap', onPressed: () => crewSignOut(session), icon: const Icon(Icons.logout_rounded, size: 20))],
        top: [
          _TopTile(icon: Icons.space_dashboard_rounded, label: 'Pano', selected: current == 'pano', onTap: () => context.go('/')),
          _TopTile(
            icon: Icons.inbox_rounded,
            label: 'Kuyruklar',
            selected: current == 'kuyruklar',
            count: queueTotal(visibleSections(session), d),
            onTap: () => context.go('/kuyruklar'),
          ),
        ],
      ),
    );
  }
}

/// Kenar çubuğunda kategorilerin üstünde sabit duran Pano / Kuyruklar.
class _TopTile extends StatelessWidget {
  const _TopTile({required this.icon, required this.label, required this.selected, required this.onTap, this.count});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
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
        leading: Icon(icon, size: 20),
        title: Text(label, style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w600)),
        trailing: (count ?? 0) > 0 ? _CountPill(count!) : null,
        onTap: onTap,
      ),
    );
  }
}

String _n99(int n) => n > 99 ? '99+' : '$n';

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
      backgroundColor: crewCanvas(context),
      appBar: AppBar(title: const Text('Kuyruklar')),
      body: ValueListenableBuilder<CrewDash?>(
        valueListenable: crewDashNotifier,
        builder: (context, d, _) => ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text('Yetkinde bir kuyruk yok.', textAlign: TextAlign.center, style: TextStyle(color: HadiColors.ink2)),
            ),
          for (final x in list) _SectionTile(section: x, count: sectionCount(x, d)),
          if (d == null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Sayılar yükleniyor…', textAlign: TextAlign.center, style: TextStyle(color: HadiColors.ink3, fontSize: 12.5)),
            ),
        ]),
      ),
    );
  }
}

/// Tümü (telefon): kenar çubuğuyla AYNI yapı — arama, Sabitlenenler, Son kullanılanlar, daraltılabilir kategoriler (A–Z).
class AllSectionsPage extends StatelessWidget {
  const AllSectionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    return Scaffold(
      backgroundColor: crewCanvas(context),
      appBar: AppBar(
        title: const Text('Tümü'),
        actions: [
          IconButton(tooltip: 'Ara ya da sor', onPressed: () => openCrewSearch(context), icon: const Icon(Icons.search_rounded)),
          IconButton(tooltip: 'Çıkış yap', onPressed: () => crewSignOut(s), icon: const Icon(Icons.logout_rounded)),
        ],
      ),
      body: ValueListenableBuilder<CrewDash?>(
        valueListenable: crewDashNotifier,
        builder: (context, d, _) => PanelNavMenu(
          title: '',
          width: double.infinity,
          entries: crewEntries(s, includeGeneral: false),
          selectedId: null,
          prefs: crewPrefs,
          onSearch: () => openCrewSearch(context),
          onSelect: (id) {
            final x = sectionById(id);
            if (x != null) openSection(context, x);
          },
          count: (e) {
            final x = sectionById(e.id);
            return x == null ? null : sectionCount(x, d);
          },
        ),
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
        color: crewCardColor(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
        clipBehavior: Clip.antiAlias,
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
