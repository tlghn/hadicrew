// HADİ Crew › Özel günler (29 Ekim 2026): yapay zekâ günü tasarlar, kurucu/yönetici tek tuşla uygular.
//
// Akış: tarih (bugün ya da yaklaşan bir gün) + isteğe bağlı not + ton → "Yapay zekâ tasarlasın" → 3 farklı konsept, her biri
// uygulamanın GERÇEK bileşenleriyle canlı telefon önizlemesinde (hadi › features/special_day: karşılama, dalgalanan bayrak,
// efekt, şerit, rozet) → metin / renk / efekt düzelt, "Benzerini üret" → "Bende dene" (yalnız sende 3 saat) → "Uygula"
// (hemen ya da gün başında) → yayındayken sayaçlar (karşılamayı gören, kutlayan) ve "Kaldır".
// Sunucu: hadimobile/functions/src/special_day.ts (specialDay; grup eglence). Tarif serbest kod içermez (special_day_core.ts).
import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:hadi/core/ui_gate.dart';
import 'package:hadi/data/callables.dart';
import 'package:hadi/data/firebase_services.dart' show kFunctionsRegion;
import 'package:hadi/data/special_day.dart';
import 'package:hadi/features/special_day/special_day_ui.dart';
import 'package:hadi/features/special_day/waving_flag.dart';
import 'package:hadi/theme/hadi_colors.dart';

Map<String, Object?> _m(Object? v) => v is Map ? v.map((k, x) => MapEntry('$k', x as Object?)) : <String, Object?>{};
List<Object?> _l(Object? v) => v is List ? v : const [];
int _i(Object? v) => v is num ? v.toInt() : 0;

Future<Map<String, Object?>> _call(Map<String, Object?> data, {int sec = 30}) async {
  try {
    final r = await FirebaseFunctions.instanceFor(region: kFunctionsRegion)
        .hadiCallable('specialDay', options: HttpsCallableOptions(timeout: Duration(seconds: sec)))
        .call(data);
    return _m(r.data);
  } on FirebaseFunctionsException catch (e) {
    throw Exception(e.message ?? 'İşlem tamamlanamadı (${e.code}).');
  }
}

const _tones = [('', 'Güne göre'), ('coskulu', 'Coşkulu'), ('zarif', 'Zarif'), ('duygusal', 'Duygusal'), ('eglenceli', 'Eğlenceli')];
const _aylar = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
const _gunler = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];

String _label(String d) {
  final p = d.split('-');
  if (p.length != 3) return d;
  final dt = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  return '${dt.day} ${_aylar[dt.month - 1]} ${dt.year} ${_gunler[dt.weekday - 1]}';
}

String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class SpecialDaysAdminScreen extends StatefulWidget {
  const SpecialDaysAdminScreen({super.key});

  @override
  State<SpecialDaysAdminScreen> createState() => _SpecialDaysAdminScreenState();
}

class _SpecialDaysAdminScreenState extends State<SpecialDaysAdminScreen> {
  bool _loading = true, _designing = false, _busy = false, _ok = true;
  String? _msg;
  String _today = _ymd(DateTime.now()), _date = _ymd(DateTime.now()), _tone = '';
  Map<String, Object?>? _todayKnown, _active, _preview, _stats;
  List<Map<String, Object?>> _upcoming = const [];
  final _note = TextEditingController();
  List<SpecialDaySpec> _concepts = const [];
  Map<String, Object?>? _known;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _say(String m, {bool ok = true}) => setState(() {
        _msg = m;
        _ok = ok;
      });
  String _err(Object e) => '$e'.replaceFirst('Exception: ', '');

  Future<void> _load() async {
    try {
      final r = await _call({'op': 'get'});
      setState(() {
        _today = '${r['today'] ?? _today}';
        if (_concepts.isEmpty) _date = _today;
        _todayKnown = r['todayKnown'] is Map ? _m(r['todayKnown']) : null;
        _upcoming = [for (final x in _l(r['upcoming'])) _m(x)];
        _active = r['active'] is Map ? _m(r['active']) : null;
        _preview = r['preview'] is Map ? _m(r['preview']) : null;
        _stats = r['stats'] is Map ? _m(r['stats']) : null;
      });
    } catch (e) {
      _say(_err(e), ok: false);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _design({SpecialDaySpec? base}) async {
    setState(() {
      _designing = true;
      _msg = null;
    });
    try {
      final r = await _call({'op': 'design', 'date': _date, 'tone': _tone, 'note': _note.text.trim(), if (base != null) 'base': base.toMap()}, sec: 120);
      final list = [for (final x in _l(r['concepts'])) ?SpecialDaySpec.fromMap(x)];
      setState(() {
        _concepts = list;
        _known = r['known'] is Map ? _m(r['known']) : null;
      });
      if (list.isEmpty) _say('Yapay zekâ kullanılabilir bir tasarım üretemedi. Yeniden dene.', ok: false);
    } catch (e) {
      _say(_err(e), ok: false);
    }
    if (mounted) setState(() => _designing = false);
  }

  Future<void> _apply(SpecialDaySpec s, {bool preview = false}) async {
    var when = 'now';
    if (!preview) {
      final future = _date.compareTo(_today) > 0;
      final r = await uiOnce(context, () => showDialog<String>(
            context: context,
            builder: (c) => AlertDialog(
              title: Text('"${s.name}" uygulansın mı?'),
              content: Text([
                future ? '${_label(_date)} başladığında (00:00) bütün üyelerde görünür, gün bitince kendiliğinden kalkar.' : 'Hemen bütün üyelerde görünür; gün bitince (24:00) kendiliğinden kalkar.',
                'Uygulamayı açan her üye günde bir kez karşılamayı görür; üst çubukta rozet, hemen altında günün şeridi durur.',
                if (_active != null) 'Yayındaki "${_m(_active!['spec'])['name']}" bunun yerine geçer.',
              ].join('\n\n')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
                if (future) OutlinedButton(onPressed: () => Navigator.pop(c, 'now'), child: const Text('Hemen başlat')),
                FilledButton(onPressed: () => Navigator.pop(c, future ? 'dayStart' : 'now'), child: Text(future ? 'Gün başında' : 'Uygula')),
              ],
            ),
          ));
      if (r == null) return;
      when = r;
    }
    setState(() => _busy = true);
    try {
      await _call({'op': 'apply', 'spec': s.toMap(), 'date': _date, 'when': when, if (preview) 'preview': true});
      await _load();
      _say(preview
          ? 'Yalnız sende açıldı (3 saat). Uygulamayı yeniden aç ya da üst çubuktaki rozete dokun; kimse görmüyor.'
          : 'Uygulandı: "${s.name}". Üyeler uygulamayı açınca karşılanacak.');
    } catch (e) {
      _say(_err(e), ok: false);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _clear({bool preview = false}) async {
    setState(() => _busy = true);
    try {
      await _call({'op': 'clear', if (preview) 'preview': true});
      await _load();
      _say(preview ? 'Denemen kaldırıldı.' : 'Özel gün kaldırıldı; uygulama normale döndü.');
    } catch (e) {
      _say(_err(e), ok: false);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final p = _date.split('-').map(int.parse).toList();
    final d = await showDatePicker(context: context, initialDate: DateTime(p[0], p[1], p[2]), firstDate: DateTime(now.year, now.month, now.day), lastDate: now.add(const Duration(days: 400)));
    if (d != null) setState(() => _date = _ymd(d));
  }

  void _fullScreen(SpecialDaySpec s) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (c) => Scaffold(
        body: SpecialDayGreetingView(day: SpecialDay(id: 'onizleme', date: _date, start: 0, end: 1 << 62, spec: s, preview: true), preview: true, onDone: () => Navigator.pop(c)),
      ),
    ));
  }

  // ------------------------------------------------------------------ görünüm

  Widget _statusCard() {
    final a = _active;
    final text = Theme.of(context).textTheme;
    if (a == null && _preview == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.celebration_outlined),
          title: const Text('Şu an yayında özel gün yok'),
          subtitle: Text(_todayKnown != null ? 'Bugün ${_todayKnown!['name']}: aşağıdan tasarla.' : 'Aşağıdan bir gün seç ve tasarla.'),
        ),
      );
    }
    final spec = a == null ? null : SpecialDaySpec.fromMap(a['spec']);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (spec != null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(gradient: LinearGradient(colors: [spec.bg1, spec.bg2])),
            child: Row(children: [
              if (spec.flag) WavingFlag(width: 54, still: spec.commemoration) else Text(spec.badge == 'flag' ? '🎉' : spec.badge, style: const TextStyle(fontSize: 34)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a!['live'] == true ? 'YAYINDA' : 'ZAMANLANDI', style: TextStyle(color: spec.text.withValues(alpha: .8), letterSpacing: 2, fontWeight: FontWeight.w800, fontSize: 11)),
                  Text(spec.name, style: TextStyle(color: spec.text, fontWeight: FontWeight.w800, fontSize: 18)),
                  Text(_label('${a['date']}'), style: TextStyle(color: spec.text.withValues(alpha: .85))),
                ]),
              ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (_stats != null) ...[
              Chip(avatar: const Icon(Icons.visibility_rounded, size: 18), label: Text('${_i(_stats!['seen'])} üye karşılandı')),
              Chip(avatar: const Text('🎉'), label: Text('${_i(_stats!['celebrated'])} kutladı')),
            ],
            if (spec != null) OutlinedButton.icon(onPressed: () => _fullScreen(spec), icon: const Icon(Icons.fullscreen_rounded), label: const Text('Tam ekran gör')),
            if (a != null) OutlinedButton.icon(onPressed: _busy ? null : () => _clear(), icon: const Icon(Icons.stop_circle_outlined), label: const Text('Kaldır')),
            if (_preview != null)
              TextButton.icon(onPressed: _busy ? null : () => _clear(preview: true), icon: const Icon(Icons.science_outlined), label: Text('Denememi kaldır (${_m(_preview!['spec'])['name']})')),
          ]),
        ),
        if (spec != null && spec.notifyBody.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: SelectableText('Bildirim taslağı (Bildirim stüdyosu için): ${spec.notifyTitle} — ${spec.notifyBody}', style: text.bodySmall),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final text = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
      Text('Özel günler', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      const Text('Günü yapay zekâya ver, 3 konsept tasarlasın; beğendiğini tek tuşla uygula. Üyeler açılışta kutlamayla karşılanır, '
          'bayrak dalgalanır, üst çubukta rozet ve altında günün şeridi görünür.'),
      const SizedBox(height: 12),
      _statusCard(),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.auto_awesome_rounded, color: HadiColors.iletisim),
              const SizedBox(width: 8),
              Text('Yapay zekâ tasarlasın', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ActionChip(avatar: const Icon(Icons.event_rounded, size: 18), label: Text(_label(_date)), onPressed: _pickDate),
              for (final u in _upcoming.take(6))
                ChoiceChip(
                  label: Text('${u['name']} · ${_label('${u['date']}').split(' ').take(2).join(' ')}'),
                  selected: _date == u['date'],
                  onSelected: (_) => setState(() => _date = '${u['date']}'),
                ),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final (k, n) in _tones) ChoiceChip(label: Text(n), selected: _tone == k, onSelected: (_) => setState(() => _tone = k)),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLength: 400,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notun (isteğe bağlı)', hintText: 'Ör. Cumhuriyetin 103. yılı; coşkulu ama saygılı, gençlere seslensin'),
            ),
            const SizedBox(height: 4),
            Row(children: [
              FilledButton.icon(
                key: const ValueKey('t.crew.special.design'),
                onPressed: _designing ? null : () => _design(),
                icon: _designing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome_rounded),
                label: Text(_designing ? 'Tasarlanıyor… (15–40 sn)' : _concepts.isEmpty ? 'Tasarla' : 'Yeni 3 konsept'),
              ),
            ]),
            if (_msg != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_msg!, style: TextStyle(color: _ok ? HadiColors.dostluk : HadiColors.error, fontWeight: FontWeight.w700))),
          ]),
        ),
      ),
      if (_concepts.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('${_known?['name'] ?? _label(_date)} · ${_concepts.length} konsept', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 1100 ? 3 : c.maxWidth >= 720 ? 2 : 1;
          final w = (c.maxWidth - (cols - 1) * 12) / cols;
          return Wrap(spacing: 12, runSpacing: 12, children: [
            for (var k = 0; k < _concepts.length; k++)
              SizedBox(
                width: w,
                child: _ConceptCard(
                  index: k,
                  spec: _concepts[k],
                  date: _date,
                  busy: _busy || _designing,
                  onChanged: (s) => setState(() => _concepts = [..._concepts]..[k] = s),
                  onSimilar: () => _design(base: _concepts[k]),
                  onTry: () => _apply(_concepts[k], preview: true),
                  onApply: () => _apply(_concepts[k]),
                  onFull: () => _fullScreen(_concepts[k]),
                ),
              ),
          ]);
        }),
      ],
    ]);
  }
}

class _ConceptCard extends StatefulWidget {
  const _ConceptCard({required this.index, required this.spec, required this.date, required this.busy, required this.onChanged, required this.onSimilar, required this.onTry, required this.onApply, required this.onFull});
  final int index;
  final SpecialDaySpec spec;
  final String date;
  final bool busy;
  final ValueChanged<SpecialDaySpec> onChanged;
  final VoidCallback onSimilar, onTry, onApply, onFull;

  @override
  State<_ConceptCard> createState() => _ConceptCardState();
}

class _ConceptCardState extends State<_ConceptCard> {
  int _tab = 0; // 0 karşılama, 1 ana ekran
  int _replay = 0;
  late final _title = TextEditingController(text: widget.spec.title);
  late final _message = TextEditingController(text: widget.spec.message);
  late final _button = TextEditingController(text: widget.spec.button);
  late final _bTitle = TextEditingController(text: widget.spec.bannerTitle);
  late final _bSub = TextEditingController(text: widget.spec.bannerSubtitle);

  @override
  void didUpdateWidget(_ConceptCard old) {
    super.didUpdateWidget(old);
    if (old.spec.name != widget.spec.name || old.spec.mood != widget.spec.mood) {
      _title.text = widget.spec.title;
      _message.text = widget.spec.message;
      _button.text = widget.spec.button;
      _bTitle.text = widget.spec.bannerTitle;
      _bSub.text = widget.spec.bannerSubtitle;
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _message, _button, _bTitle, _bSub]) {
      c.dispose();
    }
    super.dispose();
  }

  void _edit() => widget.onChanged(widget.spec.copyWith(
        title: _title.text.trim().isEmpty ? widget.spec.title : _title.text.trim(),
        message: _message.text.trim(),
        button: widget.spec.commemoration ? '' : _button.text.trim(),
        bannerTitle: _bTitle.text.trim(),
        bannerSubtitle: _bSub.text.trim(),
      ));

  Widget _phone(SpecialDaySpec s) {
    final day = SpecialDay(id: 'onizleme', date: widget.date, start: 0, end: 1 << 62, spec: s, preview: true);
    final screen = _tab == 0
        ? SpecialDayGreetingView(key: ValueKey('g$_replay${s.title}${s.effect}${s.bg1}${s.flag}'), day: day, preview: true, onDone: () => setState(() => _replay++))
        : _HomeMock(day: day);
    return AspectRatio(
      aspectRatio: 9 / 18,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: const Color(0xFF0B0B0F), borderRadius: BorderRadius.circular(28)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: 390,
              height: 780,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(size: const Size(390, 780), padding: const EdgeInsets.only(top: 30, bottom: 16)),
                child: Material(child: screen),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.spec;
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('KONSEPT ${widget.index + 1}', style: text.labelSmall?.copyWith(letterSpacing: 2, fontWeight: FontWeight.w800, color: HadiColors.ink3)),
          Text(s.name, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          if (s.mood.isNotEmpty) Text(s.mood, style: text.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [ButtonSegment(value: 0, label: Text('Karşılama')), ButtonSegment(value: 1, label: Text('Ana ekran'))],
            selected: {_tab},
            onSelectionChanged: (v) => setState(() => _tab = v.first),
          ),
          const SizedBox(height: 8),
          Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 300), child: _phone(s))),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            TextButton.icon(onPressed: () => setState(() => _replay++), icon: const Icon(Icons.replay_rounded, size: 18), label: const Text('Yeniden oynat')),
            TextButton.icon(onPressed: widget.onFull, icon: const Icon(Icons.fullscreen_rounded, size: 18), label: const Text('Tam ekran')),
          ]),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Düzenle', style: TextStyle(fontWeight: FontWeight.w700)),
            children: [
              TextField(controller: _title, maxLength: 70, decoration: const InputDecoration(labelText: 'Karşılama başlığı'), onChanged: (_) => _edit()),
              TextField(controller: _message, maxLength: 260, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Mesaj'), onChanged: (_) => _edit()),
              if (!s.commemoration) TextField(controller: _button, maxLength: 28, decoration: const InputDecoration(labelText: 'Kutlama düğmesi'), onChanged: (_) => _edit()),
              TextField(controller: _bTitle, maxLength: 50, decoration: const InputDecoration(labelText: 'Şerit başlığı'), onChanged: (_) => _edit()),
              TextField(controller: _bSub, maxLength: 90, decoration: const InputDecoration(labelText: 'Şerit alt yazısı'), onChanged: (_) => _edit()),
              if (!s.commemoration)
                DropdownButtonFormField<SpecialEffect>(
                  initialValue: s.effect,
                  decoration: const InputDecoration(labelText: 'Efekt'),
                  items: [
                    for (final e in SpecialEffect.values)
                      if (e != SpecialEffect.flags || s.flag) DropdownMenuItem(value: e, child: Text(kSpecialEffectLabels[e]!)),
                  ],
                  onChanged: (e) => e == null ? null : widget.onChanged(s.copyWith(effect: e)),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Türk bayrağı'),
                value: s.flag,
                onChanged: (v) => widget.onChanged(s.copyWith(flag: v, badge: v ? 'flag' : (s.emojis.isEmpty ? '🎉' : s.emojis.first), effect: !v && s.effect == SpecialEffect.flags ? SpecialEffect.confetti : null)),
              ),
              const SizedBox(height: 4),
              Text('Renkler', style: text.labelLarge),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (label, c, set) in <(String, Color, SpecialDaySpec Function(Color))>[
                  ('Zemin 1', s.bg1, (x) => s.copyWith(bg1: x)),
                  ('Zemin 2', s.bg2, (x) => s.copyWith(bg2: x)),
                  ('Vurgu', s.accent, (x) => s.copyWith(accent: x)),
                ])
                  _ColorChip(label: label, color: c, onPick: (x) => widget.onChanged(set(x))),
              ]),
              const SizedBox(height: 8),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
            TextButton.icon(onPressed: widget.busy ? null : widget.onSimilar, icon: const Icon(Icons.auto_awesome_motion_rounded, size: 18), label: const Text('Benzerini üret')),
            OutlinedButton.icon(onPressed: widget.busy ? null : widget.onTry, icon: const Icon(Icons.science_outlined, size: 18), label: const Text('Bende dene')),
            FilledButton.icon(
              key: ValueKey('t.crew.special.apply.${widget.index}'),
              onPressed: widget.busy ? null : widget.onApply,
              icon: const Icon(Icons.rocket_launch_rounded, size: 18),
              label: const Text('Uygula'),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Ana ekran önizlemesi: üst çubukta logo + rozet, altında günün şeridi, altta örnek kartlar.
class _HomeMock extends StatelessWidget {
  const _HomeMock({required this.day});
  final SpecialDay day;

  @override
  Widget build(BuildContext context) {
    final s = day.spec;
    return ColoredBox(
      color: const Color(0xFFF4F6F8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 38, 12, 10),
          child: Row(children: [
            const Text('HADİ', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: HadiColors.navy, letterSpacing: 1)),
            const SizedBox(width: 10),
            if (s.flag && s.badge == 'flag') WavingFlag(width: 30, wind: .6, still: s.commemoration) else Text(s.badge == 'flag' ? '🎉' : s.badge, style: const TextStyle(fontSize: 22)),
            const Spacer(),
            const Icon(Icons.notifications_none_rounded),
            const SizedBox(width: 10),
            const Icon(Icons.support_rounded),
          ]),
        ),
        SpecialDayBanner(day: day, onClose: () {}),
        const SizedBox(height: 12),
        for (var k = 0; k < 3; k++)
          Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            height: 120,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 140, height: 12, decoration: BoxDecoration(color: const Color(0xFFE3E8EE), borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 10),
                Container(width: 220, height: 10, decoration: BoxDecoration(color: const Color(0xFFEEF1F4), borderRadius: BorderRadius.circular(6))),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _ColorChip extends StatelessWidget {
  const _ColorChip({required this.label, required this.color, required this.onPick});
  final String label;
  final Color color;
  final ValueChanged<Color> onPick;

  static const _presets = [
    Color(0xFFE30A17), Color(0xFFB3121F), Color(0xFF5E0A10), Color(0xFF7A0C14), Color(0xFF0B1F3A), Color(0xFF13294B),
    Color(0xFF1A1A1A), Color(0xFF3A3A3A), Color(0xFFFFD27A), Color(0xFFFFF3E0), Color(0xFFFFFFFF), Color(0xFF2E7D32),
    Color(0xFF1565C0), Color(0xFF6A1B9A), Color(0xFFD81B60), Color(0xFFFF8F00),
  ];

  @override
  Widget build(BuildContext context) => ActionChip(
        avatar: CircleAvatar(backgroundColor: color, radius: 9),
        label: Text(label),
        onPressed: () async {
          final c = await showDialog<Color>(
            context: context,
            builder: (d) => AlertDialog(
              title: Text(label),
              content: Wrap(spacing: 10, runSpacing: 10, children: [
                for (final p in _presets)
                  InkWell(
                    onTap: () => Navigator.pop(d, p),
                    customBorder: const CircleBorder(),
                    child: CircleAvatar(radius: 18, backgroundColor: p, child: p == color ? const Icon(Icons.check_rounded, color: Colors.grey) : null),
                  ),
              ]),
            ),
          );
          if (c != null) onPick(c);
        },
      );
}
