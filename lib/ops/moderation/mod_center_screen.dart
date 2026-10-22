// Moderasyon merkezi: Bloklar · İtirazlar · Kayıtlar · İadeler (yalnızca kurucular).
// Giriş: Profil ayarları › Yönetim › Moderasyon merkezi ve kurucu paneli › Moderasyon.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hadi/core/session.dart';
import 'package:hadi/data/models.dart' show AppFailure;
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/reason_dialog.dart';
import 'package:hadi/widgets/skeleton.dart';
import 'package:hadi/features/moderation/ai_appeals_tab.dart' show AiAppealsTab;
import 'package:hadi/features/moderation/mod_api.dart';
import 'mod_sheet.dart' show ModLogList, openModSheet;

class ModCenterScreen extends StatelessWidget {
  const ModCenterScreen({super.key, this.embedded = false});

  /// Kurucu paneli sekmesi içinde (kendi uygulama çubuğu yok).
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    if (!s.canModerate) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Bu bölüm yalnızca yönetime açık.')));
    }
    final founder = s.isFounder;
    final tabs = [
      const Tab(text: 'Bloklar'),
      const Tab(text: 'İtirazlar'),
      const Tab(text: 'YZ itirazları'),
      const Tab(text: 'Kayıtlar'),
      if (founder) const Tab(text: 'İadeler'),
    ];
    final views = <Widget>[
      const _BlocksTab(),
      const _AppealsTab(),
      const AiAppealsTab(),
      const ModLogList(),
      if (founder) const _RefundsTab(),
    ];
    final bar = TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: tabs);
    return DefaultTabController(
      length: tabs.length,
      child: embedded
          ? Column(children: [Material(color: Theme.of(context).colorScheme.surface, child: bar), Expanded(child: TabBarView(children: views))])
          : Scaffold(appBar: AppBar(title: const Text('Moderasyon merkezi'), bottom: bar), body: TabBarView(children: views)),
    );
  }
}

Widget _skeletons() => ListView(children: List.generate(6, (_) => const ListTileSkeleton()));

Widget _empty(String t) => ListView(children: [
      const SizedBox(height: 80),
      Center(child: Text(t, style: TextStyle(color: HadiColors.ink3, fontSize: 15))),
    ]);

void _snack(BuildContext context, String m) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m)));

// ------------------------------------------------------------------ bloklar

class _BlocksTab extends StatefulWidget {
  const _BlocksTab();
  @override
  State<_BlocksTab> createState() => _BlocksTabState();
}

class _BlocksTabState extends State<_BlocksTab> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>>? _items;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ModApi.call('blocks', {'limit': 200});
      if (mounted) setState(() => _items = ModApi.list(d['items']));
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _unblock(Map<String, dynamic> x) async {
    final reason = await askReason(context, title: 'Blokeyi kaldır', message: '${x['name'] ?? 'Üye'} uygulamaya yeniden erişebilecek.', confirm: 'Kaldır');
    if (reason == null || !mounted) return;
    try {
      await ModApi.call('unblock', {'uid': x['uid'], 'reason': reason});
      HapticFeedback.mediumImpact();
      if (mounted) _snack(context, 'Bloke kaldırıldı.');
      await _load();
    } on AppFailure catch (e) {
      if (mounted) _snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null) return Center(child: Text(_error!));
    final items = _items;
    return RefreshIndicator(
      onRefresh: _load,
      child: items == null
          ? _skeletons()
          : items.isEmpty
              ? _empty('Bloklu hesap yok.')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final x = items[i];
                    final until = ModApi.time(x['until']);
                    final photo = '${x['photo'] ?? ''}';
                    return Container(
                      decoration: BoxDecoration(color: HadiColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: HadiColors.line)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: HadiColors.mist,
                          backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                          child: photo.isEmpty ? Icon(Icons.person_rounded, color: HadiColors.ink3) : null,
                        ),
                        title: Text('${x['name'] ?? 'Üye'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text(
                          '${until == null ? 'Süresiz' : '${modDate(until)}\'e kadar · ${modLeft(until.difference(DateTime.now()))} kaldı'}\n'
                          '${x['reason'] ?? ''}\n${x['byName'] ?? ''} (${x['byRole'] ?? ''}) · ${modDate(ModApi.time(x['at']))}',
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: true,
                        onTap: () => openModSheet(context, uid: '${x['uid']}', name: '${x['name'] ?? 'Üye'}').then((_) => _load()),
                        trailing: IconButton(tooltip: 'Blokeyi kaldır', onPressed: () => _unblock(x), icon: const Icon(Icons.lock_open_rounded, color: HadiColors.dostluk)),
                      ),
                    );
                  },
                ),
    );
  }
}

// ------------------------------------------------------------------ itirazlar

class _AppealsTab extends StatefulWidget {
  const _AppealsTab();
  @override
  State<_AppealsTab> createState() => _AppealsTabState();
}

class _AppealsTabState extends State<_AppealsTab> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>>? _items;
  String? _error;
  bool _all = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ModApi.call('appeals', {'status': _all ? 'all' : 'open'});
      if (mounted) setState(() => _items = ModApi.list(d['items']));
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _decide(Map<String, dynamic> x, bool accept) async {
    final note = await showDialog<String>(context: context, builder: (_) => _NoteDialog(accept: accept, name: '${x['name'] ?? 'Üye'}'));
    if (note == null || !mounted) return;
    try {
      await ModApi.call('appealDecide', {'id': x['id'], 'decision': accept ? 'accept' : 'reject', 'note': note});
      HapticFeedback.mediumImpact();
      if (mounted) _snack(context, accept ? 'İtiraz kabul edildi; bloke kaldırıldı.' : 'İtiraz reddedildi.');
      await _load();
    } on AppFailure catch (e) {
      if (mounted) _snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null) return Center(child: Text(_error!));
    final items = _items;
    return RefreshIndicator(
      onRefresh: _load,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(children: [
            ChoiceChip(label: const Text('Bekleyen'), selected: !_all, onSelected: (_) => setState(() {
                  _all = false;
                  _items = null;
                  _load();
                })),
            const SizedBox(width: 6),
            ChoiceChip(label: const Text('Tümü'), selected: _all, onSelected: (_) => setState(() {
                  _all = true;
                  _items = null;
                  _load();
                })),
          ]),
        ),
        Expanded(
          child: items == null
              ? _skeletons()
              : items.isEmpty
                  ? _empty(_all ? 'İtiraz yok.' : 'Bekleyen itiraz yok.')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _AppealCard(item: items[i], onDecide: (a) => _decide(items[i], a)),
                    ),
        ),
      ]),
    );
  }
}

class _AppealCard extends StatelessWidget {
  const _AppealCard({required this.item, required this.onDecide});
  final Map<String, dynamic> item;
  final ValueChanged<bool> onDecide;

  @override
  Widget build(BuildContext context) {
    final x = item;
    final st = '${x['status'] ?? 'open'}';
    final files = ModApi.list(x['files']);
    final until = ModApi.time(x['blockUntil']);
    final stColor = st == 'accepted' ? HadiColors.dostluk : (st == 'rejected' ? HadiColors.error : HadiColors.heyecan);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: HadiColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: HadiColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: InkWell(
              onTap: () => openModSheet(context, uid: '${x['uid']}', name: '${x['name'] ?? 'Üye'}'),
              child: Text('${x['name'] ?? 'Üye'}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5)),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: stColor.withValues(alpha: .12), borderRadius: BorderRadius.circular(99)),
            child: Text(switch (st) { 'accepted' => 'Kabul', 'rejected' => 'Ret', _ => 'Bekliyor' },
                style: TextStyle(color: Color.lerp(stColor, HadiColors.ink, .3), fontWeight: FontWeight.w800, fontSize: 12)),
          ),
        ]),
        Text(modDate(ModApi.time(x['at'])), style: TextStyle(color: HadiColors.ink3, fontSize: 12.5)),
        const SizedBox(height: 8),
        Text('Bloke nedeni: ${x['blockReason'] ?? '—'} · ${until == null ? 'süresiz' : '${modDate(until)}\'e kadar'}',
            style: TextStyle(color: HadiColors.ink2, fontSize: 13)),
        const SizedBox(height: 8),
        Text('${x['text'] ?? ''}', style: TextStyle(color: HadiColors.ink, height: 1.4)),
        if (files.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final f in files)
              ActionChip(
                avatar: Icon('${f['name']}'.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf_rounded : Icons.image_rounded, size: 18),
                label: Text('${f['name'] ?? 'Belge'}', overflow: TextOverflow.ellipsis),
                onPressed: () {
                  final u = Uri.tryParse('${f['url'] ?? ''}');
                  if (u != null) launchUrl(u, mode: LaunchMode.externalApplication);
                },
              ),
          ]),
        ],
        if ('${x['note'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Karar notu: ${x['note']}', style: TextStyle(color: HadiColors.ink2, fontStyle: FontStyle.italic)),
        ],
        if (st == 'open') ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => onDecide(false),
                style: OutlinedButton.styleFrom(foregroundColor: HadiColors.text(HadiColors.error)),
                child: const Text('Reddet'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => onDecide(true),
                style: FilledButton.styleFrom(backgroundColor: HadiColors.fillForWhite(HadiColors.dostluk), foregroundColor: Colors.white),
                child: const Text('Kabul et · blokeyi kaldır'),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.accept, required this.name});
  final bool accept;
  final String name;
  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _c = TextEditingController();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(widget.accept ? 'İtirazı kabul et' : 'İtirazı reddet'),
        content: TextField(
          controller: _c,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          maxLength: 600,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: 'Not (${widget.name} görür)', helperText: 'En az 5 karakter; kayda geçer.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: HadiColors.fillForWhite(widget.accept ? HadiColors.dostluk : HadiColors.error), foregroundColor: Colors.white),
            onPressed: _c.text.trim().length >= 5 ? () => Navigator.pop(context, _c.text.trim()) : null,
            child: Text(widget.accept ? 'Kabul et' : 'Reddet'),
          ),
        ],
      );
}

// ------------------------------------------------------------------ iadeler (kurucular)

class _RefundsTab extends StatefulWidget {
  const _RefundsTab();
  @override
  State<_RefundsTab> createState() => _RefundsTabState();
}

class _RefundsTabState extends State<_RefundsTab> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>>? _items;
  String? _error;
  bool _all = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ModApi.call('refunds', {'status': _all ? 'all' : 'pending'});
      if (mounted) setState(() => _items = ModApi.list(d['items']));
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _mark(Map<String, dynamic> x, String status) async {
    final note = await askReason(
      context,
      title: status == 'paid' ? 'Ödendi olarak işaretle' : 'Talebi reddet',
      message: '${x['name'] ?? 'Üye'} · ${x['purchasedHp']}💎',
      confirm: status == 'paid' ? 'Ödendi' : 'Reddet',
      danger: status != 'paid',
      hint: status == 'paid' ? 'Örn. "EFT yapıldı, dekont no 12345."' : 'Neden?',
    );
    if (note == null || !mounted) return;
    try {
      await ModApi.call('refundMark', {'id': x['id'], 'status': status, 'note': note});
      HapticFeedback.mediumImpact();
      await _load();
    } on AppFailure catch (e) {
      if (mounted) _snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null) return Center(child: Text(_error!));
    final items = _items;
    return RefreshIndicator(
      onRefresh: _load,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(children: [
            ChoiceChip(label: const Text('Bekleyen'), selected: !_all, onSelected: (_) => setState(() {
                  _all = false;
                  _items = null;
                  _load();
                })),
            const SizedBox(width: 6),
            ChoiceChip(label: const Text('Tümü'), selected: _all, onSelected: (_) => setState(() {
                  _all = true;
                  _items = null;
                  _load();
                })),
          ]),
        ),
        Expanded(
          child: items == null
              ? _skeletons()
              : items.isEmpty
                  ? _empty('İade talebi yok.')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final x = items[i];
                        final st = '${x['status'] ?? 'pending'}';
                        final iban = '${x['iban'] ?? x['ibanMasked'] ?? ''}';
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: HadiColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: HadiColors.line)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text('${x['name'] ?? 'Üye'}', style: const TextStyle(fontWeight: FontWeight.w900))),
                              Text('${x['purchasedHp'] ?? 0}💎', style: TextStyle(fontWeight: FontWeight.w900, color: HadiColors.text(HadiColors.heyecan))),
                            ]),
                            Text(modDate(ModApi.time(x['at'])), style: TextStyle(color: HadiColors.ink3, fontSize: 12.5)),
                            const SizedBox(height: 8),
                            Text('Hesap sahibi: ${x['holder'] ?? '—'}'),
                            Text('Banka: ${x['bank'] ?? '—'}'),
                            Row(children: [
                              Expanded(child: SelectableText('IBAN: $iban', style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]))),
                              if (x['iban'] != null)
                                IconButton(
                                  tooltip: 'IBAN\'ı kopyala',
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: '${x['iban']}'));
                                    _snack(context, 'IBAN kopyalandı.');
                                  },
                                  icon: const Icon(Icons.copy_rounded, size: 18),
                                ),
                            ]),
                            if ('${x['note'] ?? ''}'.isNotEmpty) Text('Not: ${x['note']}', style: TextStyle(color: HadiColors.ink2)),
                            if (st == 'pending') ...[
                              const SizedBox(height: 8),
                              Row(children: [
                                Expanded(child: OutlinedButton(onPressed: () => _mark(x, 'rejected'), child: const Text('Reddet'))),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(backgroundColor: HadiColors.fillForWhite(HadiColors.dostluk), foregroundColor: Colors.white),
                                    onPressed: () => _mark(x, 'paid'),
                                    child: const Text('Ödendi'),
                                  ),
                                ),
                              ]),
                            ] else
                              Text(st == 'paid' ? '✅ Ödendi' : '❌ Reddedildi', style: const TextStyle(fontWeight: FontWeight.w800)),
                          ]),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
