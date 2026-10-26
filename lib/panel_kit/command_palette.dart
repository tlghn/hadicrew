// Panel komut paleti (27 Ekim 2026): üstte arama, Ctrl/Cmd+K. Kurucu Paneli ve HADİ Crew ortak.
//
//  - Yerel arama (panel_search.dart): başlık, kategori, anahtar sözcük, açıklama, alt bölüm; Türkçe normalizasyon, kök/önek,
//    yazım hatası toleransı; eşleşen kısım vurgulu. Başlık dışı eşleşmede neden bulunduğu yazar ("anahtar sözcük: harita").
//  - Sorgu boşken: Sabitlenenler, Son kullanılanlar ve bütün bölümler (kategorili, A–Z).
//  - En altta HER ZAMAN "✨ Yapay zekâya sor: …". Yerel sonuç zayıfsa ve sorgu en az 3 sözcük / 12 karakterse ~600 ms sonra
//    YZ önerileri kendiliğinden gelir (panel_ai.dart). YZ yalnızca başlık önerir; hata/zaman aşımında yerel sonuçlar kalır.
//  - Klavye: ↑ ↓ gez, Enter aç, Esc kapat. Fare/dokunma ile de seçilir; ★ ile sabitlenir.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'panel_ai.dart';
import 'panel_prefs.dart';
import 'panel_search.dart';

bool _paletteOpen = false;

/// Paleti açar; seçilen bölümün id'sini döndürür (vazgeçilirse null).
Future<String?> showPanelPalette(
  BuildContext context, {
  required List<PanelEntry> entries,
  required PanelPrefs prefs,
  PanelAiAsk? askAi,
  String initialQuery = '',
}) async {
  if (_paletteOpen) return null;
  _paletteOpen = true;
  HapticFeedback.selectionClick();
  try {
    return await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .38),
      builder: (_) => PanelPalette(entries: entries, prefs: prefs, askAi: askAi, initialQuery: initialQuery),
    );
  } finally {
    _paletteOpen = false;
  }
}

/// Ctrl+K (Windows/Linux) ya da Cmd+K (macOS) ile [onOpen]. Sayfanın neresinde odak olursa olsun çalışır;
/// üstte başka bir pencere açıkken (ModalRoute güncel değilken) tetiklenmez.
class PanelHotkeys extends StatefulWidget {
  const PanelHotkeys({super.key, required this.onOpen, required this.child});
  final VoidCallback onOpen;
  final Widget child;

  @override
  State<PanelHotkeys> createState() => _PanelHotkeysState();
}

class _PanelHotkeysState extends State<PanelHotkeys> {
  bool _handle(KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.keyK) return false;
    final k = HardwareKeyboard.instance;
    if (!(k.isControlPressed || k.isMetaPressed) || k.isAltPressed || k.isShiftPressed) return false;
    if (!mounted || _paletteOpen) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    widget.onOpen();
    return true;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handle);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handle);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Kısayol ipucu: macOS'ta ⌘K, diğerlerinde Ctrl K.
String panelHotkeyLabel(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.macOS || Theme.of(context).platform == TargetPlatform.iOS ? '⌘K' : 'Ctrl K';

enum _Kind { header, entry, ai, info, loading, ask }

class _Row {
  _Row(this.kind, {this.key = '', this.label, this.entry, this.hit, this.sug, this.onPick});
  final _Kind kind;
  final String key;
  final String? label;
  final PanelEntry? entry;
  final PanelHit? hit;
  final PanelAiSuggestion? sug;
  final VoidCallback? onPick;
  bool get selectable => onPick != null;
}

enum _AiState { idle, loading, done }

class PanelPalette extends StatefulWidget {
  const PanelPalette({super.key, required this.entries, required this.prefs, this.askAi, this.initialQuery = ''});
  final List<PanelEntry> entries;
  final PanelPrefs prefs;
  final PanelAiAsk? askAi;
  final String initialQuery;

  @override
  State<PanelPalette> createState() => _PanelPaletteState();
}

class _PanelPaletteState extends State<PanelPalette> {
  static final Map<String, PanelAiResult> _cache = {};

  late final TextEditingController _ctrl = TextEditingController(text: widget.initialQuery);
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();
  final GlobalKey _selKey = GlobalKey();
  late final PanelSearchIndex _index = PanelSearchIndex(widget.entries);
  late final Map<String, PanelEntry> _byId = {for (final e in widget.entries) e.id: e};

  List<PanelHit> _hits = const [];
  String _q = '';
  String? _sel;
  _AiState _ai = _AiState.idle;
  String _aiFor = '';
  PanelAiResult? _aiRes;
  Timer? _debounce;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    widget.prefs.addListener(_onPrefs);
    _onChanged(_ctrl.text);
  }

  @override
  void dispose() {
    widget.prefs.removeListener(_onPrefs);
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onPrefs() {
    if (mounted) setState(() {});
  }

  String _cacheKey(String q) => '${widget.entries.length}|${q.trim().toLowerCase()}';

  void _onChanged(String raw) {
    final q = raw.trim();
    _debounce?.cancel();
    setState(() {
      _q = q;
      _hits = q.isEmpty ? const [] : _index.search(q);
      _sel = null;
      if (q.isEmpty) {
        _ai = _AiState.idle;
        _aiRes = null;
        return;
      }
      final cached = _cache[_cacheKey(q)];
      if (cached != null) {
        _ai = _AiState.done;
        _aiFor = q;
        _aiRes = cached;
        return;
      }
      if (_aiFor != q) {
        _ai = _AiState.idle;
        _aiRes = null;
      }
    });
    if (q.isNotEmpty && widget.askAi != null && _cache[_cacheKey(q)] == null && aiEligible(q) && weakResults(_hits)) {
      _debounce = Timer(const Duration(milliseconds: 600), () => _ask(q));
    }
  }

  Future<void> _ask(String q) async {
    final ask = widget.askAi;
    if (ask == null || q.isEmpty) return;
    _debounce?.cancel();
    final cached = _cache[_cacheKey(q)];
    if (cached != null && cached.ok) {
      setState(() {
        _ai = _AiState.done;
        _aiFor = q;
        _aiRes = cached;
      });
      return;
    }
    final seq = ++_seq;
    setState(() {
      _ai = _AiState.loading;
      _aiFor = q;
      _aiRes = null;
    });
    PanelAiResult r;
    try {
      r = await ask(q, widget.entries);
    } catch (_) {
      r = const PanelAiResult(error: 'YZ şu an yanıt veremedi');
    }
    if (!mounted || seq != _seq || _q != q) return;
    if (r.ok) _cache[_cacheKey(q)] = r;
    setState(() {
      _ai = _AiState.done;
      _aiRes = r;
      // Yerel sonuç yoksa ilk öneri seçili gelsin (Enter ile açılır).
      if (_hits.isEmpty && r.items.isNotEmpty) _sel = 'ai:${r.items.first.id}';
    });
  }

  bool _done = false;
  DateTime _lastActivate = DateTime(2000);

  void _pick(String id) {
    if (_done) return;
    _done = true;
    Navigator.of(context).pop(id);
  }

  /// Enter: seçili satırı çalıştır (kısayol ve klavyenin "ara" eylemi ikisi birden gelirse bir kez).
  void _activate() {
    final now = DateTime.now();
    if (now.difference(_lastActivate) < const Duration(milliseconds: 250)) return;
    _lastActivate = now;
    for (final r in _rows()) {
      if (r.selectable && r.key == _sel) {
        r.onPick!();
        return;
      }
    }
  }

  List<_Row> _rows() {
    final rows = <_Row>[];
    _Row entryRow(PanelEntry e, String prefix, {PanelHit? hit}) =>
        _Row(_Kind.entry, key: '$prefix:${e.id}', entry: e, hit: hit, onPick: () => _pick(e.id));
    if (_q.isEmpty) {
      final pins = [for (final id in widget.prefs.pins) if (_byId[id] != null) _byId[id]!];
      final recent = [for (final id in widget.prefs.recent) if (_byId[id] != null && !widget.prefs.isPinned(id)) _byId[id]!];
      if (pins.isNotEmpty) {
        rows.add(_Row(_Kind.header, label: 'Sabitlenenler'));
        rows.addAll(pins.map((e) => entryRow(e, 'pin')));
      }
      if (recent.isNotEmpty) {
        rows.add(_Row(_Kind.header, label: 'Son kullanılanlar'));
        rows.addAll(recent.map((e) => entryRow(e, 'recent')));
      }
      for (final g in groupByCategory(widget.entries)) {
        rows.add(_Row(_Kind.header, label: g.category));
        rows.addAll(g.entries.map((e) => entryRow(e, 'all')));
      }
      return rows;
    }
    if (_hits.isNotEmpty) {
      rows.add(_Row(_Kind.header, label: 'Bölümler'));
      rows.addAll(_hits.map((h) => entryRow(h.entry, 'hit', hit: h)));
    } else {
      rows.add(_Row(_Kind.info, label: 'Başlıklarda "$_q" yok. Yapay zekâ ne demek istediğini anlayabilir.'));
    }
    if (widget.askAi != null) {
      if (_ai == _AiState.loading && _aiFor == _q) {
        rows.add(_Row(_Kind.header, label: '✨ Yapay zekâ önerileri'));
        rows.add(_Row(_Kind.loading, label: 'Ne demek istediğin anlaşılıyor…'));
      } else if (_ai == _AiState.done && _aiFor == _q && _aiRes != null) {
        final r = _aiRes!;
        rows.add(_Row(_Kind.header, label: '✨ Yapay zekâ önerileri'));
        if (!r.ok) {
          rows.add(_Row(_Kind.info, label: r.error));
        } else if (r.items.isEmpty) {
          rows.add(_Row(_Kind.info, label: 'Yapay zekâ bu isteğe uyan bir bölüm bulamadı.'));
        } else {
          if (r.intent != null) rows.add(_Row(_Kind.info, label: 'Anlaşılan: ${r.intent}'));
          for (final s in r.items) {
            final e = _byId[s.id];
            if (e != null) rows.add(_Row(_Kind.ai, key: 'ai:${e.id}', entry: e, sug: s, onPick: () => _pick(e.id)));
          }
        }
      }
      rows.add(_Row(_Kind.ask, key: 'ask', label: _q, onPick: () => _ask(_q)));
    }
    return rows;
  }

  void _move(List<_Row> rows, int d) {
    final sel = [for (final r in rows) if (r.selectable) r.key];
    if (sel.isEmpty) return;
    final i = _sel == null ? -1 : sel.indexOf(_sel!);
    final n = i < 0 ? (d > 0 ? 0 : sel.length - 1) : (i + d).clamp(0, sel.length - 1);
    setState(() => _sel = sel[n]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _selKey.currentContext;
      if (c != null) {
        Scrollable.ensureVisible(c,
            duration: const Duration(milliseconds: 90),
            alignmentPolicy: d > 0 ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd : ScrollPositionAlignmentPolicy.keepVisibleAtStart);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    final selectable = [for (final r in rows) if (r.selectable) r.key];
    if (_sel == null || !selectable.contains(_sel)) _sel = selectable.isEmpty ? null : selectable.first;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 640;
    final cs = Theme.of(context).colorScheme;

    final field = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(rows, 1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(rows, -1),
        const SingleActivator(LogicalKeyboardKey.pageDown): () => _move(rows, 6),
        const SingleActivator(LogicalKeyboardKey.pageUp): () => _move(rows, -6),
        const SingleActivator(LogicalKeyboardKey.enter): _activate,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _activate,
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
      },
      child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        autofocus: true,
        onChanged: _onChanged,
        onSubmitted: (_) {
          _activate();
          _focus.requestFocus();
        },
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 16.5),
        decoration: InputDecoration(
          hintText: 'Bölüm ara ya da ne yapmak istediğini yaz…',
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          suffixIcon: _ctrl.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Temizle',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () {
                    _ctrl.clear();
                    _onChanged('');
                    _focus.requestFocus();
                  },
                ),
        ),
      ),
    );

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
      child: Row(children: [
        if (!wide)
          IconButton(tooltip: 'Kapat', icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).maybePop())
        else
          Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Icon(Icons.search_rounded, color: cs.onSurfaceVariant)),
        Expanded(child: field),
        if (wide) const _Kbd('Esc'),
      ]),
    );

    final list = rows.isEmpty
        ? const SizedBox.shrink()
        : ListView.builder(
            controller: _scroll,
            shrinkWrap: wide,
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final r = rows[i];
              final selected = r.selectable && r.key == _sel;
              final w = _RowView(
                row: r,
                selected: selected,
                prefs: widget.prefs,
                onHover: r.selectable ? () => setState(() => _sel = r.key) : null,
              );
              return selected ? KeyedSubtree(key: _selKey, child: w) : w;
            },
          );

    final body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      Divider(height: 1, color: cs.outlineVariant),
      Flexible(child: list),
      if (wide) ...[
        Divider(height: 1, color: cs.outlineVariant),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: DefaultTextStyle.merge(
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            child: const Wrap(spacing: 14, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _Hint(keys: ['↑', '↓'], label: 'gez'),
              _Hint(keys: ['Enter'], label: 'aç'),
              _Hint(keys: ['Esc'], label: 'kapat'),
              _Hint(keys: ['★'], label: 'sabitle'),
            ]),
          ),
        ),
      ],
    ]);

    if (!wide) {
      return Dialog.fullscreen(child: SafeArea(child: body));
    }
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: EdgeInsets.fromLTRB(24, size.height > 700 ? 80 : 24, 24, 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 680, maxHeight: size.height * .72), child: body),
    );
  }
}

class _RowView extends StatelessWidget {
  const _RowView({required this.row, required this.selected, required this.prefs, this.onHover});
  final _Row row;
  final bool selected;
  final PanelPrefs prefs;
  final VoidCallback? onHover;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    switch (row.kind) {
      case _Kind.header:
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Text(row.label!, style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800, letterSpacing: .2)),
        );
      case _Kind.info:
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Text(row.label ?? '', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.35)),
        );
      case _Kind.loading:
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Text(row.label ?? '', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ]),
        );
      case _Kind.ask:
        return _Tile(
          selected: selected,
          onTap: row.onPick!,
          onHover: onHover,
          leading: Icon(Icons.auto_awesome_rounded, color: cs.tertiary),
          title: Text.rich(TextSpan(children: [
            const TextSpan(text: '✨ Yapay zekâya sor: ', style: TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: '“${row.label}”'),
          ]), maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: const Text('Niyetini anlayıp olası bölümleri gösterir; hiçbir işlem yapmaz.'),
        );
      case _Kind.entry:
      case _Kind.ai:
        final e = row.entry!;
        final h = row.hit;
        final s = row.sug;
        final base = DefaultTextStyle.of(context).style;
        final mark = TextStyle(fontWeight: FontWeight.w800, backgroundColor: cs.primaryContainer.withValues(alpha: .7), color: cs.onPrimaryContainer);
        Widget sub;
        if (s != null) {
          sub = Text.rich(
            TextSpan(children: [
              if (s.section != null) TextSpan(text: '› ${s.section}  ', style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary)),
              TextSpan(text: s.reason.isEmpty ? e.category : s.reason),
            ]),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          );
        } else {
          final desc = e.description.isEmpty ? e.category : e.description;
          sub = Text.rich(
            TextSpan(children: [
              if (h?.via != null) TextSpan(text: '“${h!.via}” ile bulundu · ', style: TextStyle(fontStyle: FontStyle.italic, color: cs.primary)),
              ...highlightSpans(desc, e.description.isEmpty ? const [] : (h?.descRanges ?? const []), base, mark),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }
        return _Tile(
          selected: selected,
          onTap: row.onPick!,
          onHover: onHover,
          leading: Icon(e.icon, color: s != null ? cs.tertiary : cs.onSurfaceVariant),
          title: Row(children: [
            Flexible(
              child: Text.rich(
                TextSpan(children: highlightSpans(e.title, h?.titleRanges ?? const [], const TextStyle(fontWeight: FontWeight.w700), mark)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _CategoryChip(e.category),
          ]),
          subtitle: DefaultTextStyle.merge(style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5), child: sub),
          trailing: ListenableBuilder(
            listenable: prefs,
            builder: (context, _) {
              final on = prefs.isPinned(e.id);
              return IconButton(
                tooltip: on ? 'Sabitlemeyi kaldır' : 'Sabitle',
                visualDensity: VisualDensity.compact,
                icon: Icon(on ? Icons.star_rounded : Icons.star_outline_rounded, size: 20, color: on ? Colors.amber.shade700 : cs.outline),
                onPressed: () => prefs.togglePin(e.id),
              );
            },
          ),
        );
    }
  }
}

/// [text] içinde [ranges] aralıklarını [mark] ile vurgular.
List<InlineSpan> highlightSpans(String text, List<TextRange2> ranges, TextStyle base, TextStyle mark) {
  if (ranges.isEmpty) return [TextSpan(text: text, style: base)];
  final out = <InlineSpan>[];
  var at = 0;
  for (final r in ranges) {
    final s = r.start.clamp(0, text.length), e = r.end.clamp(0, text.length);
    if (s < at || e <= s) continue;
    if (s > at) out.add(TextSpan(text: text.substring(at, s), style: base));
    out.add(TextSpan(text: text.substring(s, e), style: base.merge(mark)));
    at = e;
  }
  if (at < text.length) out.add(TextSpan(text: text.substring(at), style: base));
  return out;
}

class _Tile extends StatelessWidget {
  const _Tile({required this.selected, required this.onTap, this.onHover, required this.leading, required this.title, this.subtitle, this.trailing});
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onHover;
  final Widget leading, title;
  final Widget? subtitle, trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: onHover == null ? null : (_) => onHover!(),
      child: Material(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(children: [
              IconTheme.merge(data: const IconThemeData(size: 22), child: leading),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  title,
                  if (subtitle != null) ...[const SizedBox(height: 2), subtitle!],
                ]),
              ),
              if (trailing != null) trailing! else const SizedBox(width: 8),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(99)),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
    );
  }
}

class _Kbd extends StatelessWidget {
  const _Kbd(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: cs.outlineVariant), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.keys, required this.label});
  final List<String> keys;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (final k in keys) ...[_Kbd(k), const SizedBox(width: 3)],
        const SizedBox(width: 3),
        Text(label),
      ]);
}
