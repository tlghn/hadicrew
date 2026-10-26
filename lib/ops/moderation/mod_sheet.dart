// Üye profilindeki "Moderasyon" sayfası (kurucu, geçici kurucu, Sistem Moderatörü).
// Uyarı ver · Hesabı blokla / blokeyi kaldır · Profil fotoğrafı, profil yazısı, durum yazısı, belge kaldır ·
// Moderasyon geçmişi (kaldırılanı geri al). Her işlem zorunlu gerekçeyle kayda geçer (hesapMod).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hadi/data/models.dart' show AppFailure;
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/hadi_sheet.dart';
import 'package:hadi/widgets/reason_dialog.dart';
import 'package:hadi/widgets/skeleton.dart';
import 'package:hadi/features/moderation/mod_api.dart';
import 'package:hadi/features/moderation/account_block_sheet.dart' show blockModeFrom, blockModeLabel, blockModeWho, openAccountBlockSheet, openAccountUnblock, openBlockEditSheet;
import 'package:hadi/core/ui_gate.dart';

Future<void> openModSheet(BuildContext context, {required String uid, required String name}) => showHadiSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _ModSheet(uid: uid, name: name),
    );

class _ModSheet extends StatefulWidget {
  const _ModSheet({required this.uid, required this.name});
  final String uid, name;
  @override
  State<_ModSheet> createState() => _ModSheetState();
}

class _ModSheetState extends State<_ModSheet> {
  Map<String, dynamic>? _d;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ModApi.call('status', {'uid': widget.uid});
      if (mounted) setState(() => _d = d);
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _toast(String m) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m)));

  Future<void> _run(String op, Map<String, Object?> data, String done) async {
    setState(() => _busy = true);
    try {
      await ModApi.call(op, {'uid': widget.uid, ...data});
      HapticFeedback.mediumImpact();
      _toast(done);
      await _load();
    } on AppFailure catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> get _target => _d?['target'] is Map ? Map<String, dynamic>.from(_d!['target'] as Map) : const {};
  Map<String, dynamic>? get _block => _d?['block'] is Map ? Map<String, dynamic>.from(_d!['block'] as Map) : null;
  bool get _blocked {
    final b = _block;
    if (b == null || b['active'] == false) return false;
    final u = ModApi.time(b['until']);
    return u == null || u.isAfter(DateTime.now());
  }

  Future<void> _warn() async {
    final r = await uiOnce(context, () => showDialog<(String, String)>(context: context, builder: (_) => _WarnDialog(name: widget.name)));
    if (r == null || !mounted) return;
    await _run('warn', {'text': r.$1, if (r.$2.isNotEmpty) 'reason': r.$2}, 'Uyarı gönderildi; ${widget.name} bildirim aldı.');
  }

  // "Hesabı blokla" yalnızca ana kurucu (sunucu: account_mod.ts › block; durum yanıtındaki canBlock). Ortak sayfa:
  // hadi/features/moderation/account_block_sheet.dart (süre/kural, üyeye neden + not, iç not, önizleme, onay).
  Future<void> _blockUser() async {
    if (await openAccountBlockSheet(context, uid: widget.uid, name: widget.name, targetFounder: _target['founder'] == true)) await _load();
  }

  Future<void> _unblock() async {
    if (await openAccountUnblock(context, uid: widget.uid, name: widget.name, mode: blockModeFrom(_block?['mode']))) await _load();
  }

  Future<void> _editBlock() async {
    final b = _block;
    if (b == null) return;
    if (await openBlockEditSheet(context, uid: widget.uid, name: widget.name, block: b)) await _load();
  }

  Future<void> _takedown(String kind, {String? ref, required String what}) async {
    final reason = await askReason(
      context,
      title: '$what kaldırılsın mı?',
      message: 'Yayından kaldırılır; üyeye nedeniyle birlikte bildirilir. Kayıttan geri alınabilir.',
      confirm: 'Kaldır',
      danger: true,
      hint: 'Neden? Örn. "Müstehcen içerik, topluluk kuralları 3. madde."',
    );
    if (reason == null || !mounted) return;
    await _run('takedown', {'kind': kind, 'ref': ?ref, 'reason': reason}, '$what yayından kaldırıldı.');
  }

  Future<void> _pickPhoto() async {
    final photos = (_target['photos'] is List ? (_target['photos'] as List).map((e) => '$e').toList() : <String>[]);
    if (photos.isEmpty) return _toast('Profil fotoğrafı yok.');
    final url = await showHadiSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Kaldırılacak fotoğrafı seç', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final u in photos)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(c, u),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(u, fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: HadiColors.mist)),
                  ),
                ),
            ],
          ),
        ]),
      ),
    );
    if (url == null || !mounted) return;
    await _takedown('photo', ref: url, what: 'Profil fotoğrafı');
  }

  Future<void> _pickCert() async {
    final certs = ModApi.list(_target['certs']).where((c) => c['modRemoved'] != true).toList();
    if (certs.isEmpty) return _toast('Yayında belge yok.');
    final id = await showHadiSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(alignment: Alignment.centerLeft, child: Text('Kaldırılacak belgeyi seç', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        ),
        for (final x in certs)
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text('${x['title'] ?? 'Belge'}', maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => Navigator.pop(c, '${x['id']}'),
          ),
        const SizedBox(height: 8),
      ])),
    );
    if (id == null || !mounted) return;
    await _takedown('cert', ref: id, what: 'Belge');
  }

  Future<void> _history() => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ModLogScreen(uid: widget.uid, title: '${widget.name} · moderasyon geçmişi'),
      ));

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (_error != null) {
      return Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: HadiColors.text(HadiColors.error))));
    }
    if (d == null) return Column(mainAxisSize: MainAxisSize.min, children: List.generate(5, (_) => const ListTileSkeleton()));
    final t = _target;
    final founder = t['founder'] == true;
    final warnings = ModApi.list(d['warnings']);
    final b = _block;
    final blocked = _blocked;
    final until = ModApi.time(b?['until']);
    final bio = '${t['bio'] ?? ''}'.trim(), status = '${t['statusText'] ?? ''}'.trim();
    final photos = t['photos'] is List ? (t['photos'] as List).length : 0;
    final certs = ModApi.list(t['certs']).where((c) => c['modRemoved'] != true).length;
    return AbsorbPointer(
      absorbing: _busy,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: Row(children: [
            const Icon(Icons.shield_moon_outlined, color: HadiColors.iletisim),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Moderasyon · ${widget.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            ),
            if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Wrap(spacing: 8, runSpacing: 6, children: [
            _Chip(
              blocked ? (until == null ? 'Bloklu · süresiz' : 'Bloklu · ${modDate(until)}\'e kadar') : 'Aktif hesap',
              blocked ? HadiColors.error : HadiColors.dostluk,
            ),
            _Chip('${warnings.length} uyarı', warnings.isEmpty ? HadiColors.ink3 : HadiColors.heyecan),
            if (founder) const _Chip('👑 Kurucu', HadiColors.gold),
          ]),
        ),
        if (blocked)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              [
                blockModeLabel(blockModeFrom(b?['mode'])),
                if ('${b?['reason'] ?? ''}'.isNotEmpty) 'Neden: ${b!['reason']}',
                if ('${b?['internal'] ?? ''}'.isNotEmpty) 'İç not: ${b!['internal']}',
                if ('${b?['byName'] ?? ''}'.isNotEmpty) 'Bloklayan: ${b!['byName']}',
              ].join('\n'),
              style: TextStyle(color: HadiColors.ink2, height: 1.35),
            ),
          ),
        if (blocked && b?['canLift'] == true)
          _Action(icon: Icons.lock_open_rounded, color: HadiColors.dostluk, title: 'Bloğu kaldır', sub: 'Uygulamaya yeniden erişir; hesap her yerde yeniden görünür.', onTap: _unblock),
        if (blocked && b?['canLift'] != true)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(blockModeWho(blockModeFrom(b?['mode'])), style: TextStyle(color: HadiColors.ink3, fontSize: 12.5)),
          ),
        if (blocked && b?['canEdit'] == true)
          _Action(icon: Icons.edit_calendar_rounded, title: 'Süreyi değiştir', sub: 'Süre ya da kaldırma kuralı (ana kurucu)', onTap: _editBlock),
        if (!blocked && d['canBlock'] == true)
          _Action(icon: Icons.block_rounded, color: HadiColors.error, title: 'Hesabı blokla', sub: 'Ana kurucu · hesap her yerde gizlenir; üye nedenini görür, itiraz edebilir.', onTap: _blockUser),
        if (founder)
          Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text('Kuruculara diğer moderasyon işlemleri uygulanamaz.', style: TextStyle(color: HadiColors.ink3)),
          )
        else ...[
          _Action(icon: Icons.warning_amber_rounded, color: HadiColors.heyecan, title: 'Uyarı ver', sub: 'Yalnızca üye kendi profilinde görür; bildirim gider.', onTap: _warn),
          const Divider(height: 18, indent: 20, endIndent: 20),
          _Action(
            icon: Icons.hide_image_outlined,
            title: 'Profil fotoğrafını kaldır',
            sub: photos == 0 ? 'Fotoğraf yok' : '$photos fotoğraf',
            onTap: photos == 0 ? null : _pickPhoto,
          ),
          _Action(
            icon: Icons.subject_rounded,
            title: 'Profil yazısını kaldır',
            sub: bio.isEmpty ? 'Yazı yok' : bio,
            onTap: bio.isEmpty ? null : () => _takedown('bio', what: 'Profil yazısı'),
          ),
          _Action(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Durum yazısını kaldır',
            sub: status.isEmpty ? 'Durum yok' : status,
            onTap: status.isEmpty ? null : () => _takedown('status', what: 'Durum yazısı'),
          ),
          _Action(
            icon: Icons.folder_off_outlined,
            title: 'Belge kaldır',
            sub: certs == 0 ? 'Yayında belge yok' : '$certs belge',
            onTap: certs == 0 ? null : _pickCert,
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 2, 20, 4),
            child: Text('Gönderi, yazı, story ve yorumları kendi menülerinden "Gizle" ile kaldırabilirsin.', style: TextStyle(color: HadiColors.ink3, fontSize: 12.5)),
          ),
        ],
        const Divider(height: 18, indent: 20, endIndent: 20),
        _Action(icon: Icons.history_rounded, title: 'Moderasyon geçmişi', sub: 'Kim, ne zaman, neden', onTap: _history),
        SizedBox(height: 8 + MediaQuery.paddingOf(context).bottom),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, this.color);
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: Color.lerp(color, HadiColors.ink, .25), fontWeight: FontWeight.w700, fontSize: 12.5)),
      );
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.title, required this.sub, required this.onTap, Color? color}) : _color = color;
  final IconData icon;
  final String title, sub;
  final VoidCallback? onTap;
  final Color? _color;
  Color get color => _color ?? HadiColors.ink2;
  @override
  Widget build(BuildContext context) => ListTile(
        enabled: onTap != null,
        leading: Icon(icon, color: onTap == null ? HadiColors.ink3 : color),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      );
}

class _WarnDialog extends StatefulWidget {
  const _WarnDialog({required this.name});
  final String name;
  @override
  State<_WarnDialog> createState() => _WarnDialogState();
}

class _WarnDialogState extends State<_WarnDialog> {
  final _text = TextEditingController();
  final _reason = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _text.text.trim().length >= 5;
    return AlertDialog(
      scrollable: true,
      title: Text('${widget.name} için uyarı'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _text,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Uyarı metni (üye görür)', alignLabelWithHint: true),
        ),
        TextField(
          controller: _reason,
          maxLength: 300,
          decoration: const InputDecoration(labelText: 'İç not (isteğe bağlı, yalnızca kayıtta)'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: ok ? () => Navigator.pop(context, (_text.text.trim(), _reason.text.trim())) : null,
          child: const Text('Uyarıyı gönder'),
        ),
      ],
    );
  }
}

/// Moderasyon kayıtları: tek üye ([uid]) ya da tümü. Kaldırılan içeriği geri alma düğmesiyle.
class ModLogScreen extends StatelessWidget {
  const ModLogScreen({super.key, this.uid, this.title = 'Moderasyon kayıtları'});
  final String? uid;
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title)), body: ModLogList(uid: uid));
}

class ModLogList extends StatefulWidget {
  const ModLogList({super.key, this.uid});
  final String? uid;
  @override
  State<ModLogList> createState() => _ModLogListState();
}

class _ModLogListState extends State<ModLogList> {
  List<Map<String, dynamic>>? _items;
  String? _error;
  String _filter = 'all';
  String _q = '';

  static const _filters = <(String, String)>[
    ('all', 'Tümü'),
    ('block', 'Bloke'),
    ('warn', 'Uyarı'),
    ('takedown', 'Kaldırma'),
    ('content', 'İçerik gizleme'),
    ('appeal', 'İtiraz'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ModApi.call('log', {'uid': ?widget.uid, 'limit': 300});
      if (mounted) setState(() => _items = ModApi.list(d['items']));
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  bool _match(Map<String, dynamic> x) {
    final a = '${x['action']}';
    final okF = switch (_filter) {
      'all' => true,
      'block' => a == 'block' || a == 'unblock',
      'takedown' => a == 'takedown' || a == 'restore',
      'content' => a.startsWith('content.'),
      'appeal' => a.startsWith('appeal'),
      _ => a == _filter,
    };
    if (!okF) return false;
    if (_q.isEmpty) return true;
    final hay = '${x['targetName'] ?? ''} ${x['actorName'] ?? ''} ${x['reason'] ?? ''}'.toLowerCase();
    return hay.contains(_q.toLowerCase());
  }

  Future<void> _restore(Map<String, dynamic> x) async {
    final id = '${x['takedownId'] ?? x['id']}';
    final reason = await askReason(context, title: 'Yeniden yayına al', message: '${modKindLabel(x['kind'] as String?)} geri yüklenecek.', confirm: 'Geri al');
    if (reason == null || !mounted) return;
    try {
      await ModApi.call('restore', {'id': id, 'reason': reason});
      HapticFeedback.mediumImpact();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Yeniden yayında.')));
      await _load();
    } on AppFailure catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)));
    final items = _items;
    final restored = {for (final x in items ?? const <Map<String, dynamic>>[]) if (x['action'] == 'restore') '${x['takedownId'] ?? ''}'};
    final shown = items?.where(_match).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (widget.uid == null)
                TextField(
                  onChanged: (v) => setState(() => _q = v.trim()),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Üye, işlemi yapan ya da neden ara', isDense: true),
                ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final f in _filters)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(label: Text(f.$2), selected: _filter == f.$1, onSelected: (_) => setState(() => _filter = f.$1)),
                    ),
                ]),
              ),
            ]),
          ),
        ),
        if (shown == null)
          SliverList.list(children: List.generate(6, (_) => const ListTileSkeleton()))
        else if (shown.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('Kayıt yok.', style: TextStyle(color: HadiColors.ink3))),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + MediaQuery.paddingOf(context).bottom),
            sliver: SliverList.separated(
              itemCount: shown.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final x = shown[i];
                final a = '${x['action']}';
                final canRestore = a == 'takedown' && !restored.contains('${x['takedownId'] ?? x['id']}');
                return _LogTile(item: x, onRestore: canRestore ? () => _restore(x) : null);
              },
            ),
          ),
      ]),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.item, this.onRestore});
  final Map<String, dynamic> item;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final x = item;
    final a = '${x['action']}';
    final color = switch (a) {
      'block' || 'takedown' || 'content.hide' || 'appeal.reject' => HadiColors.error,
      'unblock' || 'restore' || 'content.unhide' || 'appeal.accept' => HadiColors.dostluk,
      'warn' => HadiColors.heyecan,
      _ => HadiColors.aktivite,
    };
    final until = ModApi.time(x['until']);
    final kind = x['kind'] as String?;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: HadiColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: HadiColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${modActionLabel(a)}${kind != null && kind.isNotEmpty ? ' · ${modKindLabel(kind)}' : ''}',
              style: TextStyle(fontWeight: FontWeight.w800, color: Color.lerp(color, HadiColors.ink, .35)),
            ),
          ),
          Text(modDate(ModApi.time(x['at'])), style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
        ]),
        const SizedBox(height: 6),
        Text.rich(TextSpan(children: [
          TextSpan(text: 'Üye: ', style: TextStyle(color: HadiColors.ink3)),
          TextSpan(text: '${x['targetName'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: '   ·   Yapan: ', style: TextStyle(color: HadiColors.ink3)),
          TextSpan(text: '${x['actorName'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700)),
          if ('${x['actorRole'] ?? ''}'.isNotEmpty) TextSpan(text: ' (${x['actorRole']})', style: TextStyle(color: HadiColors.ink3)),
        ]), style: TextStyle(color: HadiColors.ink, fontSize: 13.5)),
        if ('${x['reason'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Neden: ${x['reason']}', style: TextStyle(color: HadiColors.ink2, height: 1.35)),
        ],
        if ('${x['details'] ?? ''}'.isNotEmpty) Text('Ayrıntı: ${x['details']}', style: TextStyle(color: HadiColors.ink3, height: 1.35)),
        if (a == 'block') Text(until == null ? 'Süre: süresiz' : 'Bitiş: ${modDate(until)}', style: TextStyle(color: HadiColors.ink3, fontSize: 12.5)),
        if (onRestore != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(onPressed: onRestore, icon: const Icon(Icons.restore_rounded, size: 18), label: const Text('Geri al')),
          ),
      ]),
    );
  }
}
