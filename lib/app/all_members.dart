import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/features/messages/chat_widgets.dart' show ChatAvatar;
import 'package:hadi/panel_ui/crew_ui.dart' show crewCardColor;
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/instant.dart' show InlineError;

import 'crew_api.dart';

/// Pano › Tüm üyeler (3 Kasım 2026; kurucu: "toplam üye sayısı ile sadece üye fotoğrafı, adı ve kullanıcı adı listelensin").
/// Sunucu: crewDash › members (functions/src/crew_members.ts) — yetki sunucuda; satırda yalnız fotoğraf, görünen ad ve
/// kullanıcı adı. Liste 30'luk sayfalarla yüklenir ("Daha fazla göster"); arama sunucuda (kullanıcı adı / ad / rumuz öneki).
class AllMembersSection extends StatefulWidget {
  const AllMembersSection({super.key, this.fetch});

  /// Testler için yükleyici; verilmezse [CrewApi.members].
  final Future<CrewMembersPage> Function({required String sort, Map<String, Object?>? cursor, String? q})? fetch;

  @override
  State<AllMembersSection> createState() => _AllMembersSectionState();
}

class _AllMembersSectionState extends State<AllMembersSection> with AutomaticKeepAliveClientMixin {
  // Pano listesi kaydırılınca bölüm ekrandan çıksa da yüklenen sayfalar korunur.
  @override
  bool get wantKeepAlive => true;

  final _q = TextEditingController();
  Timer? _debounce;
  String _sort = 'new';
  String _query = '';
  int? _total;
  final List<CrewMember> _items = [];
  Map<String, Object?>? _cursor;
  bool _done = false, _loading = false;
  String? _error;

  /// Uçan isteğin kimliği: arama/sıralama değişince eski yanıt yazılmaz.
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<CrewMembersPage> _get({Map<String, Object?>? cursor}) {
    final f = widget.fetch;
    final q = _query.length >= 2 ? _query : null;
    if (f != null) return f(sort: _sort, cursor: cursor, q: q);
    return CrewApi.members(SessionScope.read(context).services, sort: _sort, cursor: cursor, q: q);
  }

  Future<void> _reload() async {
    final my = ++_seq;
    setState(() {
      _items.clear();
      _cursor = null;
      _done = false;
      _loading = true;
      _error = null;
    });
    await _fetch(my, null);
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    final my = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    await _fetch(my, _cursor);
  }

  Future<void> _fetch(int my, Map<String, Object?>? cursor) async {
    try {
      final p = await _get(cursor: cursor);
      if (!mounted || my != _seq) return;
      setState(() {
        if (p.total != null) _total = p.total;
        _items.addAll(p.items);
        _cursor = p.cursor;
        _done = p.done;
      });
    } catch (e) {
      if (mounted && my == _seq) setState(() => _error = InlineError.messageOf(e));
    } finally {
      if (mounted && my == _seq) setState(() => _loading = false);
    }
  }

  void _changed(String v) {
    setState(() {}); // temizle düğmesi
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = v.trim().replaceFirst(RegExp(r'^@+'), '').length >= 2 ? v.trim() : '';
      if (q == _query) return;
      _query = q;
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final text = Theme.of(context).textTheme;
    final searching = _query.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          Text('Tüm üyeler', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          _CountChip(key: const ValueKey('allMembersTotal'), total: _total),
        ],
      ),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, c) {
        final search = TextField(
          controller: _q,
          onChanged: _changed,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: 'Ad, rumuz ya da @kullanıcı adı',
            suffixIcon: _q.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Temizle',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _q.clear();
                      _changed('');
                    },
                  ),
          ),
        );
        final sort = SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'new', label: Text('En yeni')), ButtonSegment(value: 'old', label: Text('En eski'))],
          selected: {_sort},
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          onSelectionChanged: searching
              ? null
              : (v) {
                  _sort = v.first;
                  _reload();
                },
        );
        if (c.maxWidth < 560) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [search, const SizedBox(height: 8), Align(alignment: Alignment.centerLeft, child: sort)]);
        return Row(children: [Expanded(child: search), const SizedBox(width: 12), sort]);
      }),
      const SizedBox(height: 12),
      if (_items.isEmpty && _loading)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
      else if (_items.isEmpty && _error == null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Text(searching ? 'Eşleşen üye yok.' : 'Henüz üye yok.', style: text.bodyMedium?.copyWith(color: HadiColors.ink3)),
        )
      else
        _MemberGrid(items: _items),
      if (_error != null) InlineError(message: _error!, onRetry: _items.isEmpty ? _reload : _more, compact: true),
      if (_items.isNotEmpty && !_done && _error == null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Center(
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _more,
              icon: _loading
                  ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.expand_more_rounded),
              label: Text(_total == null ? 'Daha fazla göster' : 'Daha fazla göster (${fmtCount(_items.length)} / ${fmtCount(_total)})'),
            ),
          ),
        ),
      if (searching && _items.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Aramada en çok 20 sonuç gösterilir.', style: text.bodySmall?.copyWith(color: HadiColors.ink3)),
        ),
    ]);
  }
}

/// 1.284 biçimi (null → —).
String fmtCount(int? v) {
  if (v == null) return '—';
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '$b';
}

class _CountChip extends StatelessWidget {
  const _CountChip({super.key, required this.total});
  final int? total;

  @override
  Widget build(BuildContext context) {
    final f = HadiColors.brandFill(HadiColors.aktivite);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: f.bg, borderRadius: BorderRadius.circular(99)),
      child: Text('${fmtCount(total)} üye', style: TextStyle(color: f.fg, fontWeight: FontWeight.w800, fontSize: 12.5)),
    );
  }
}

/// Kartlar: dar ekranda tek sütun, genişledikçe 4 sütuna kadar.
class _MemberGrid extends StatelessWidget {
  const _MemberGrid({required this.items});
  final List<CrewMember> items;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, cons) {
        final cols = (cons.maxWidth / 260).floor().clamp(1, 4);
        const gap = 8.0;
        final w = (cons.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [for (final m in items) SizedBox(width: w, child: _MemberTile(m: m))]);
      });
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.m});
  final CrewMember m;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
        decoration: BoxDecoration(
          color: crewCardColor(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Row(children: [
          ChatAvatar(name: m.name, photoUrl: m.photo, size: 40, live: false, showPremium: false),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              if (m.handle != null)
                Text('@${m.handle}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: HadiColors.ink3, fontSize: 12.5)),
            ]),
          ),
        ]),
      );
}
