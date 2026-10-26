// Panel yan menüsü (27 Ekim 2026): arama düğmesi (Ctrl/Cmd+K), Sabitlenenler, Son kullanılanlar ve daraltılabilir kategoriler.
// Kategoriler ve içlerindeki bölümler Türk alfabesine göre sıralı (tr_text.dart › trCompare). Geniş ekranda kalıcı kenar
// çubuğu, dar ekranda çekmece (Drawer) olarak aynı bileşen kullanılır. Kurucu Paneli ve HADİ Crew ortak.
import 'package:flutter/material.dart';

import 'package:hadi/theme/hadi_colors.dart';

import 'command_palette.dart' show panelHotkeyLabel;
import 'panel_prefs.dart';
import 'panel_search.dart';

class PanelNavMenu extends StatelessWidget {
  const PanelNavMenu({
    super.key,
    required this.title,
    required this.entries,
    required this.selectedId,
    required this.onSelect,
    required this.prefs,
    required this.onSearch,
    this.top = const [],
    this.actions = const [],
    this.trailing,
    this.count,
    this.width = 284,
  });

  final String title;
  final List<PanelEntry> entries;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final PanelPrefs prefs;
  final VoidCallback onSearch;

  /// Kategorilerin üstünde sabit duran öğeler (ör. Pano, Destek talepleri kısayolu).
  final List<Widget> top;

  /// Başlık satırının sağı (ör. çıkış).
  final List<Widget> actions;

  /// Bölüm satırının sağında rozet (ör. bekleyen destek sayısı).
  final Widget? Function(PanelEntry e)? trailing;

  /// Bekleyen iş sayısı: satırda ve (kapalıyken) kategori başlığında toplam olarak gösterilir.
  final int? Function(PanelEntry e)? count;
  final double width;

  /// [id]'nin kategorisini açık işaretle (paletten / bağlantıdan gidilince menüde görünsün).
  static void reveal(PanelPrefs prefs, List<PanelEntry> entries, String id) {
    for (final e in entries) {
      if (e.id == id) {
        if (prefs.categoryOpen(e.category) == false) prefs.setCategoryOpen(e.category, true);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Material(
        color: cs.surfaceContainerLow,
        child: SafeArea(
          child: ListenableBuilder(
            listenable: prefs,
            builder: (context, _) {
              final byId = {for (final e in entries) e.id: e};
              final groups = groupByCategory(entries);
              final selCat = byId[selectedId]?.category;
              final pins = [for (final id in prefs.pins) if (byId[id] != null) byId[id]!];
              final recent = [for (final id in prefs.recent) if (byId[id] != null && !prefs.isPinned(id)) byId[id]!];
              bool isOpen(String c) => prefs.categoryOpen(c) ?? (c == selCat);
              final allOpen = groups.every((g) => isOpen(g.category));
              Widget tile(PanelEntry e, {bool showCat = false}) => _NavTile(
                    entry: e,
                    selected: e.id == selectedId,
                    pinned: prefs.isPinned(e.id),
                    showCategory: showCat,
                    onTap: () => onSelect(e.id),
                    onPin: () => prefs.togglePin(e.id),
                    trailing: trailing?.call(e),
                    count: count?.call(e),
                  );
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (title.isNotEmpty || actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 8, 6),
                  child: Row(children: [
                    Expanded(
                      child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    ...actions,
                  ]),
                ),
                Padding(padding: const EdgeInsets.fromLTRB(12, 2, 12, 8), child: _SearchButton(onTap: onSearch)),
                Expanded(
                  child: ListView(padding: const EdgeInsets.fromLTRB(8, 0, 8, 20), children: [
                    ...top,
                    if (pins.isNotEmpty) ...[
                      const _SectionLabel('Sabitlenenler', icon: Icons.star_rounded),
                      for (final e in pins) tile(e, showCat: true),
                    ],
                    if (recent.isNotEmpty) ...[
                      const _SectionLabel('Son kullanılanlar', icon: Icons.history_rounded),
                      for (final e in recent) tile(e, showCat: true),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 14, 4, 2),
                      child: Row(children: [
                        Expanded(
                          child: Text('Kategoriler', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant, letterSpacing: .3)),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontSize: 12)),
                          onPressed: () => prefs.setAllCategories(groups.map((g) => g.category), !allOpen),
                          child: Text(allOpen ? 'Tümünü kapat' : 'Tümünü aç'),
                        ),
                      ]),
                    ),
                    for (final g in groups)
                      _CategoryBlock(
                        label: g.category,
                        open: isOpen(g.category),
                        active: g.category == selCat,
                        total: g.entries.length,
                        pending: count == null ? 0 : g.entries.fold<int>(0, (a, e) => a + (count!(e) ?? 0)),
                        onToggle: () => prefs.setCategoryOpen(g.category, !isOpen(g.category)),
                        children: [for (final e in g.entries) tile(e)],
                      ),
                  ]),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cs.outlineVariant)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Icon(Icons.search_rounded, size: 19, color: cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(child: Text('Ara ya da sor…', style: TextStyle(color: cs.onSurfaceVariant))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(border: Border.all(color: cs.outlineVariant), borderRadius: BorderRadius.circular(6)),
              child: Text(panelHotkeyLabel(context), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(children: [
        Icon(icon, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant, letterSpacing: .3)),
      ]),
    );
  }
}

class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock({
    required this.label,
    required this.open,
    required this.active,
    required this.total,
    required this.pending,
    required this.onToggle,
    required this.children,
  });
  final String label;
  final bool open, active;
  final int total, pending;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
        button: true,
        expanded: open,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
            child: Row(children: [
              AnimatedRotation(
                turns: open ? .25 : 0,
                duration: const Duration(milliseconds: 150),
                child: Icon(Icons.chevron_right_rounded, size: 18, color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w800 : FontWeight.w700, color: active ? cs.primary : cs.onSurface),
                ),
              ),
              if (!open && pending > 0) _Pill(pending) else Text('$total', style: TextStyle(fontSize: 11.5, color: cs.outline)),
            ]),
          ),
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: open
            ? Padding(padding: const EdgeInsets.only(left: 6, bottom: 4), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))
            : const SizedBox(width: double.infinity),
      ),
    ]);
  }
}

class _NavTile extends StatefulWidget {
  const _NavTile({
    required this.entry,
    required this.selected,
    required this.pinned,
    required this.onTap,
    required this.onPin,
    this.showCategory = false,
    this.trailing,
    this.count,
  });
  final PanelEntry entry;
  final bool selected, pinned, showCategory;
  final VoidCallback onTap, onPin;
  final Widget? trailing;
  final int? count;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final e = widget.entry;
    final on = widget.selected;
    final fg = on ? cs.onPrimaryContainer : cs.onSurface;
    final showStar = _hover || widget.pinned;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Material(
          color: on ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap,
            // Dokunmatik ekranda: uzun bas → sabitle / kaldır.
            onLongPress: () {
              widget.onPin();
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
                duration: const Duration(seconds: 2),
                content: Text(widget.pinned ? '"${e.title}" sabitlenenlerden çıkarıldı.' : '"${e.title}" sabitlendi.'),
              ));
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
              child: Row(children: [
                Icon(e.icon, size: 19, color: on ? fg : cs.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: fg, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
                    if (widget.showCategory)
                      Text(e.category, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: on ? fg : cs.onSurfaceVariant)),
                  ]),
                ),
                if (widget.trailing != null) widget.trailing!,
                if ((widget.count ?? 0) > 0) ...[const SizedBox(width: 4), _Pill(widget.count!)],
                SizedBox(
                  width: 32,
                  height: 28,
                  child: showStar
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 17,
                          tooltip: widget.pinned ? 'Sabitlemeyi kaldır' : 'Sabitle',
                          onPressed: widget.onPin,
                          icon: Icon(widget.pinned ? Icons.star_rounded : Icons.star_outline_rounded, color: widget.pinned ? Colors.amber.shade700 : cs.outline),
                        )
                      : null,
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.n);
  final int n;

  @override
  Widget build(BuildContext context) {
    final f = HadiColors.brandFill(HadiColors.heyecan);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
      decoration: BoxDecoration(color: f.bg, borderRadius: BorderRadius.circular(99)),
      child: Text(n > 99 ? '99+' : '$n', style: TextStyle(color: f.fg, fontWeight: FontWeight.w800, fontSize: 11.5)),
    );
  }
}
