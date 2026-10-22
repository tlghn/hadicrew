import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hadi/core/session.dart';
import 'package:hadi/data/chat_models.dart';
import 'package:hadi/data/community_service.dart' show Community;
import 'package:hadi/data/member_models.dart';
import 'package:hadi/data/models.dart';
import 'package:hadi/data/roles_service.dart';
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/common.dart';
import 'package:hadi/widgets/reason_dialog.dart';
import 'package:hadi/widgets/hadi_sheet.dart';
import 'package:hadi/features/fun/_placeholders.dart';
import 'package:hadi/features/candidate/lobby_emoji.dart' show LobbyEmojiPanel;
import 'package:hadi/features/messages/chat_widgets.dart' show ChatAvatar;

// "Rolleri yönetebilir mi" (canManageRoles) temel pakette: lib/modules.dart
// (profil menüsü düğmeyi modülü indirmeden gösterir; sunucu ayrıca denetler).

/// Önceliği sunucuda sabit kurucu rolleri. İkisi de her yerde "Kurucu" adıyla ve aynı emojiyle görünür;
/// ayrımı (gecici_kurucu) yalnızca ana kurucu, kurucu panelinde ince bir işaretle görür.
const kFounderRoleIds = {'kurucu', 'gecici_kurucu'};

/// Ana kurucunun eklediği kurucuların rolü (adı yine "Kurucu").
const kAddedFounderRoleId = 'gecici_kurucu';

/// Rol renk seçenekleri ('#RRGGBB').
const kRoleColors = ['#F2801F', '#1D9AD6', '#78BE3A', '#A3338C', '#E0407A', '#D9A93A', '#17344F', '#2BB5A0', '#7A5AF8', '#D64545', '#6B7F92', '#8D6E63'];

Color _c(String hex) {
  final h = hex.replaceFirst('#', '');
  final v = h.length == 6 ? int.tryParse(h, radix: 16) : null;
  return Color(0xFF000000 | (v ?? 0x1D9AD6));
}

String _err(Object e) => e is AppFailure ? e.message : 'Olmadı, bağlantını kontrol edip tekrar dene.';

/// Rol oluştur / düzenle: emoji, ad, açıklama, renk, yetkiler, görünürlük, kapsam.
class RoleEditSheet extends StatefulWidget {
  const RoleEditSheet({super.key, required this.initial, required this.capabilities});
  final HadiRole initial;
  final List<RoleCapability> capabilities;

  @override
  State<RoleEditSheet> createState() => _RoleEditSheetState();
}

class _RoleEditSheetState extends State<RoleEditSheet> {
  late final _name = TextEditingController(text: widget.initial.name);
  late final _desc = TextEditingController(text: widget.initial.description);
  late String _emoji = widget.initial.emoji;
  late String _color = widget.initial.color;
  late final Set<String> _caps = {...widget.initial.capabilities};
  late bool _visible = widget.initial.visible;
  late bool _scoped = widget.initial.scoped;
  String? _nameErr;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickEmoji() async {
    final e = await showHadiSheet<String>(
      context: context,
      builder: (c) => LobbyEmojiPanel(height: 340, onPick: (e) => Navigator.pop(c, e)),
    );
    if (e != null && mounted) setState(() => _emoji = e);
  }

  /// Kurucu rollerinin adı her zaman "Kurucu"dur (sunucu da zorlar).
  bool get _founderRole => kFounderRoleIds.contains(widget.initial.id);

  void _save() {
    final name = _founderRole ? 'Kurucu' : _name.text.trim();
    if (name.length < 2) {
      setState(() => _nameErr = 'En az 2 harf yaz.');
      return;
    }
    Navigator.pop(
      context,
      widget.initial.copyWith(
        name: name,
        emoji: _emoji,
        color: _color,
        description: _desc.text.trim(),
        capabilities: [for (final c in widget.capabilities) if (_caps.contains(c.id)) c.id, ..._caps.where((id) => !widget.capabilities.any((c) => c.id == id))],
        visible: _visible,
        scoped: _scoped,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final editing = widget.initial.id.isNotEmpty;
    final groups = <String, List<RoleCapability>>{};
    for (final c in widget.capabilities) {
      (groups[c.group] ??= []).add(c);
    }
    final color = _c(_color);
    return SizedBox(
      height: MediaQuery.of(context).size.height * .86,
      child: Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), children: [
            Text(editing ? 'Rolü düzenle' : 'Yeni rol', style: text.headlineSmall),
            if (widget.initial.system) ...[
              const SizedBox(height: 8),
              InfoNote(icon: Icons.lock_rounded, color: HadiColors.ink3, text: 'Sistem rolü: düzenlenebilir ama silinemez.'),
            ],
            const SizedBox(height: 16),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              InkWell(
                onTap: _pickEmoji,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(18), border: Border.all(color: color.withValues(alpha: .5))),
                  child: Text(_emoji, style: const TextStyle(fontSize: 32)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _name,
                  readOnly: _founderRole,
                  maxLength: 30,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) {
                    if (_nameErr != null) setState(() => _nameErr = null);
                  },
                  decoration: InputDecoration(
                    labelText: 'Rol adı',
                    hintText: 'Örneğin: Sohbet Operatörü',
                    helperText: _founderRole ? 'Kurucu rollerinin adı değişmez; emoji ve renk iki kurucu rolünde ortaktır.' : null,
                    helperMaxLines: 2,
                    errorText: _nameErr,
                  ),
                ),
              ),
            ]),
            TextButton.icon(onPressed: _pickEmoji, icon: const Icon(Icons.emoji_emotions_outlined, size: 18), label: const Text('Emojiyi değiştir')),
            TextField(
              controller: _desc,
              maxLength: 160,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Açıklama', hintText: 'Rozete dokunan üyeler görür'),
            ),
            const SizedBox(height: 4),
            Text('Renk', style: text.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final h in kRoleColors)
                GestureDetector(
                  onTap: () => setState(() => _color = h),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _c(h),
                      shape: BoxShape.circle,
                      border: Border.all(color: _color.toUpperCase() == h ? HadiColors.ink : Colors.transparent, width: 3),
                    ),
                    child: _color.toUpperCase() == h ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _visible,
              onChanged: (v) => setState(() => _visible = v),
              title: const Text('Rozet görünsün'),
              subtitle: const Text('Emoji, sahiplerinin profilinde ve isimlerinin yanında görünür.'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _scoped,
              onChanged: (v) => setState(() => _scoped = v),
              title: const Text('Kapsamlı rol'),
              subtitle: const Text('Verirken kanal, grup ya da Bekleme Salonu seçilebilir; yetkiler yalnızca orada geçerli olur.'),
            ),
            const SizedBox(height: 8),
            Text('Yetkiler', style: text.titleSmall),
            for (final g in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 2),
                child: Text(g.key.toUpperCase(), style: text.labelSmall?.copyWith(color: HadiColors.ink3, fontWeight: FontWeight.w800, letterSpacing: .4)),
              ),
              for (final c in g.value)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _caps.contains(c.id),
                  onChanged: (v) => setState(() => v == true ? _caps.add(c.id) : _caps.remove(c.id)),
                  title: Text(c.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: c.desc.isEmpty ? null : Text(c.desc),
                ),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: PrimaryButton(label: editing ? 'Kaydet' : 'Oluştur', icon: Icons.check_rounded, onPressed: _save),
        ),
      ]),
    );
  }
}

// -----------------------------------------------------------------------------
// Kapsamlar (kanal / grup / Bekleme Salonu)
// -----------------------------------------------------------------------------

/// Kapsam seçenekleri: tür → [(kapsam, etiket)]. Oturum başına bir kez yüklenir.
class _ScopeOptions {
  static Future<Map<String, List<(String, String)>>>? _cache;

  static Future<Map<String, List<(String, String)>>> load(Session s) => _cache ??= _fetch(s).then((v) => v, onError: (Object e) {
        _cache = null;
        throw e;
      });

  static Future<Map<String, List<(String, String)>>> _fetch(Session s) async {
    final svc = s.services;
    Future<List<T>> safe<T>(Future<List<T>> f) => f.timeout(const Duration(seconds: 12)).catchError((Object _) => <T>[]);
    final res = await Future.wait<Object>([
      safe<Chat>(svc.chat.watchChannels().first),
      safe<Community>(svc.community.watchGroups().first),
      safe<Map<String, Object?>>(svc.candidates.rooms()),
    ]);
    final channels = res[0] as List<Chat>;
    final groups = res[1] as List<Community>;
    final rooms = res[2] as List<Map<String, Object?>>;
    return {
      'channel': [
        for (final c in channels) (roleScope('channel', c.id), '${c.emoji} ${c.title.isEmpty ? 'Kanal' : c.title}'),
      ],
      'group': [
        for (final g in groups) (roleScope('group', g.id), '${g.emoji} ${g.name}'),
      ],
      'lobby': [
        for (final r in rooms)
          if ('${r['room'] ?? ''}'.isNotEmpty) (roleScope('lobby', '${r['room']}'), '🛋️ ${r['name'] ?? r['room']}'),
      ],
    };
  }

  static String label(String scope, Map<String, List<(String, String)>>? opts) {
    final (kind, id) = parseRoleScope(scope);
    for (final o in opts?[kind] ?? const <(String, String)>[]) {
      if (o.$1 == scope) return o.$2;
    }
    return '${kRoleScopeKinds[kind] ?? 'Kapsam'} · $id';
  }
}

/// Kapsam çipleri (adlarıyla). [onDeleted] verilirse silinebilir.
class RoleScopeChips extends StatelessWidget {
  const RoleScopeChips({super.key, required this.scopes, this.onDeleted, this.emptyText = 'Her yerde'});
  final List<String> scopes;
  final ValueChanged<String>? onDeleted;
  final String emptyText;

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, List<(String, String)>>>(
        future: _ScopeOptions.load(SessionScope.read(context)),
        builder: (context, snap) {
          if (scopes.isEmpty) {
            return Text(emptyText, style: TextStyle(color: HadiColors.ink3, fontSize: 12.5));
          }
          return Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in scopes)
              InputChip(
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                label: Text(_ScopeOptions.label(s, snap.data), style: const TextStyle(fontSize: 12.5)),
                onDeleted: onDeleted == null ? null : () => onDeleted!(s),
              ),
          ]);
        },
      );
}

/// Kapsam seç: kanal / grup / salon sekmeleri. Boş liste: her yerde geçerli.
Future<List<String>?> pickRoleScopes(BuildContext context, {List<String> initial = const [], String? title}) => showHadiSheet<List<String>>(
      context: context,
      showDragHandle: true,
      builder: (_) => _ScopePicker(initial: initial, title: title ?? 'Kapsam seç'),
    );

class _ScopePicker extends StatefulWidget {
  const _ScopePicker({required this.initial, required this.title});
  final List<String> initial;
  final String title;

  @override
  State<_ScopePicker> createState() => _ScopePickerState();
}

class _ScopePickerState extends State<_ScopePicker> {
  late final Set<String> _sel = {...realScopes(widget.initial)};
  late final Future<Map<String, List<(String, String)>>> _opts = _ScopeOptions.load(SessionScope.read(context));

  @override
  Widget build(BuildContext context) => SizedBox(
        height: MediaQuery.of(context).size.height * .75,
        child: DefaultTabController(
          length: kRoleScopeKinds.length,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Row(children: [
                Expanded(child: Text(widget.title, style: Theme.of(context).textTheme.titleLarge)),
                if (_sel.isNotEmpty) TextButton(onPressed: () => setState(_sel.clear), child: const Text('Temizle')),
              ]),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('Hiçbirini seçmezsen rol her yerde geçerli olur.', style: TextStyle(color: HadiColors.ink3, fontSize: 13)),
            ),
            TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final v in kRoleScopeKinds.values) Tab(text: v)]),
            Expanded(
              child: FutureBuilder<Map<String, List<(String, String)>>>(
                future: _opts,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) return const RowsSkeleton();
                  final o = snap.data ?? const {};
                  return TabBarView(children: [
                    for (final k in kRoleScopeKinds.keys)
                      (o[k] ?? const []).isEmpty
                          ? Center(child: Text('Seçenek yok.', style: TextStyle(color: HadiColors.ink3)))
                          : ListView(children: [
                              for (final (scope, label) in o[k]!)
                                CheckboxListTile(
                                  value: _sel.contains(scope),
                                  onChanged: (v) => setState(() => v == true ? _sel.add(scope) : _sel.remove(scope)),
                                  title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                            ]),
                  ]);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: PrimaryButton(
                label: _sel.isEmpty ? 'Her yerde geçerli' : '${_sel.length} kapsamla kaydet',
                onPressed: () => Navigator.pop(context, _sel.toList()),
              ),
            ),
          ]),
        ),
      );
}

// -----------------------------------------------------------------------------
// Üye arama
// -----------------------------------------------------------------------------

/// Üye ara (ad ya da @kullanıcı adı) ve seç.
Future<MemberProfile?> pickMemberForRole(BuildContext context, {String title = 'Üye ekle'}) => showHadiSheet<MemberProfile>(
      context: context,
      showDragHandle: true,
      builder: (_) => _MemberSearch(title: title),
    );

class _MemberSearch extends StatefulWidget {
  const _MemberSearch({required this.title});
  final String title;

  @override
  State<_MemberSearch> createState() => _MemberSearchState();
}

class _MemberSearchState extends State<_MemberSearch> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<MemberProfile> _results = const [];
  bool _loading = false;
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(v));
  }

  Future<void> _search(String v) async {
    final my = ++_seq;
    if (v.trim().replaceFirst('@', '').length < 2) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      // Yönetim araması (staff_search, yalnızca yetkililer): rumuzlu üye gerçek adıyla da bulunur; bloklular dahil.
      final r = await SessionScope.read(context).services.members.staffSearch(v);
      if (mounted && my == _seq) setState(() => _results = r);
    } catch (_) {
      if (mounted && my == _seq) setState(() => _results = const []);
    } finally {
      if (mounted && my == _seq) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: MediaQuery.of(context).size.height * .75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              TextField(
                controller: _q,
                autofocus: true,
                onChanged: _changed,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Ad soyad, rumuz ya da @kullanıcı adı'),
              ),
            ]),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(children: [
              if (!_loading && _results.isEmpty && _q.text.trim().length >= 2)
                Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Üye bulunamadı.', style: TextStyle(color: HadiColors.ink3)))),
              for (final p in _results)
                ListTile(
                  leading: ChatAvatar(uid: p.uid, name: p.publicName, photoUrl: p.photoUrl, size: 42),
                  title: Text(p.staffLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: p.username == null ? null : Text('@${p.username}'),
                  onTap: () => Navigator.pop(context, p),
                ),
            ]),
          ),
        ]),
      );
}

// -----------------------------------------------------------------------------
// Profilden rol ver / al
// -----------------------------------------------------------------------------

/// Üyenin profilinden: rolleri işaretle (kapsamlı rollerde kapsam seç) ve kaydet.
Future<void> openUserRolesSheet(BuildContext context, {required String uid, required String name}) => showHadiSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _UserRolesSheet(uid: uid, name: name),
    );

class _UserRolesSheet extends StatefulWidget {
  const _UserRolesSheet({required this.uid, required this.name});
  final String uid, name;

  @override
  State<_UserRolesSheet> createState() => _UserRolesSheetState();
}

class _UserRolesSheetState extends State<_UserRolesSheet> {
  List<HadiRole>? _roles;
  Map<String, List<String>> _before = const {};

  /// Seçili roller → kapsamları.
  final _sel = <String, List<String>>{};
  String? _error;
  bool _saving = false;

  RolesService get _svc => RolesService.of(SessionScope.read(context).services);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final svc = _svc;
      final res = await Future.wait<Object>([svc.list(), svc.userRoles(widget.uid)]);
      final l = res[0] as ({List<HadiRole> roles, List<RoleCapability> capabilities});
      final u = res[1] as UserRoles;
      if (!mounted) return;
      setState(() {
        // Kurucu rolleri burada hiç gösterilmez ve değiştirilmez (kurucu paneli › Kurucular).
        _roles = [for (final r in l.roles) if (!kFounderRoleIds.contains(r.id)) r];
        _before = {
          for (final id in u.roleIds)
            if (!kFounderRoleIds.contains(id)) id: List.of(u.roleScopes[id] ?? const <String>[]),
        };
        _sel
          ..clear()
          ..addAll({for (final e in _before.entries) e.key: List.of(e.value)});
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  Future<void> _toggle(HadiRole r, bool on) async {
    if (!on) {
      setState(() => _sel.remove(r.id));
      return;
    }
    if (r.scoped) {
      final s = await pickRoleScopes(context, title: '${r.emoji} ${r.name} · kapsam');
      if (s == null || !mounted) return;
      setState(() => _sel[r.id] = s);
    } else {
      setState(() => _sel[r.id] = const []);
    }
  }

  Future<void> _scopes(HadiRole r) async {
    final s = await pickRoleScopes(context, initial: _sel[r.id] ?? const [], title: '${r.emoji} ${r.name} · kapsam');
    if (s == null || !mounted) return;
    setState(() => _sel[r.id] = s);
  }

  static bool _sameScopes(List<String> a, List<String> b) => a.length == b.length && a.toSet().containsAll(b);

  Future<void> _save() async {
    final svc = _svc;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final reason = await askRoleReason(context, title: '${widget.name} · rol değişikliği');
    if (reason == null || !mounted) return;
    setState(() => _saving = true);
    if (svc is DemoRolesService) svc.rememberName(widget.uid, widget.name);
    try {
      for (final id in _before.keys) {
        if (!_sel.containsKey(id)) await svc.unassign(widget.uid, id, reason: reason);
      }
      for (final e in _sel.entries) {
        final old = _before[e.key];
        if (old != null && _sameScopes(old, e.value)) continue;
        final role = _roles?.where((r) => r.id == e.key).firstOrNull;
        await svc.assign(widget.uid, e.key, scopes: role?.scoped ?? false ? e.value : null, reason: reason);
      }
      HapticFeedback.mediumImpact();
      nav.pop();
      messenger.showSnackBar(SnackBar(content: Text('${widget.name} için roller kaydedildi.')));
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        messenger.showSnackBar(SnackBar(content: Text(_err(e))));
        await _load();
      }
    }
  }

  bool get _dirty {
    if (_sel.length != _before.length) return true;
    for (final e in _sel.entries) {
      final o = _before[e.key];
      if (o == null || !_sameScopes(o, e.value)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final roles = _roles;
    return SizedBox(
      height: MediaQuery.of(context).size.height * .8,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
          child: Row(children: [
            Expanded(child: Text('${widget.name} · roller', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge)),
          ]),
        ),
        if (_saving) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: roles == null
              ? Center(
                  child: _error == null
                      ? const CircularProgressIndicator()
                      : Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)),
                )
              : roles.isEmpty
                  ? Center(child: Text('Henüz rol tanımlanmamış.', style: TextStyle(color: HadiColors.ink3)))
                  : ListView(padding: const EdgeInsets.symmetric(horizontal: 8), children: [
                      for (final r in roles)
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          CheckboxListTile(
                            value: _sel.containsKey(r.id),
                            onChanged: _saving ? null : (v) => _toggle(r, v == true),
                            secondary: CircleAvatar(backgroundColor: _c(r.color).withValues(alpha: .15), child: Text(r.emoji, style: const TextStyle(fontSize: 20))),
                            title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: r.description.isEmpty ? null : Text(r.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                          ),
                          if (r.scoped && _sel.containsKey(r.id))
                            Padding(
                              padding: const EdgeInsets.fromLTRB(72, 0, 16, 10),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Expanded(child: RoleScopeChips(scopes: _sel[r.id]!)),
                                TextButton(onPressed: _saving ? null : () => _scopes(r), child: const Text('Kapsam')),
                              ]),
                            ),
                        ]),
                    ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: PrimaryButton(label: 'Kaydet', loading: _saving, onPressed: roles == null || !_dirty || _saving ? null : _save),
        ),
      ]),
    );
  }
}

// -----------------------------------------------------------------------------
// Zorunlu gerekçe ve rol geçmişi
// -----------------------------------------------------------------------------

/// Rol verme / kaldırma için zorunlu gerekçe (en az [kRoleReasonMin] karakter). Vazgeçilirse null.
Future<String?> askRoleReason(
  BuildContext context, {
  required String title,
  String? message,
  String confirm = 'Kaydet',
  bool danger = false,
}) =>
    askReason(context, title: title, message: message, confirm: confirm, danger: danger);
