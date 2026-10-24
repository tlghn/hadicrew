// HADİ Crew — Mağaza yorumları ve değerlendirmeleri (24 Ekim 2026): ürüne göre süz, şikâyet sayısı, gizle / geri aç.
// Sunucu: `store` › adminSocial / adminHide (store_social.ts). Gizlenen içerik üyelere görünmez, sayaçlardan düşer.
import 'package:flutter/material.dart';
import 'package:hadi/panel_ui/crew_ui.dart';

import 'package:hadi/core/format.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/data/store_service.dart' show StoreService, StoreReview, StoreComment;
import 'package:hadi/theme/hadi_colors.dart';

import 'store_admin_common.dart';

StoreService _svc(BuildContext context) => StoreService.of(SessionScope.read(context).services);

class StoreReviewsAdminTab extends StatefulWidget {
  const StoreReviewsAdminTab({super.key, this.embedded = true});
  final bool embedded;

  @override
  State<StoreReviewsAdminTab> createState() => _StoreReviewsAdminTabState();
}

class _StoreReviewsAdminTabState extends State<StoreReviewsAdminTab> {
  List<(String, String)> _products = const [];
  String? _product;
  List<StoreReview>? _reviews;
  List<StoreComment>? _comments;
  String? _error;
  bool _reportedOnly = false;
  final _busy = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reviews == null && _error == null) {
      _load();
      _svc(context).adminProducts().then((ps) {
        if (mounted) setState(() => _products = [for (final p in ps) (p.id, p.title)]);
      }, onError: (Object _) {});
    }
  }

  Future<void> _load() async {
    try {
      final r = await _svc(context).adminSocial(productId: _product);
      if (mounted) {
        setState(() {
          _reviews = r.$1;
          _comments = r.$2;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = storeError(e));
    }
  }

  Future<void> _hide(String kind, String id, bool hidden) async {
    setState(() => _busy.add(id));
    try {
      await _svc(context).adminHide(kind, id, hidden);
      if (mounted) storeToast(context, hidden ? 'Gizlendi; üyelere görünmüyor.' : 'Yeniden görünür.');
      await _load();
    } catch (e) {
      if (mounted) storeToast(context, storeError(e));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  String _title(String? id) => _products.where((p) => p.$1 == id).firstOrNull?.$2 ?? (id ?? '');

  @override
  Widget build(BuildContext context) {
    final reviews = [for (final r in _reviews ?? const <StoreReview>[]) r];
    final comments = [for (final c in _comments ?? const <StoreComment>[]) if (!_reportedOnly || c.reports > 0 || c.hidden) c];
    final body = DefaultTabController(
      length: 2,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _product ?? '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Ürün', isDense: true),
                items: [const DropdownMenuItem(value: '', child: Text('Tüm ürünler (son 100)')), for (final p in _products) DropdownMenuItem(value: p.$1, child: Text(p.$2, overflow: TextOverflow.ellipsis))],
                onChanged: (v) {
                  setState(() {
                    _product = (v ?? '').isEmpty ? null : v;
                    _reviews = null;
                  });
                  _load();
                },
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(label: const Text('Şikâyetli'), selected: _reportedOnly, onSelected: (v) => setState(() => _reportedOnly = v)),
          ]),
        ),
        TabBar(tabs: [Tab(text: 'Değerlendirmeler (${reviews.length})'), Tab(text: 'Yorumlar (${comments.length})')]),
        if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: TextStyle(color: HadiColors.text(HadiColors.error)))),
        Expanded(
          child: _reviews == null && _error == null
              ? const CrewMaxWidth(maxWidth: 900, child: Padding(padding: EdgeInsets.only(top: 16), child: CrewLoading()))
              : TabBarView(children: [
                  CrewListView(maxWidth: 900, children: [
                    if (reviews.isEmpty) const CrewEmpty(icon: Icons.star_outline_rounded, title: 'Değerlendirme yok'),
                    for (final r in reviews)
                      _Row(
                        hidden: r.hidden,
                        busy: _busy.contains(r.id),
                        title: '${'★' * r.stars}${'☆' * (5 - r.stars)}  ${r.name}',
                        subtitle: '${_title(r.id.length > r.uid.length + 1 ? r.id.substring(0, r.id.length - r.uid.length - 1) : r.id)} · ${r.at == null ? '' : dateTimeLong(r.at!)}',
                        text: r.text.isEmpty ? '(yalnızca puan)' : r.text,
                        onHide: (v) => _hide('review', r.id, v),
                      ),
                  ]),
                  CrewListView(maxWidth: 900, children: [
                    if (comments.isEmpty) const CrewEmpty(icon: Icons.chat_bubble_outline_rounded, title: 'Yorum yok'),
                    for (final c in comments)
                      _Row(
                        hidden: c.hidden,
                        busy: _busy.contains(c.id),
                        title: c.name,
                        subtitle: '${c.reports > 0 ? '🚩 ${c.reports} şikâyet · ' : ''}${c.at == null ? '' : dateTimeLong(c.at!)}',
                        text: c.text,
                        onHide: (v) => _hide('comment', c.id, v),
                      ),
                  ]),
                ]),
        ),
      ]),
    );
    return widget.embedded ? body : Scaffold(appBar: AppBar(title: const Text('Mağaza yorumları')), body: body);
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.hidden, required this.busy, required this.title, required this.subtitle, required this.text, required this.onHide});
  final bool hidden, busy;
  final String title, subtitle, text;
  final ValueChanged<bool> onHide;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: StoreCard(
          color: hidden ? HadiColors.mist : null,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(subtitle, style: TextStyle(fontSize: 12, color: HadiColors.ink3)),
                const SizedBox(height: 4),
                Text(text, style: TextStyle(color: hidden ? HadiColors.ink3 : HadiColors.ink, decoration: hidden ? TextDecoration.lineThrough : null)),
              ]),
            ),
            busy
                ? const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : TextButton(onPressed: () => onHide(!hidden), child: Text(hidden ? 'Geri aç' : 'Gizle')),
          ]),
        ),
      );
}
