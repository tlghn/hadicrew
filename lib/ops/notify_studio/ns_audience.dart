// HADİ Crew — Bildirim Stüdyosu: kitle seçici (24 Ekim 2026). Herkes · tek üye (arama + zorunlu gerekçe) · liste · kayıtlı
// kitle · VE/VEYA gruplu süzgeçler. Düzenlerken canlı sayım (sunucu: audienceCount — kategori kapısından sonra kaç kişiye
// gideceği, kimlerin neden düşeceği, eşik/onay ve küçük kitle uyarısı). Özel nitelikli veriyle (sağlık, din, siyaset, cinsel
// yönelim…) süzgeç YOKTUR; hassas topluluk/ilgi adları listelenmez ve sunucu reddeder.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hadi/core/districts_tr.dart' show kIlceler;
import 'package:hadi/core/lists.dart' show kIller, kInterestGroups;
import 'package:hadi/core/session.dart';
import 'package:hadi/data/member_models.dart' show MemberProfile;
import 'package:hadi/panel_ui/crew_ui.dart';
import 'package:hadi/theme/hadi_colors.dart';

import 'ns_api.dart';

class NsAudienceEditor extends StatefulWidget {
  const NsAudienceEditor({super.key, required this.draft, required this.onChanged, this.onCount});
  final NsDraft draft;
  final VoidCallback onChanged;
  final void Function(Map<String, dynamic>? count)? onCount;

  @override
  State<NsAudienceEditor> createState() => _NsAudienceEditorState();
}

class _NsAudienceEditorState extends State<NsAudienceEditor> {
  Timer? _deb;
  Map<String, dynamic>? _count;
  String? _countErr;
  bool _counting = false;
  List<Map<String, dynamic>> _saved = [];
  final _names = <String, String>{}; // uid → ad (tek üye / liste)
  final _commNames = <String, String>{};
  int _seq = 0;

  NsDraft get d => widget.draft;
  Map<String, Object?> get a => d.audience;
  String get mode => '${a['mode'] ?? 'all'}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSaved();
      _recount();
    });
  }

  String? _lastCat;

  /// Kategori değişince (pazarlama rıza kapısı vb.) yeniden say; içerik yazarken saymaz.
  @override
  void didUpdateWidget(covariant NsAudienceEditor old) {
    super.didUpdateWidget(old);
    if (_lastCat != d.category) _recount();
  }

  @override
  void dispose() {
    _deb?.cancel();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    try {
      final l = await NsApi.audiences(SessionScope.read(context).services);
      if (mounted) setState(() => _saved = l);
    } catch (_) {}
  }

  void _changed() {
    widget.onChanged();
    setState(() {});
    _recount();
  }

  void _recount() {
    _lastCat = d.category;
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      final s = SessionScope.read(context).services;
      final my = ++_seq;
      _lastCat = d.category;
      if (_incomplete()) {
        setState(() => (_count = null, _countErr = null));
        widget.onCount?.call(null);
        return;
      }
      setState(() => _counting = true);
      try {
        final c = await NsApi.count(s, a, d.category);
        if (!mounted || my != _seq) return;
        setState(() => (_count = c, _countErr = null, _counting = false));
        widget.onCount?.call(c);
      } catch (e) {
        if (!mounted || my != _seq) return;
        setState(() => (_count = null, _countErr = '$e'.replaceFirst('AppFailure: ', ''), _counting = false));
        widget.onCount?.call(null);
      }
    });
  }

  bool _incomplete() {
    switch (mode) {
      case 'single':
        return (a['uid'] ?? '').toString().isEmpty;
      case 'list':
        return ((a['uids'] as List?) ?? const []).isEmpty;
      case 'saved':
        return (a['savedId'] ?? '').toString().isEmpty;
      case 'filter':
        final gs = (a['groups'] as List?) ?? const [];
        return gs.isEmpty || gs.every((g) => ((g as Map)['rules'] as List? ?? const []).isEmpty) || gs.any((g) => ((g as Map)['rules'] as List? ?? const []).any((r) => !_ruleReady(r as Map)));
    }
    return false;
  }

  bool _ruleReady(Map r) {
    final v = r['v'];
    if (v is List) return v.isNotEmpty && v.every((x) => x != null && '$x'.isNotEmpty);
    return v != null && '$v'.isNotEmpty;
  }

  void _setMode(String m) {
    d.audience = switch (m) {
      'single' => {'mode': 'single', 'uid': ''},
      'list' => {'mode': 'list', 'uids': <String>[]},
      'saved' => {'mode': 'saved', 'savedId': _saved.isEmpty ? '' : _saved.first['id']},
      'filter' => {
          'mode': 'filter',
          'join': 'and',
          'groups': [
            {'join': 'and', 'rules': <Map<String, Object?>>[]},
          ],
        },
      _ => {'mode': 'all'},
    };
    _changed();
  }

  // ---------------------------------------------------------------- üye arama

  Future<MemberProfile?> _pickMember() => showDialog<MemberProfile>(context: context, builder: (_) => const _MemberSearchDialog());

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (id, label, icon) in const [
          ('all', 'Herkes', Icons.public_rounded),
          ('filter', 'Süzgeçle', Icons.filter_alt_rounded),
          ('saved', 'Kayıtlı kitle', Icons.bookmark_rounded),
          ('list', 'Üye listesi', Icons.people_alt_rounded),
          ('single', 'Tek üye', Icons.person_rounded),
        ])
          ChoiceChip(avatar: Icon(icon, size: 18), label: Text(label), selected: mode == id, onSelected: (_) => _setMode(id)),
      ]),
      const SizedBox(height: 12),
      if (mode == 'single') _single(t),
      if (mode == 'list') _list(t),
      if (mode == 'saved') _savedPicker(t),
      if (mode == 'filter') _filters(t),
      const SizedBox(height: 12),
      _countBanner(t),
    ]);
  }

  Widget _single(TextTheme t) {
    final uid = '${a['uid'] ?? ''}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (uid.isEmpty)
        OutlinedButton.icon(
          onPressed: () async {
            final m = await _pickMember();
            if (m == null) return;
            _names[m.uid] = m.publicName;
            d.audience = {'mode': 'single', 'uid': m.uid};
            _changed();
          },
          icon: const Icon(Icons.search_rounded),
          label: const Text('Üye ara (ad, rumuz ya da @kullanıcı adı)'),
        )
      else
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
          title: Text(_names[uid] ?? uid),
          subtitle: const Text('Yalnızca bu üye'),
          trailing: IconButton(tooltip: 'Değiştir', icon: const Icon(Icons.close_rounded), onPressed: () => _setMode('single')),
        ),
      const SizedBox(height: CrewSpace.fieldGap),
      TextFormField(
        initialValue: d.reason,
        maxLength: 300,
        minLines: 1,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Gerekçe (zorunlu)',
          hintText: 'Ör. "Sipariş #1234 kargo bilgisi yanlış gitti; düzeltme"',
          helperText: 'Tek üyeye gönderim denetim kaydına gerekçesiyle yazılır.',
        ),
        onChanged: (x) {
          d.reason = x;
          widget.onChanged();
        },
      ),
    ]);
  }

  Widget _list(TextTheme t) {
    final uids = [for (final x in (a['uids'] as List? ?? const [])) '$x'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final u in uids)
          InputChip(
            label: Text(_names[u] ?? u),
            onDeleted: () {
              d.audience = {'mode': 'list', 'uids': [for (final x in uids) if (x != u) x]};
              _changed();
            },
          ),
        ActionChip(
          avatar: const Icon(Icons.person_add_alt_1_rounded, size: 18),
          label: const Text('Üye ekle'),
          onPressed: () async {
            final m = await _pickMember();
            if (m == null || uids.contains(m.uid)) return;
            _names[m.uid] = m.publicName;
            d.audience = {'mode': 'list', 'uids': [...uids, m.uid]};
            _changed();
          },
        ),
      ]),
      const SizedBox(height: CrewSpace.sm),
      const CrewNote('Liste en çok 5000 üye. Sık kullandığın listeyi "Kitleyi kaydet" ile adlandırabilirsin.'),
      Align(alignment: Alignment.centerLeft, child: _saveBtn()),
    ]);
  }

  Widget _savedPicker(TextTheme t) {
    if (_saved.isEmpty) return const CrewNote('Kayıtlı kitle yok. Süzgeçle bir kitle kurup "Kitleyi kaydet"e bas.');
    final id = '${a['savedId'] ?? ''}';
    return Column(children: [
      for (final s in _saved)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(id == '${s['id']}' ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded, color: id == '${s['id']}' ? Theme.of(context).colorScheme.primary : null),
          onTap: () {
            d.audience = {'mode': 'saved', 'savedId': '${s['id']}'};
            _changed();
          },
          title: Text('${s['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${s['text'] ?? ''}${s['count'] != null ? ' · ~${s['count']} kişi' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
    ]);
  }

  // ---------------------------------------------------------------- süzgeçler

  List<Map<String, Object?>> get _groups => [for (final g in (a['groups'] as List? ?? const [])) Map<String, Object?>.from(g as Map)];

  void _setGroups(List<Map<String, Object?>> gs) {
    d.audience = {'mode': 'filter', 'join': a['join'] ?? 'and', 'groups': gs};
    _changed();
  }

  Widget _joinToggle(String value, ValueChanged<String> onChanged, {bool small = false}) => SegmentedButton<String>(
        style: small ? const ButtonStyle(visualDensity: VisualDensity.compact) : null,
        showSelectedIcon: false,
        segments: const [ButtonSegment(value: 'and', label: Text('VE')), ButtonSegment(value: 'or', label: Text('VEYA'))],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      );

  Widget _filters(TextTheme t) {
    final gs = _groups;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (gi, g) in gs.indexed) ...[
        if (gi > 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              const Expanded(child: Divider()),
              const SizedBox(width: 8),
              _joinToggle('${a['join'] ?? 'and'}', (x) {
                d.audience = {...a, 'join': x};
                _changed();
              }, small: true),
              const SizedBox(width: 8),
              const Expanded(child: Divider()),
            ]),
          ),
        CrewItemCard(
          title: 'Grup ${gi + 1}',
          onRemove: gs.length > 1 ? () => _setGroups([...gs]..removeAt(gi)) : null,
          removeTooltip: 'Grubu sil',
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('kurallar arası', style: t.bodySmall),
            const SizedBox(width: CrewSpace.sm),
            _joinToggle('${g['join'] ?? 'and'}', (x) {
              gs[gi] = {...g, 'join': x};
              _setGroups(gs);
            }, small: true),
          ]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (ri, r) in ((g['rules'] as List?) ?? const []).indexed)
              _RuleRow(
                key: ValueKey('r$gi-$ri-${(r as Map)['f']}'),
                rule: Map<String, Object?>.from(r),
                commNames: _commNames,
                onChanged: (nr) {
                  final rules = [...(g['rules'] as List)];
                  rules[ri] = nr;
                  gs[gi] = {...g, 'rules': rules};
                  _setGroups(gs);
                },
                onRemove: () {
                  final rules = [...(g['rules'] as List)]..removeAt(ri);
                  gs[gi] = {...g, 'rules': rules};
                  _setGroups(gs);
                },
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: PopupMenuButton<String>(
                tooltip: 'Kural ekle',
                onSelected: (f) {
                  final rules = [...((g['rules'] as List?) ?? const []), _defaultRule(f)];
                  gs[gi] = {...g, 'rules': rules};
                  _setGroups(gs);
                },
                itemBuilder: (_) => [for (final e in kNsFields.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add_rounded, size: 20), SizedBox(width: CrewSpace.xs), Text('Kural ekle')]),
                ),
              ),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        OutlinedButton.icon(onPressed: () => _setGroups([...gs, {'join': 'and', 'rules': <Map<String, Object?>>[]}]), icon: const Icon(Icons.add_box_outlined), label: const Text('Grup ekle')),
        _saveBtn(),
      ]),
      const SizedBox(height: CrewSpace.sm),
      const CrewNote('Sağlık, din, siyasi görüş, cinsel yönelim, etnik köken gibi özel nitelikli verilerle hedefleme yapılamaz; bu konulara işaret eden topluluk ve ilgi adları listede yoktur.', icon: Icons.shield_outlined),
    ]);
  }

  Map<String, Object?> _defaultRule(String f) => switch (f) {
        'age' => {'f': f, 'op': 'between', 'v': [25, 40]},
        'memberDays' => {'f': f, 'op': 'between', 'v': [0, 30]},
        'inactiveDays' => {'f': f, 'op': 'gte', 'v': 30},
        'activeDays' => {'f': f, 'op': 'lte', 'v': 7},
        'premium' || 'elmasBuyer' || 'storeCustomer' => {'f': f, 'op': 'is', 'v': true},
        'appVersion' => {'f': f, 'op': 'gte', 'v': '1.0.0'},
        'lang' => {'f': f, 'op': 'in', 'v': ['tr']},
        'gender' => {'f': f, 'op': 'in', 'v': <String>[]},
        'platform' => {'f': f, 'op': 'in', 'v': <String>[]},
        _ => {'f': f, 'op': f == 'province' || f == 'district' ? 'in' : 'any', 'v': <String>[]},
      };

  Widget _saveBtn() => TextButton.icon(
        onPressed: _incomplete()
            ? null
            : () async {
                final ctl = TextEditingController();
                final name = await showDialog<String>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Kitleyi kaydet'),
                    content: TextField(controller: ctl, autofocus: true, maxLength: 60, decoration: const InputDecoration(labelText: 'Ad', hintText: 'Ör. Hafta sonu kaşifleri')),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
                      FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('Kaydet')),
                    ],
                  ),
                );
                if (name == null || name.length < 2 || !mounted) return;
                final s = SessionScope.read(context).services;
                try {
                  final r = await NsApi.saveAudience(s, name, a);
                  if (mounted) crewToast(context, '"$name" kaydedildi (~${r['count']} kişi).');
                  _loadSaved();
                } catch (e) {
                  if (mounted) crewToast(context, '$e'.replaceFirst('AppFailure: ', ''));
                }
              },
        icon: const Icon(Icons.bookmark_add_outlined),
        label: const Text('Kitleyi kaydet'),
      );

  // ---------------------------------------------------------------- canlı sayım

  Widget _countBanner(TextTheme t) {
    final c = _count;
    if (_countErr != null) return CrewNote(_countErr!, icon: Icons.error_outline_rounded, color: Theme.of(context).colorScheme.error);
    if (c == null) return CrewNote(_counting ? 'Sayılıyor…' : 'Kitleyi tamamla; kaç kişiye gideceği burada görünür.', icon: Icons.groups_2_outlined);
    final total = (c['total'] as num?)?.toInt() ?? 0;
    final elig = (c['eligible'] as num?)?.toInt() ?? 0;
    final skipped = Map<String, dynamic>.from(c['skipped'] as Map? ?? const {});
    return Column(spacing: CrewSpace.sm, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Divider(height: CrewSpace.sm, color: Theme.of(context).colorScheme.outlineVariant),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${c['estimated'] == true ? '~' : ''}$elig', style: t.headlineMedium),
        const SizedBox(width: CrewSpace.sm),
        Flexible(child: Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('kişiye gidecek · kitle $total · bildirim alabilen cihazı olan ${c['withDevice'] ?? '-'}', style: t.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis))),
        if (_counting) ...[const SizedBox(width: CrewSpace.sm), const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2))],
      ]),
      if (skipped.isNotEmpty) CrewNote('Gönderilmeyecek: ${skipped.entries.map((e) => '${kNsSkip[e.key] ?? e.key} ${e.value}').join(' · ')}', icon: Icons.filter_alt_off_outlined),
      const CrewNote('Cihazı olmayanlar bildirimi uygulamadaki zil listesinde görür.'),
      if (c['small'] == true)
        CrewNote('Kitle çok küçük ($total < ${c['smallMin']}). Süzgeçle birkaç kişiyi seçmek kişiyi belirlenebilir kılabilir; gönderirken ayrıca onay istenir.', icon: Icons.warning_amber_rounded, color: HadiColors.heyecan),
      if (c['approval'] == true)
        CrewNote('${c['threshold']} kişiden büyük kitle: gönderim ikinci bir yetkilinin onayına gider (dört göz).', icon: Icons.verified_user_outlined, color: HadiColors.iletisim),
    ]);
  }
}

/// Bir süzgeç kuralı satırı (alan + değer düzenleyici).
class _RuleRow extends StatelessWidget {
  const _RuleRow({super.key, required this.rule, required this.onChanged, required this.onRemove, required this.commNames});
  final Map<String, Object?> rule;
  final ValueChanged<Map<String, Object?>> onChanged;
  final VoidCallback onRemove;
  final Map<String, String> commNames;

  String get f => '${rule['f']}';
  List<String> get vals => [for (final x in (rule['v'] is List ? rule['v'] as List : const [])) '$x'];

  Future<void> _multi(BuildContext context, String title, List<String> options, {bool searchable = true}) async {
    final r = await showDialog<List<String>>(context: context, builder: (_) => _MultiPick(title: title, options: options, selected: vals.toSet(), searchable: searchable));
    if (r != null) onChanged({...rule, 'v': r});
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget value;
    switch (f) {
      case 'province':
        value = _chipsBtn(context, vals, 'İl seç', () => _multi(context, 'İller', kIller));
      case 'district':
        value = _chipsBtn(context, vals, 'İlçe seç', () => _multi(context, 'İlçeler', [for (final e in kIlceler.entries) for (final d in e.value) '${e.key}/$d']));
      case 'interests':
        value = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _chipsBtn(context, vals, 'İlgi alanı seç', () => _multi(context, 'İlgi alanları', [for (final g in kInterestGroups) ...g.items])),
          _anyAll(),
        ]);
      case 'eventType':
        value = _chipsBtn(context, vals, 'Etkinlik türü seç', () => _multi(context, 'Etkinlik türleri', const ['Konser', 'Doğa yürüyüşü', 'Atölye', 'Yemek', 'Kahvaltı', 'Oyun gecesi', 'Spor', 'Gezi', 'Söyleşi', 'Parti', 'Kitap kulübü', 'Film gecesi']));
      case 'community':
        value = _chipsBtn(context, [for (final v in vals) commNames[v] ?? v], 'Topluluk seç', () async {
          final r = await showDialog<Map<String, String>>(context: context, builder: (_) => _CommunityPick(selected: vals.toSet()));
          if (r != null) {
            commNames.addAll(r);
            onChanged({...rule, 'v': r.keys.toList()});
          }
        });
      case 'gender':
        value = Wrap(spacing: 6, children: [
          for (final (k, l) in const [('f', 'Kadın'), ('m', 'Erkek'), ('u', 'Belirtmemiş')])
            FilterChip(label: Text(l), selected: vals.contains(k), onSelected: (on) => onChanged({...rule, 'v': on ? [...vals, k] : [for (final x in vals) if (x != k) x]})),
        ]);
      case 'platform':
        value = Wrap(spacing: 6, children: [
          for (final (k, l) in const [('android', 'Android'), ('ios', 'iPhone'), ('web', 'Web')])
            FilterChip(label: Text(l), selected: vals.contains(k), onSelected: (on) => onChanged({...rule, 'v': on ? [...vals, k] : [for (final x in vals) if (x != k) x]})),
        ]);
      case 'lang':
        value = Wrap(spacing: 6, children: [
          for (final (k, l) in const [('tr', 'Türkçe'), ('en', 'İngilizce')])
            FilterChip(label: Text(l), selected: vals.contains(k), onSelected: (on) => onChanged({...rule, 'v': on ? [...vals, k] : [for (final x in vals) if (x != k) x]})),
        ]);
      case 'premium':
      case 'elmasBuyer':
      case 'storeCustomer':
        value = SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [ButtonSegment(value: true, label: Text('Evet')), ButtonSegment(value: false, label: Text('Hayır'))],
          selected: {rule['v'] == true},
          onSelectionChanged: (s) => onChanged({...rule, 'v': s.first}),
        );
      case 'age':
      case 'memberDays':
        final r = [for (final x in (rule['v'] as List)) (x as num).toInt()];
        final (lo, hi) = f == 'age' ? (18, 80) : (0, 1100);
        value = Row(children: [
          Expanded(
            child: RangeSlider(
              min: lo.toDouble(),
              max: hi.toDouble(),
              divisions: hi - lo,
              values: RangeValues(r[0].clamp(lo, hi).toDouble(), r[1].clamp(lo, hi).toDouble()),
              labels: RangeLabels('${r[0]}', '${r[1]}'),
              onChanged: (v) => onChanged({...rule, 'v': [v.start.round(), v.end.round()]}),
            ),
          ),
          Text(f == 'age' ? '${r[0]}–${r[1]} yaş' : '${r[0]}–${r[1]} gün', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
        ]);
      case 'inactiveDays':
      case 'activeDays':
        final n = (rule['v'] as num?)?.toInt() ?? 30;
        value = Wrap(spacing: 6, children: [
          for (final x in const [3, 7, 14, 30, 60, 90])
            ChoiceChip(label: Text('$x gün'), selected: n == x, onSelected: (_) => onChanged({...rule, 'v': x})),
        ]);
      case 'appVersion':
        value = Row(children: [
          DropdownButton<String>(
            value: '${rule['op'] ?? 'gte'}',
            items: const [DropdownMenuItem(value: 'gte', child: Text('≥')), DropdownMenuItem(value: 'lt', child: Text('<')), DropdownMenuItem(value: 'eq', child: Text('='))],
            onChanged: (x) => onChanged({...rule, 'op': x}),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(initialValue: '${rule['v'] ?? ''}', decoration: const InputDecoration(labelText: 'Sürüm', hintText: '1.4.0'), onChanged: (x) => onChanged({...rule, 'v': x.trim()})),
          ),
        ]);
      default:
        value = const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 2, child: Padding(padding: const EdgeInsets.only(top: 10), child: Text(kNsFields[f] ?? f, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis))),
        const SizedBox(width: CrewSpace.md),
        Expanded(flex: 5, child: value),
        IconButton(tooltip: 'Kuralı sil', icon: const Icon(Icons.close_rounded, size: 18), onPressed: onRemove),
      ]),
    );
  }

  Widget _anyAll() => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: SegmentedButton<String>(
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          showSelectedIcon: false,
          segments: const [ButtonSegment(value: 'any', label: Text('herhangi biri')), ButtonSegment(value: 'all', label: Text('hepsi'))],
          selected: {'${rule['op'] ?? 'any'}' == 'all' ? 'all' : 'any'},
          onSelectionChanged: (s) => onChanged({...rule, 'op': s.first}),
        ),
      );

  Widget _chipsBtn(BuildContext context, List<String> shown, String hint, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: crewCardColor(context), borderRadius: BorderRadius.circular(10), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
          child: shown.isEmpty
              ? Text(hint, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
              : Wrap(spacing: 4, runSpacing: 4, children: [for (final s in shown.take(12)) Chip(label: Text(s), visualDensity: VisualDensity.compact), if (shown.length > 12) Chip(label: Text('+${shown.length - 12}'))]),
        ),
      );
}

class _MultiPick extends StatefulWidget {
  const _MultiPick({required this.title, required this.options, required this.selected, this.searchable = true});
  final String title;
  final List<String> options;
  final Set<String> selected;
  final bool searchable;

  @override
  State<_MultiPick> createState() => _MultiPickState();
}

class _MultiPickState extends State<_MultiPick> {
  late final Set<String> _sel = {...widget.selected};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = [for (final o in widget.options) if (q.isEmpty || o.toLowerCase().contains(q)) o];
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        height: 460,
        child: Column(children: [
          if (widget.searchable) TextField(autofocus: true, decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Ara'), onChanged: (x) => setState(() => _q = x)),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) => CheckboxListTile(
                dense: true,
                value: _sel.contains(list[i]),
                title: Text(list[i]),
                onChanged: (on) => setState(() => on == true ? _sel.add(list[i]) : _sel.remove(list[i])),
              ),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context, _sel.toList()), child: Text('Seç (${_sel.length})')),
      ],
    );
  }
}

class _CommunityPick extends StatefulWidget {
  const _CommunityPick({required this.selected});
  final Set<String> selected;

  @override
  State<_CommunityPick> createState() => _CommunityPickState();
}

class _CommunityPickState extends State<_CommunityPick> {
  final _sel = <String, String>{};
  List<Map<String, dynamic>> _items = [];
  Timer? _deb;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(''));
  }

  @override
  void dispose() {
    _deb?.cancel();
    super.dispose();
  }

  Future<void> _load(String q) async {
    try {
      final l = await NsApi.communities(SessionScope.read(context).services, q);
      if (!mounted) return;
      setState(() {
        _items = l;
        for (final x in l) {
          if (widget.selected.contains(x['id']) && !_sel.containsKey(x['id'])) _sel['${x['id']}'] = '${x['name']}';
        }
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Topluluklar'),
        content: SizedBox(
          width: 420,
          height: 460,
          child: Column(children: [
            TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Topluluk ara'),
              onChanged: (x) {
                _deb?.cancel();
                _deb = Timer(const Duration(milliseconds: 400), () => _load(x));
              },
            ),
            Expanded(
              child: ListView(children: [
                for (final c in _items)
                  CheckboxListTile(
                    dense: true,
                    value: _sel.containsKey(c['id']),
                    secondary: Text('${c['emoji'] ?? '👥'}', style: const TextStyle(fontSize: 22)),
                    title: Text('${c['name']}'),
                    subtitle: Text('${c['members']} üye'),
                    onChanged: (on) => setState(() => on == true ? _sel['${c['id']}'] = '${c['name']}' : _sel.remove(c['id'])),
                  ),
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, _sel), child: Text('Seç (${_sel.length})')),
        ],
      );
}

/// Üye arama penceresi (ekip araması: ad, rumuz, @kullanıcı adı).
class _MemberSearchDialog extends StatefulWidget {
  const _MemberSearchDialog();

  @override
  State<_MemberSearchDialog> createState() => _MemberSearchDialogState();
}

class _MemberSearchDialogState extends State<_MemberSearchDialog> {
  List<MemberProfile> _r = [];
  Timer? _deb;
  bool _busy = false;

  @override
  void dispose() {
    _deb?.cancel();
    super.dispose();
  }

  void _search(String q) {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 350), () async {
      if (q.trim().length < 2) return setState(() => _r = []);
      setState(() => _busy = true);
      try {
        final r = await SessionScope.read(context).services.members.staffSearch(q);
        if (mounted) setState(() => (_r = r, _busy = false));
      } catch (_) {
        if (mounted) setState(() => _busy = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Üye ara'),
        content: SizedBox(
          width: 420,
          height: 420,
          child: Column(children: [
            TextField(autofocus: true, decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: 'Ad, rumuz ya da @kullanıcı adı', suffixIcon: _busy ? const Padding(padding: EdgeInsets.all(CrewSpace.md), child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null), onChanged: _search),
            Expanded(
              child: ListView(children: [
                for (final m in _r)
                  ListTile(
                    leading: CircleAvatar(backgroundImage: m.photoUrl != null ? NetworkImage(m.photoUrl!) : null, child: m.photoUrl == null ? const Icon(Icons.person_rounded) : null),
                    title: Text(m.publicName),
                    subtitle: Text([if ((m.username ?? '').isNotEmpty) '@${m.username}', if (m.province.isNotEmpty) m.province].join(' · ')),
                    onTap: () => Navigator.pop(context, m),
                  ),
              ]),
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç'))],
      );
}
