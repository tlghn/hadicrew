// HADİ Crew — Bildirim Stüdyosu: yeni bildirim / taslak düzenleme (24 Ekim 2026).
// 1 Kategori · 2 Kitle (canlı sayım) · 3 İçerik (A/B, emoji, {ad}, büyük görsel, ses, hedef bağlantı, 2 düğme, zengin kart +
// sesli mesaj) · 4 Zaman (şimdi / tarih / tekrarlı; sessiz saat ve sıklık sınırı) · önizleme (Android / iPhone / Web / kart).
// Alt çubuk: Taslak kaydet · Test gönder (yalnızca bana) · Gönder / Onaya gönder. Arayüz: package:hadi/panel_ui/crew_ui.dart.
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/panel_ui/crew_ui.dart';

import 'ns_api.dart';
import 'ns_audience.dart';
import 'ns_previews.dart';

String _errText(Object e) => '$e'.replaceFirst('AppFailure: ', '');

class NsComposerPage extends StatefulWidget {
  const NsComposerPage({super.key, this.initial, required this.config});
  final NsDraft? initial;
  final Map<String, dynamic> config;

  @override
  State<NsComposerPage> createState() => _NsComposerPageState();
}

class _NsComposerPageState extends State<NsComposerPage> {
  late final NsDraft d = widget.initial ?? (NsDraft()..variants[0].sound = 'hadi_ding');
  String _vTab = 'A';
  Map<String, dynamic>? _count;
  bool _busy = false;
  final _player = AudioPlayer();

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  NsVariant get v => d.variants[_vTab == 'B' && d.abOn ? 1 : 0];
  int _cfg(String k, int def) => (widget.config[k] as num?)?.toInt() ?? def;
  void _touch() => setState(() {});

  String? _problem() {
    for (final x in [d.variants[0], if (d.abOn) d.variants[1]]) {
      if (x.title.trim().isEmpty || x.body.trim().isEmpty) return '${d.abOn ? '${x.id}: ' : ''}Başlık ve metin gerekli.';
      if (x.title.length > 65) return 'Başlık en çok 65 karakter.';
      if (x.body.length > 240) return 'Metin en çok 240 karakter.';
      if (x.cardOn && x.cardBody.trim().isEmpty) return 'Kart metni boş.';
      for (final b in x.buttons) {
        if (b.label.trim().isEmpty || b.link.trim().isEmpty) return 'Düğmelerin yazısı ve bağlantısı dolu olmalı.';
      }
    }
    if (d.audience['mode'] == 'single' && d.reason.trim().length < 5) return 'Tek üyeye gönderimde gerekçe zorunlu.';
    if (d.scheduleMode == 'at' && (d.at == null || d.at!.isBefore(DateTime.now()))) return 'Gönderim zamanı seç (ileri bir tarih).';
    if (d.scheduleMode == 'recurring' && d.dow.isEmpty) return 'Tekrar için en az bir gün seç.';
    if (_count == null) return 'Kitleyi tamamla.';
    return null;
  }

  Future<void> _save({bool quiet = false}) async {
    final s = SessionScope.read(context).services;
    d.name = d.name.trim().isEmpty ? d.variants[0].title : d.name;
    d.cid = await NsApi.save(s, d);
    if (!quiet && mounted) crewToast(context, 'Taslak kaydedildi.');
  }

  Future<void> _run(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) crewToast(context, _errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() => _run(() async {
        final r = await NsApi.test(SessionScope.read(context).services, d, variant: _vTab);
        if (!mounted) return;
        final n = (r['devices'] as num?)?.toInt() ?? 0;
        crewToast(
          context,
          n == 0
              ? 'Test bildirimi zil listene yazıldı. Bu hesapta bildirim alabilen cihaz yok; telefonunda HADİ\'ye bu hesapla gir.'
              : 'Test bildirimi $n cihazına gönderildi. Zil listende de "[TEST]" olarak görünür.',
        );
      });

  Future<void> _send() async {
    final p = _problem();
    if (p != null) {
      crewToast(context, p);
      return;
    }
    final elig = (_count?['eligible'] as num?)?.toInt() ?? 0;
    final approval = _count?['approval'] == true;
    final when = switch (d.scheduleMode) {
      'at' => 'şu zamanda: ${_fmt(d.at!)}',
      'recurring' => 'her ${_dowText(d.dow)} ${_two(d.hour)}:${_two(d.minute)}',
      _ => 'hemen',
    };
    final cat = kNsCategories[d.category]!;
    final ok = await crewConfirm(
      context,
      title: approval ? 'Onaya gönderilsin mi?' : 'Gönderilsin mi?',
      confirm: approval ? 'Onaya gönder' : 'Gönder',
      message: '${cat.emoji} ${cat.label} · ~$elig kişi · $when.\n\n'
          'İçerik gönderimden önce yapay zekâyla denetlenir.${approval ? ' Kitle eşikten büyük; ikinci bir yetkili onaylayınca gider.' : ''}'
          '${d.category == 'marketing' ? ' Yalnızca kampanya izni olan 18+ üyelere, günde en çok ${_cfg('marketingPerDay', 2)} kez.' : ''}',
    );
    if (!ok || !mounted) return;
    await _run(() async {
      final s = SessionScope.read(context).services;
      await _save(quiet: true);
      Map<String, dynamic> r;
      try {
        r = await NsApi.submit(s, d.cid!);
      } catch (e) {
        final msg = _errText(e);
        if (!msg.startsWith('Kitle çok küçük') || !mounted) rethrow;
        final go = await crewConfirm(context, title: 'Çok küçük kitle', message: '$msg\n\nBu kişileri belirli bir amaçla hedeflediğinden emin ol; gönderim denetim kaydına yazılır.', confirm: 'Yine de gönder', danger: true);
        if (!go) return;
        r = await NsApi.submit(s, d.cid!, ackSmall: true);
      }
      if (!mounted) return;
      crewToast(context, switch ('${r['status']}') {
        'pending_approval' => 'Onaya gönderildi (${r['count']} kişi). Onaylanınca gider.',
        'scheduled' => 'Planlandı (${r['count']} kişi).',
        'recurring' => 'Tekrarlı gönderim kuruldu.',
        _ => 'Gönderim başladı: ${r['count']} kişi. Sessiz saate ve sıklık sınırına takılanlar sonra gider.',
      });
      Navigator.of(context).pop();
    });
  }

  Future<String?> _upload(String kind) async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: kind == 'image' ? const ['jpg', 'jpeg', 'png', 'webp'] : const ['mp3', 'm4a', 'aac', 'ogg', 'wav', 'webm'],
      withData: true,
    );
    final f = r?.files.single;
    if (f == null || f.bytes == null || !mounted) return null;
    final mime = switch ((f.extension ?? '').toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      'aac' => 'audio/aac',
      'ogg' => 'audio/ogg',
      'wav' => 'audio/wav',
      _ => 'audio/webm',
    };
    String? url;
    await _run(() async => url = await NsApi.upload(SessionScope.read(context).services, kind, mime, f.bytes!));
    return url;
  }

  // ---------------------------------------------------------------- arayüz

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1180;
    final gut = CrewSpace.gutter(context);
    final sections = <Widget>[
      CrewCard(title: '1 · Ne gönderiyorsun?', icon: Icons.category_outlined, children: _categoryPicker()),
      CrewCard(
        title: '2 · Kime?',
        icon: Icons.groups_2_outlined,
        subtitle: 'Kitle değiştikçe kaç kişiye gideceği canlı hesaplanır.',
        children: [NsAudienceEditor(draft: d, onChanged: _touch, onCount: (c) => setState(() => _count = c))],
      ),
      CrewCard(
        title: '3 · İçerik',
        icon: Icons.edit_note_rounded,
        action: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('A/B testi', style: Theme.of(context).textTheme.bodyMedium),
          Switch(
            value: d.abOn,
            onChanged: d.audience['mode'] == 'single'
                ? null
                : (on) => setState(() {
                      d.abOn = on;
                      if (on && d.variants[1].title.isEmpty) d.variants[1] = NsVariant.from('B', Map<String, dynamic>.from(d.variants[0].toJson()));
                      if (!on) _vTab = 'A';
                    }),
          ),
        ]),
        children: _content(),
      ),
      CrewCard(title: '4 · Ne zaman?', icon: Icons.schedule_rounded, children: _schedule()),
      if (!wide) CrewCard(title: 'Önizleme', icon: Icons.visibility_outlined, children: [NsPreviews(v: v, compact: true)]),
    ];
    final form = ListView.separated(
      padding: EdgeInsets.fromLTRB(gut, CrewSpace.xl, wide ? CrewSpace.xl : gut, CrewSpace.xxl),
      itemCount: sections.length,
      separatorBuilder: (_, _) => const SizedBox(height: CrewSpace.sectionGap),
      itemBuilder: (_, i) => sections[i],
    );
    return CrewPage(
      title: d.cid == null ? 'Yeni bildirim' : 'Taslağı düzenle',
      subtitle: 'Uygulama içi bildirim (telefon + web) ve kart',
      maxWidth: 1440,
      bottomBar: _actionBar(),
      body: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: form),
              SizedBox(
                width: 400,
                child: ListView(padding: EdgeInsets.fromLTRB(0, CrewSpace.xl, gut, CrewSpace.xxl), children: [
                  CrewCard(
                    title: 'Önizleme${d.abOn ? ' · $_vTab' : ''}',
                    subtitle: '{ad} yerine örnek ad; görünüm yaklaşıktır.',
                    icon: Icons.visibility_outlined,
                    children: [NsPreviews(v: v)],
                  ),
                ]),
              ),
            ])
          : form,
    );
  }

  Widget _actionBar() {
    final p = _problem();
    final approval = _count?['approval'] == true;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final wide = crewWide(context);
    final status = Text(
      p ?? '${kNsCategories[d.category]!.emoji} ~${_count?['eligible'] ?? '-'} kişi · ${d.scheduleMode == 'now' ? 'hemen' : d.scheduleMode == 'at' ? 'planlı' : 'tekrarlı'}${d.abOn ? ' · A/B' : ''}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: t.bodyMedium?.copyWith(color: p != null ? cs.onSurfaceVariant : null),
    );
    final buttons = [
      if (_busy) const Padding(padding: EdgeInsets.symmetric(horizontal: CrewSpace.sm), child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      PopupMenuButton<String>(
        tooltip: 'Diğer',
        enabled: !_busy,
        onSelected: (_) => _run(() => _save()),
        itemBuilder: (_) => const [PopupMenuItem(value: 'save', child: Text('Taslak kaydet'))],
      ),
      const SizedBox(width: CrewSpace.sm),
      OutlinedButton.icon(onPressed: _busy || v.title.isEmpty || v.body.isEmpty ? null : _test, icon: const Icon(Icons.send_to_mobile_rounded, size: 18), label: const Text('Test gönder')),
      const SizedBox(width: CrewSpace.sm),
      FilledButton.icon(
        onPressed: _busy || p != null ? null : _send,
        icon: Icon(approval ? Icons.how_to_reg_rounded : Icons.send_rounded, size: 18),
        label: Text(approval ? 'Onaya gönder' : 'Gönder'),
      ),
    ];
    return Material(
      color: crewCardColor(context),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant))),
          padding: EdgeInsets.symmetric(horizontal: CrewSpace.gutter(context), vertical: CrewSpace.md),
          child: wide
              ? Row(children: [Expanded(child: status), ...buttons])
              : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  status,
                  const SizedBox(height: CrewSpace.sm),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: buttons),
                ]),
        ),
      ),
    );
  }

  List<Widget> _categoryPicker() {
    final c = kNsCategories[d.category]!;
    return [
      Wrap(spacing: CrewSpace.sm, runSpacing: CrewSpace.sm, children: [
        for (final e in kNsCategories.entries)
          ChoiceChip(label: Text('${e.value.emoji} ${e.value.label}'), selected: d.category == e.key, onSelected: (_) => setState(() => d.category = e.key)),
      ]),
      CrewNote(c.hint),
      TextFormField(
        initialValue: d.name,
        maxLength: 80,
        decoration: const InputDecoration(labelText: 'İç ad (yalnızca ekip görür)', hintText: 'Ör. Kasım mağaza indirimi'),
        onChanged: (x) => d.name = x,
      ),
    ];
  }

  List<Widget> _content() => [
        if (d.abOn) ...[
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [ButtonSegment(value: 'A', label: Text('Varyant A')), ButtonSegment(value: 'B', label: Text('Varyant B'))],
            selected: {_vTab},
            onSelectionChanged: (s) => setState(() => _vTab = s.first),
          ),
          CrewFormGrid(children: [
            Row(children: [
              Expanded(child: Slider(min: 4, max: 50, divisions: 23, value: d.abSample.toDouble(), label: '%${d.abSample}', onChanged: (x) => setState(() => d.abSample = x.round()))),
              Text('Örneklem %${d.abSample}'),
            ]),
            DropdownButtonFormField<int>(
              initialValue: d.abWait,
              decoration: const InputDecoration(labelText: 'Kazanan seçimi'),
              items: [for (final h in const [1, 2, 4, 8, 12, 24]) DropdownMenuItem(value: h, child: Text('$h saat sonra'))],
              onChanged: (x) => setState(() => d.abWait = x ?? 4),
            ),
          ]),
          CrewNote('Kitlenin %${d.abSample}\'i yarı yarıya A ve B\'yi alır; ${d.abWait} saat sonra açılma oranı yüksek olan kalanlara gider.'),
        ],
        _VariantEditor(key: ValueKey('v$_vTab${d.abOn}'), v: v, onChanged: _touch, upload: _upload, player: _player),
      ];

  List<Widget> _schedule() => [
        Wrap(spacing: CrewSpace.sm, runSpacing: CrewSpace.sm, children: [
          for (final (id, l, i) in const [('now', 'Hemen', Icons.flash_on_rounded), ('at', 'Tarih ve saat', Icons.event_rounded), ('recurring', 'Tekrarlı', Icons.repeat_rounded)])
            ChoiceChip(avatar: Icon(i, size: 18), label: Text(l), selected: d.scheduleMode == id, onSelected: (_) => setState(() => d.scheduleMode = id)),
        ]),
        if (d.scheduleMode == 'at')
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.schedule_rounded, size: 18),
              label: Text(d.at == null ? 'Zaman seç' : _fmt(d.at!)),
              onPressed: () async {
                final now = DateTime.now();
                final day = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 90)), initialDate: d.at ?? now);
                if (day == null || !mounted) return;
                final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(d.at ?? now.add(const Duration(hours: 1))));
                if (tm == null) return;
                setState(() => d.at = DateTime(day.year, day.month, day.day, tm.hour, tm.minute));
              },
            ),
          ),
        if (d.scheduleMode == 'recurring') ...[
          Wrap(spacing: CrewSpace.sm - 2, runSpacing: CrewSpace.sm - 2, children: [
            for (final (n, l) in const [(1, 'Pzt'), (2, 'Sal'), (3, 'Çar'), (4, 'Per'), (5, 'Cum'), (6, 'Cmt'), (0, 'Paz')])
              FilterChip(label: Text(l), selected: d.dow.contains(n), onSelected: (on) => setState(() => on ? d.dow.add(n) : d.dow.remove(n))),
          ]),
          Wrap(spacing: CrewSpace.sm, runSpacing: CrewSpace.sm, children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.schedule_rounded, size: 18),
              label: Text('Saat ${_two(d.hour)}:${_two(d.minute)}'),
              onPressed: () async {
                final tm = await showTimePicker(context: context, initialTime: TimeOfDay(hour: d.hour, minute: d.minute));
                if (tm != null) setState(() => (d.hour = tm.hour, d.minute = tm.minute));
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_busy_rounded, size: 18),
              label: Text(d.until == null ? 'Bitiş yok' : 'Bitiş ${_fmt(d.until!).split(' ').first}'),
              onPressed: () async {
                final now = DateTime.now();
                final day = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 365)), initialDate: d.until ?? now.add(const Duration(days: 30)));
                setState(() => d.until = day == null ? null : DateTime(day.year, day.month, day.day, 23, 59));
              },
            ),
          ]),
          const CrewNote('Her turda kitle yeniden hesaplanır: yeni üyeler girer, izni kalkanlar çıkar.'),
        ],
        CrewNote(
          d.category == 'service'
              ? 'Hizmet bildirimi sessiz saate ve sıklık sınırına takılmaz; yalnızca gerçekten gerekli bilgi için kullan.'
              : '${widget.config['quietOn'] == false ? 'Genel sessiz saat kapalı.' : '${_two(_cfg('quietStart', 22))}:00–${_two(_cfg('quietEnd', 9))}:00 arası gönderilmez, sabaha kayar.'} '
                  'Üyenin kendi sessiz saatleri de uygulanır. Sıklık: ${d.category == 'marketing' ? 'pazarlama günde en çok ${_cfg('marketingPerDay', 2)}' : 'duyuru + etkinlik günde en çok ${_cfg('otherPerDay', 4)}'}; fazlası ertesi gün.',
          icon: d.category == 'service' ? Icons.notifications_active_outlined : Icons.bedtime_outlined,
        ),
      ];

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _fmt(DateTime x) => '${_two(x.day)}.${_two(x.month)}.${x.year} ${_two(x.hour)}:${_two(x.minute)}';
  static String _dowText(Set<int> s) {
    const n = {1: 'Pzt', 2: 'Sal', 3: 'Çar', 4: 'Per', 5: 'Cum', 6: 'Cmt', 0: 'Paz'};
    return [for (final k in const [1, 2, 3, 4, 5, 6, 0]) if (s.contains(k)) n[k]].join(', ');
  }
}

/// Tek varyantın içerik düzenleyicisi.
class _VariantEditor extends StatefulWidget {
  const _VariantEditor({super.key, required this.v, required this.onChanged, required this.upload, required this.player});
  final NsVariant v;
  final VoidCallback onChanged;
  final Future<String?> Function(String kind) upload;
  final AudioPlayer player;

  @override
  State<_VariantEditor> createState() => _VariantEditorState();
}

class _VariantEditorState extends State<_VariantEditor> {
  late final _title = TextEditingController(text: widget.v.title);
  late final _body = TextEditingController(text: widget.v.body);
  late final _cardBody = TextEditingController(text: widget.v.cardBody);
  late TextEditingController _focusCtl = _title;
  late String _linkType = _typeOf(widget.v.link);
  late final _linkArg = TextEditingController(text: _argOf(widget.v.link));

  static const _emojis = ['🎉', '🎁', '🔥', '📣', '📅', '🎶', '☕', '🛍️', '✨', '💎', '🪙', '👋', '❤️', '🚀', '📚', '🌿'];
  static const _linkTypes = <String, (String, String)>{
    'none': ('Bağlantı yok (bildirim listesi)', ''),
    'event': ('Etkinlik', '/etkinlik/'),
    'events': ('Etkinlikler sayfası', '/etkinlikler'),
    'product': ('Mağaza ürünü', '/magaza/urun/'),
    'store': ('Mağaza', '/magaza'),
    'group': ('Grup / topluluk', '/grup/'),
    'invite': ('Davetlerim', '/davetlerim'),
    'custom': ('Başka bir sayfa (yol)', ''),
  };

  static String _typeOf(String l) {
    if (l.isEmpty) return 'none';
    if (l.startsWith('/etkinlik/')) return 'event';
    if (l == '/etkinlikler') return 'events';
    if (l.startsWith('/magaza/urun/')) return 'product';
    if (l == '/magaza') return 'store';
    if (l.startsWith('/grup/')) return 'group';
    if (l == '/davetlerim') return 'invite';
    return 'custom';
  }

  static String _argOf(String l) => switch (_typeOf(l)) {
        'event' => l.substring('/etkinlik/'.length),
        'product' => l.substring('/magaza/urun/'.length),
        'group' => l.substring('/grup/'.length),
        'custom' => l,
        _ => '',
      };

  void _syncLink() {
    final (_, base) = _linkTypes[_linkType]!;
    final arg = _linkArg.text.trim();
    widget.v.link = switch (_linkType) {
      'none' => '',
      'custom' => arg,
      'event' || 'product' || 'group' => arg.isEmpty ? '' : '$base$arg',
      _ => base,
    };
    widget.onChanged();
  }

  @override
  void dispose() {
    for (final c in [_title, _body, _cardBody, _linkArg]) {
      c.dispose();
    }
    super.dispose();
  }

  void _insert(String s) {
    final c = _focusCtl;
    final sel = c.selection;
    final at = sel.isValid ? sel.start : c.text.length;
    final end = sel.isValid ? sel.end : c.text.length;
    c.value = TextEditingValue(text: c.text.replaceRange(at, end, s), selection: TextSelection.collapsed(offset: at + s.length));
    _pushText();
  }

  void _pushText() {
    widget.v
      ..title = _title.text
      ..body = _body.text
      ..cardBody = _cardBody.text;
    widget.onChanged();
  }

  /// Değişiklik + yeniden çiz + üst bileşene haber.
  void _edit(void Function() f) {
    setState(f);
    widget.onChanged();
  }

  void _play(String id) {
    final f = kNsSounds.firstWhere((s) => s.id == id, orElse: () => kNsSounds.first).file;
    if (f.isNotEmpty) widget.player.play(AssetSource('notify_sounds/$f'));
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.v;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Column(spacing: CrewSpace.fieldGap, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Focus(
        onFocusChange: (f) => f ? _focusCtl = _title : null,
        child: TextField(controller: _title, maxLength: 65, decoration: const InputDecoration(labelText: 'Başlık', hintText: 'Ör. Cuma akşamı Moda\'da akustik gece 🎶'), onChanged: (_) => _pushText()),
      ),
      Focus(
        onFocusChange: (f) => f ? _focusCtl = _body : null,
        child: TextField(controller: _body, maxLength: 240, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Metin', hintText: '{ad}, bu cuma 20:00\'de sahilde gitarlar çalıyor…'), onChanged: (_) => _pushText()),
      ),
      Wrap(spacing: CrewSpace.xs, runSpacing: CrewSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final e in _emojis)
          InkWell(onTap: () => _insert(e), borderRadius: BorderRadius.circular(8), child: Padding(padding: const EdgeInsets.all(CrewSpace.sm - 2), child: Text(e, style: const TextStyle(fontSize: 20)))),
        const SizedBox(width: CrewSpace.sm),
        ActionChip(avatar: const Icon(Icons.person_outline_rounded, size: 18), label: const Text('{ad} ekle'), onPressed: () => _insert('{ad}')),
      ]),
      const CrewNote('{ad} üyenin görünen adının ilk kelimesiyle değişir (rumuzlu üyede rumuz; gerçek ad kullanılmaz).'),
      // görsel
      Row(children: [
        if (v.image != null) ...[
          ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(v.image!, width: 128, height: 72, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 128, height: 72))),
          const SizedBox(width: CrewSpace.md),
        ],
        OutlinedButton.icon(
          icon: const Icon(Icons.image_outlined, size: 18),
          label: Text(v.image == null ? 'Büyük görsel ekle' : 'Görseli değiştir'),
          onPressed: () async {
            final u = await widget.upload('image');
            if (u != null) setState(() => v.image = u);
            widget.onChanged();
          },
        ),
        if (v.image != null) TextButton(onPressed: () => _edit(() => v.image = null), child: const Text('Kaldır')),
      ]),
      const CrewNote('JPG/PNG/WEBP, en çok 1 MB, yatay 2:1 önerilir. Yüklenen görsel güvenlik taramasından geçer.'),
      CrewFormGrid(children: [
        DropdownButtonFormField<String>(
          initialValue: kNsSounds.any((s) => s.id == v.sound) ? v.sound : 'default',
          decoration: InputDecoration(
            labelText: 'Bildirim sesi',
            suffixIcon: IconButton(tooltip: 'Dinle', icon: const Icon(Icons.play_circle_outline_rounded), onPressed: () => _play(v.sound)),
          ),
          items: [for (final s in kNsSounds) DropdownMenuItem(value: s.id, child: Text(s.label))],
          onChanged: (x) {
            v.sound = x ?? 'default';
            widget.onChanged();
            _play(v.sound);
          },
        ),
        DropdownButtonFormField<String>(
          initialValue: _linkType,
          decoration: const InputDecoration(labelText: 'Dokununca açılacak yer'),
          items: [for (final e in _linkTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value.$1))],
          onChanged: (x) => setState(() {
            _linkType = x ?? 'none';
            _syncLink();
          }),
        ),
        if (const ['event', 'product', 'group', 'custom'].contains(_linkType))
          CrewSpan.full(TextField(
            controller: _linkArg,
            decoration: InputDecoration(labelText: _linkType == 'custom' ? 'Yol (/… ya da https://hadisosyal.com/…)' : 'Kimlik', hintText: _linkType == 'custom' ? '/akademi' : 'abc123'),
            onChanged: (_) => _syncLink(),
          )),
      ]),
      const CrewNote('Sesler uygulamaya gömülüdür (Android kanalı, iPhone paketi); web\'de tarayıcının kendi sesi çalar.'),
      // düğmeler
      Row(children: [
        Expanded(child: Text('Düğmeler (en çok 2)', style: t.titleSmall)),
        if (v.buttons.length < 2)
          TextButton.icon(
            onPressed: () => _edit(() => v.buttons.add((label: v.buttons.isEmpty ? 'Göz at' : 'Sonra', link: v.link.isEmpty ? '/bildirimler' : v.link))),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Düğme ekle'),
          ),
      ]),
      for (final (i, b) in v.buttons.indexed)
        CrewItemCard(
          title: '${i + 1}. düğme',
          onRemove: () => _edit(() => v.buttons.removeAt(i)),
          child: CrewFormGrid(children: [
            TextFormField(
              initialValue: b.label,
              maxLength: 20,
              decoration: const InputDecoration(labelText: 'Yazı', counterText: ''),
              onChanged: (x) {
                v.buttons[i] = (label: x, link: v.buttons[i].link);
                widget.onChanged();
              },
            ),
            TextFormField(
              initialValue: b.link,
              decoration: const InputDecoration(labelText: 'Bağlantı', hintText: '/etkinlik/abc'),
              onChanged: (x) {
                v.buttons[i] = (label: v.buttons[i].label, link: x.trim());
                widget.onChanged();
              },
            ),
          ]),
        ),
      if (v.buttons.isEmpty) const CrewNote('Düğmeler zengin kartta ve tarayıcı bildiriminde görünür; telefonda bildirime dokununca kart açılır.'),
      Divider(height: CrewSpace.sm, color: cs.outlineVariant),
      CrewSwitchRow(
        title: 'Dokununca zengin kart açılsın',
        subtitle: 'Büyük görsel, uzun metin, sesli mesaj ve düğmeler; gönderildikten sonra geri çekilebilir.',
        value: v.cardOn,
        onChanged: (on) => _edit(() => v.cardOn = on),
      ),
      if (v.cardOn) ...[
        Focus(
          onFocusChange: (f) => f ? _focusCtl = _cardBody : null,
          child: TextField(controller: _cardBody, maxLength: 2000, minLines: 3, maxLines: 8, decoration: const InputDecoration(labelText: 'Kart metni', alignLabelWithHint: true), onChanged: (_) => _pushText()),
        ),
        Row(children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.mic_none_rounded, size: 18),
            label: Text(v.cardAudio == null ? 'Sesli mesaj ekle' : 'Sesli mesaj · ${v.cardAudioSec} sn'),
            onPressed: () async {
              final u = await widget.upload('audio');
              if (u == null) return;
              var sec = 30;
              try {
                final p = AudioPlayer();
                await p.setSourceUrl(u);
                sec = ((await p.getDuration())?.inSeconds ?? 30).clamp(1, 180);
                await p.dispose();
              } catch (_) {}
              setState(() => (v.cardAudio = u, v.cardAudioSec = sec));
              widget.onChanged();
            },
          ),
          if (v.cardAudio != null) TextButton(onPressed: () => _edit(() => (v.cardAudio = null, v.cardAudioSec = 0)), child: const Text('Kaldır')),
        ]),
        const CrewNote('MP3/M4A/AAC/OGG/WAV, en çok 3 dakika ve 3 MB. Ses de gönderimden önce denetlenir.'),
      ],
    ]);
  }
}

