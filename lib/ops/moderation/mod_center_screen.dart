// Moderasyon merkezi: Bloklu hesaplar (+ geçmiş) · İtirazlar · Kayıtlar · İadeler (yalnızca kurucular).
// 26 Ekim 2026: "Hesabı blokla" yalnızca ana kurucu; kaldırma kuralı (mode) sunucuda (account_mod.ts).
// Giriş: Profil ayarları › Yönetim › Moderasyon merkezi ve kurucu paneli › Moderasyon.

import 'dart:async';

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
import 'package:hadi/features/moderation/account_block_sheet.dart' show blockModeFrom, blockModeLabel, blockModeWho, openAccountUnblock, openBlockEditSheet;
import 'mod_sheet.dart' show ModLogList, openModSheet;
import 'package:hadi/core/ui_gate.dart';

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
      const Tab(text: 'Bloklu hesaplar'),
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
  List<Map<String, dynamic>>? _items, _history;
  String? _error;
  bool _showHistory = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (_showHistory) {
        final d = await ModApi.call('blockHistory');
        if (mounted) setState(() => _history = ModApi.list(d['items']));
      } else {
        final d = await ModApi.call('blocks', {'limit': 200});
        if (mounted) setState(() => _items = ModApi.list(d['items']));
      }
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _unblock(Map<String, dynamic> x) async {
    if (await openAccountUnblock(context, uid: '${x['uid']}', name: '${x['name'] ?? 'Üye'}', mode: blockModeFrom(x['mode']))) await _load();
  }

  Future<void> _edit(Map<String, dynamic> x) async {
    if (await openBlockEditSheet(context, uid: '${x['uid']}', name: '${x['name'] ?? 'Üye'}', block: x)) await _load();
  }

  void _switch(bool history) => setState(() {
        _showHistory = history;
        _error = null;
        _load();
      });

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final items = _showHistory ? _history : _items;
    return RefreshIndicator(
      onRefresh: _load,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(children: [
            ChoiceChip(label: const Text('Aktif'), selected: !_showHistory, onSelected: (_) => _switch(false)),
            const SizedBox(width: 6),
            ChoiceChip(label: const Text('Geçmiş'), selected: _showHistory, onSelected: (_) => _switch(true)),
          ]),
        ),
        Expanded(
          child: _error != null
              ? Center(child: Text(_error!))
              : items == null
                  ? _skeletons()
                  : items.isEmpty
                      ? _empty(_showHistory ? 'Kayıt yok.' : 'Bloklu hesap yok.')
                      : _showHistory
                          ? ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                              itemCount: items.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final x = items[i];
                                final until = ModApi.time(x['until']);
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(_histIcon('${x['action']}'), color: HadiColors.ink2),
                                  title: Text('${modActionLabel('${x['action']}')} · ${x['targetName'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text([
                                    modDate(ModApi.time(x['at'])),
                                    if ('${x['actorName'] ?? ''}'.isNotEmpty) '${x['actorName']} (${x['actorRole'] ?? ''})',
                                    if (x['kind'] != null) blockModeLabel(blockModeFrom(x['kind'])),
                                    if (until != null) '${modDate(until)}\'e kadar',
                                    if ('${x['reason'] ?? ''}'.isNotEmpty) '${x['reason']}',
                                  ].join(' · ')),
                                  onTap: x['targetUid'] == null ? null : () => openModSheet(context, uid: '${x['targetUid']}', name: '${x['targetName'] ?? 'Üye'}'),
                                );
                              },
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                              itemCount: items.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 10),
                              itemBuilder: (context, i) => _BlockCard(
                                item: items[i],
                                onOpen: () => openModSheet(context, uid: '${items[i]['uid']}', name: '${items[i]['name'] ?? 'Üye'}').then((_) => _load()),
                                onLift: () => _unblock(items[i]),
                                onEdit: () => _edit(items[i]),
                              ),
                            ),
        ),
      ]),
    );
  }

  static IconData _histIcon(String a) => switch (a) {
        'block' => Icons.block_rounded,
        'block.edit' => Icons.edit_calendar_rounded,
        'unblock' || 'appeal.accept' => Icons.lock_open_rounded,
        'expired' => Icons.timer_off_rounded,
        _ => Icons.gavel_rounded,
      };
}

/// Aktif blok kartı: kural, geri sayım, kim, neden, iç not, itiraz; Kaldır · Süreyi değiştir (yetkiye göre).
class _BlockCard extends StatefulWidget {
  const _BlockCard({required this.item, required this.onOpen, required this.onLift, required this.onEdit});
  final Map<String, dynamic> item;
  final VoidCallback onOpen, onLift, onEdit;
  @override
  State<_BlockCard> createState() => _BlockCardState();
}

class _BlockCardState extends State<_BlockCard> {
  Timer? _t;
  @override
  void initState() {
    super.initState();
    if (widget.item['until'] != null) _t = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final x = widget.item;
    final until = ModApi.time(x['until']);
    final mode = blockModeFrom(x['mode']);
    final photo = '${x['photo'] ?? ''}';
    final appeal = x['appealStatus'] ?? x['appeal'];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: HadiColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: HadiColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: widget.onOpen,
          child: Row(children: [
            CircleAvatar(
              backgroundColor: HadiColors.mist,
              backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
              child: photo.isEmpty ? Icon(Icons.person_rounded, color: HadiColors.ink3) : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${x['name'] ?? 'Üye'}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5)),
                if ('${x['username'] ?? ''}'.isNotEmpty) Text('@${x['username']}', style: TextStyle(color: HadiColors.ink3, fontSize: 12.5)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: HadiColors.error.withValues(alpha: .1), borderRadius: BorderRadius.circular(99)),
              child: Text(blockModeLabel(mode), style: TextStyle(color: HadiColors.text(HadiColors.error), fontWeight: FontWeight.w800, fontSize: 12)),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Text(
          until == null ? 'Süresiz' : '${modDate(until)}\'e kadar · ${modLeft(until.difference(DateTime.now()))} kaldı',
          style: TextStyle(color: HadiColors.ink, fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        const SizedBox(height: 4),
        Text('Neden (üye görür): ${x['reason'] ?? ''}', style: TextStyle(color: HadiColors.ink2, height: 1.35)),
        if ('${x['internal'] ?? ''}'.isNotEmpty) Text('İç not: ${x['internal']}', style: TextStyle(color: HadiColors.ink2, height: 1.35)),
        Text(
          [if ('${x['byName'] ?? ''}'.isNotEmpty) '${x['byName']} (${x['byRole'] ?? ''})', modDate(ModApi.time(x['at'])), if (appeal != null) 'İtiraz: ${_appealLabel('$appeal')}'].join(' · '),
          style: TextStyle(color: HadiColors.ink3, fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (x['canLift'] == true)
            FilledButton.icon(
              onPressed: widget.onLift,
              style: FilledButton.styleFrom(backgroundColor: HadiColors.fillForWhite(HadiColors.dostluk), foregroundColor: Colors.white),
              icon: const Icon(Icons.lock_open_rounded, size: 18),
              label: const Text('Kaldır'),
            )
          else
            Text(blockModeWho(mode), style: TextStyle(color: HadiColors.ink3, fontSize: 12.5)),
          if (x['canEdit'] == true)
            OutlinedButton.icon(onPressed: widget.onEdit, icon: const Icon(Icons.edit_calendar_rounded, size: 18), label: const Text('Süreyi değiştir')),
        ]),
      ]),
    );
  }
}

String _appealLabel(String s) => switch (s) {
      'open' => 'inceleniyor',
      'info' => 'ek bilgi bekleniyor',
      'accepted' => 'kabul',
      'rejected' => 'ret',
      'closed' => 'kapandı',
      _ => s,
    };

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

  /// decision: accept (bloğu kaldırır — kaldırma kuralına uyar) · reject (üyeye yanıt zorunlu) · info (üyeye soru).
  Future<void> _decide(Map<String, dynamic> x, String decision) async {
    final note = await uiOnce(context, () => showDialog<String>(context: context, builder: (_) => _NoteDialog(decision: decision, name: '${x['name'] ?? 'Üye'}')));
    if (note == null || !mounted) return;
    try {
      await ModApi.call('appealDecide', {'id': x['id'], 'decision': decision, 'note': note});
      HapticFeedback.mediumImpact();
      if (mounted) {
        _snack(context, switch (decision) { 'accept' => 'İtiraz kabul edildi; blok kaldırıldı.', 'info' => 'Soru üyeye iletildi.', _ => 'İtiraz reddedildi; üye 24 saat sonra yeniden itiraz edebilir.' });
      }
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
                      itemBuilder: (context, i) => _AppealCard(item: items[i], onDecide: (d) => _decide(items[i], d)),
                    ),
        ),
      ]),
    );
  }
}

class _AppealCard extends StatelessWidget {
  const _AppealCard({required this.item, required this.onDecide});
  final Map<String, dynamic> item;
  final ValueChanged<String> onDecide;

  @override
  Widget build(BuildContext context) {
    final x = item;
    final st = '${x['status'] ?? 'open'}';
    final files = ModApi.list(x['files']);
    final until = ModApi.time(x['blockUntil']);
    final stColor = switch (st) { 'accepted' => HadiColors.dostluk, 'rejected' => HadiColors.error, 'info' => HadiColors.iletisim, 'closed' => HadiColors.ink3, _ => HadiColors.heyecan };
    final thread = ModApi.list(x['thread']);
    final open = st == 'open' || st == 'info';
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
            child: Text(switch (st) { 'accepted' => 'Kabul', 'rejected' => 'Ret', 'info' => 'Ek bilgi bekleniyor', 'closed' => 'Kapandı', _ => 'Bekliyor' },
                style: TextStyle(color: Color.lerp(stColor, HadiColors.ink, .3), fontWeight: FontWeight.w800, fontSize: 12)),
          ),
        ]),
        Text(modDate(ModApi.time(x['at'])), style: TextStyle(color: HadiColors.ink3, fontSize: 12.5)),
        const SizedBox(height: 8),
        Text('Blok: ${x['blockModeLabel'] ?? ''} · ${until == null ? 'süresiz' : '${modDate(until)}\'e kadar'}${x['blockActive'] == false ? ' · artık aktif değil' : ''}',
            style: TextStyle(color: HadiColors.ink2, fontSize: 13, fontWeight: FontWeight.w700)),
        Text('Neden: ${x['blockReason'] ?? '—'}', style: TextStyle(color: HadiColors.ink2, fontSize: 13)),
        if ('${x['internal'] ?? ''}'.isNotEmpty) Text('İç not: ${x['internal']}', style: TextStyle(color: HadiColors.ink2, fontSize: 13)),
        if ('${x['blockByName'] ?? ''}'.isNotEmpty) Text('Bloklayan: ${x['blockByName']}', style: TextStyle(color: HadiColors.ink3, fontSize: 12.5)),
        const SizedBox(height: 8),
        if (thread.length <= 1)
          Text('${x['text'] ?? ''}', style: TextStyle(color: HadiColors.ink, height: 1.4))
        else
          for (final t in thread)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: t['by'] == 'user' ? HadiColors.mist : HadiColors.iletisim.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  '${switch ('${t['kind']}') { 'appeal' => 'İtiraz', 'reply' => 'Üyenin yanıtı', 'question' => 'Yönetimin sorusu', _ => 'Karar' }}'
                  '${'${t['byName'] ?? ''}'.isNotEmpty ? ' · ${t['byName']}' : ''} · ${modDate(ModApi.time(t['at']))}',
                  style: TextStyle(color: HadiColors.ink3, fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text('${t['text'] ?? ''}', style: TextStyle(color: HadiColors.ink, height: 1.35)),
              ]),
            ),
        if (files.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final f in files)
              ActionChip(
                avatar: Icon(switch ('${f['kind']}') { 'audio' => Icons.graphic_eq_rounded, 'pdf' => Icons.picture_as_pdf_rounded, _ => Icons.image_rounded }, size: 18),
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
        if (open) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
            OutlinedButton(
              onPressed: () => onDecide('reject'),
              style: OutlinedButton.styleFrom(foregroundColor: HadiColors.text(HadiColors.error)),
              child: const Text('Reddet'),
            ),
            if (st == 'open')
              OutlinedButton.icon(
                onPressed: () => onDecide('info'),
                icon: const Icon(Icons.help_outline_rounded, size: 18),
                label: const Text('Ek bilgi iste'),
              ),
            FilledButton(
              onPressed: x['canAccept'] == true ? () => onDecide('accept') : null,
              style: FilledButton.styleFrom(backgroundColor: HadiColors.fillForWhite(HadiColors.dostluk), foregroundColor: Colors.white),
              child: const Text('Kabul et ve bloğu kaldır'),
            ),
          ]),
          if (x['canAccept'] != true && x['blockActive'] == true)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(blockModeWho(blockModeFrom(x['blockMode'])), style: TextStyle(color: HadiColors.ink3, fontSize: 12.5)),
            ),
        ],
      ]),
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.decision, required this.name});
  final String decision;
  final String name;
  bool get accept => decision == 'accept';
  bool get info => decision == 'info';
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
        title: Text(widget.info ? 'Ek bilgi iste' : widget.accept ? 'İtirazı kabul et' : 'İtirazı reddet'),
        content: TextField(
          controller: _c,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          maxLength: 600,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: widget.info ? 'Soru (${widget.name} görür ve yanıtlar)' : 'Yanıt (${widget.name} görür)',
            helperText: 'En az 5 karakter; kayda geçer.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: HadiColors.fillForWhite(widget.info ? HadiColors.iletisim : widget.accept ? HadiColors.dostluk : HadiColors.error),
              foregroundColor: Colors.white,
            ),
            onPressed: _c.text.trim().length >= 5 ? () => Navigator.pop(context, _c.text.trim()) : null,
            child: Text(widget.info ? 'Soruyu gönder' : widget.accept ? 'Kabul et' : 'Reddet'),
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
