// Operasyon › Moderasyon kuyruğu (20 Ekim 2026). Sunucu: functions/src/ops_moderation.ts (opsMod).
//
// Tek kuyruk: şikâyetler (mesaj, gönderi, rızayla açılan gizli sohbet mesajı, yorum, profil, etkinlik, albüm fotoğrafı,
// anonim soru, salon, radyo yorumu) + otomatik işaretler. Aynı içeriğe gelen şikâyetler tek kartta birleşir.
// Kararlar: Gizle · Uyar · Sustur (N gün) · Blokla · Kapat — gerekçe ZORUNLU (≥10 karakter), hepsi kayda geçer.
// SLA: öneme göre süre (Yüksek/Orta/Düşük; ana kurucu ayarlar); süresi geçenler en üstte.
// KVKK: yapay zekâ yalnızca ÖN SIRALAR; kararı her zaman insan verir.
// Erişim: reports.review yetkisi (kurucular hepsi). Hizmet anahtarı: mod_queue (gizliyken ekran kapalı).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hadi/core/service_switches.dart';
import 'package:hadi/data/models.dart' show AppFailure;
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/theme/hadi_icons.dart';
import 'package:hadi/widgets/auto_marquee_text.dart';
import 'package:hadi/widgets/hadi_sheet.dart';
import 'package:hadi/widgets/instant.dart' show InlineError, ListSkeleton;
import 'package:hadi/widgets/net_fallback.dart';
import 'package:hadi/data/ops_api.dart';

/// Tam ekran (Şikayetler ekranından ve Operasyon merkezinden açılır).
class ModQueueScreen extends StatelessWidget {
  const ModQueueScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: ServiceSwitches.instance,
        builder: (context, _) {
          final off = ServiceSwitches.instance.isHidden('mod_queue');
          return DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: AppBar(
                title: const AutoMarqueeText('Moderasyon kuyruğu'),
                bottom: off ? null : const TabBar(tabs: [Tab(text: 'Kuyruk'), Tab(text: 'İtirazlar')]),
              ),
              body: off
                  ? const _OffNote(text: 'Moderasyon kuyruğu kapalı. Ana kurucu kurucu paneli › Hizmetler › Moderasyon kuyruğu ile açabilir. '
                      'Şikayetler ekranı çalışmaya devam eder.')
                  : const TabBarView(children: [_QueueTab(), _AppealsTab()]),
            ),
          );
        },
      );
}

class _OffNote extends StatelessWidget {
  const _OffNote({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            HadiIcon(Icons.toggle_off_rounded, size: 48, color: HadiColors.ink3),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: HadiColors.ink2, height: 1.4)),
          ]),
        ),
      );
}

Color _sevColor(String s) => switch (s) { 'high' => HadiColors.error, 'medium' => HadiColors.heyecan, _ => HadiColors.aktivite };

String _sevLabel(String s) => switch (s) { 'high' => 'Yüksek', 'medium' => 'Orta', _ => 'Düşük' };

// ================================================================== kuyruk

class _QueueTab extends StatefulWidget {
  const _QueueTab();
  @override
  State<_QueueTab> createState() => _QueueTabState();
}

class _QueueTabState extends State<_QueueTab> with AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? _d;
  String? _err;
  bool _busy = false;
  String _filter = 'all';
  Timer? _tick;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    // SLA sayaçları canlı: dakikada bir yeniden çizilir.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final d = await OpsApi.mod('queue');
      if (mounted) setState(() => _d = d);
    } on AppFailure catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _presort() async {
    setState(() => _busy = true);
    try {
      final r = await OpsApi.mod('presort');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ön sıralandı: ${r['sorted'] ?? 0} şikâyet. Kararı yine sen verirsin.')));
      await _load();
    } on AppFailure catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _claim(Map<String, dynamic> it) async {
    try {
      await OpsApi.mod('claim', {'key': it['key'], 'release': it['claimedBy'] != null});
      await _load();
    } on AppFailure catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _decide(Map<String, dynamic> it) async {
    final caps = {for (final c in (_d?['caps'] as List? ?? const [])) '$c'};
    final ok = await showHadiSheet<bool>(context: context, showDragHandle: true, builder: (_) => _DecideSheet(item: it, caps: caps));
    if (ok == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final d = _d;
    if (d == null) return _err != null ? InlineError(message: _err!, onRetry: _load) : const ListSkeleton(padding: EdgeInsets.all(12));
    final now = DateTime.now();
    var items = OpsApi.list(d['items']);
    items = switch (_filter) {
      'overdue' => items.where((i) => (OpsApi.time(i['dueAt']) ?? now).isBefore(now)).toList(),
      'high' => items.where((i) => i['severity'] == 'high').toList(),
      'auto' => items.where((i) => i['source'] == 'auto').toList(),
      _ => items,
    };
    final st = OpsApi.map(d['stats']);
    final sla = OpsApi.map(d['slaHours']);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: EdgeInsets.fromLTRB(12, 8, 12, 24 + MediaQuery.paddingOf(context).bottom), children: [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _Stat(label: 'Açık', value: '${st['open'] ?? 0}', color: HadiColors.aktivite),
          _Stat(label: 'Süresi geçen', value: '${st['overdue'] ?? 0}', color: HadiColors.error),
          _Stat(label: 'Yüksek', value: '${st['high'] ?? 0}', color: HadiColors.error),
          _Stat(label: 'Orta', value: '${st['medium'] ?? 0}', color: HadiColors.heyecan),
          _Stat(label: 'Düşük', value: '${st['low'] ?? 0}', color: HadiColors.aktivite),
          _Stat(label: '7 günde karar', value: '${st['decided7d'] ?? 0}', color: HadiColors.dostluk),
          _Stat(label: 'Ortanca süre', value: st['medianHours7d'] is num ? '${st['medianHours7d']} sa' : '—', color: HadiColors.iletisim),
          _Stat(label: 'Açık itiraz', value: '${d['appealsOpen'] ?? 0}', color: HadiColors.iletisim),
        ]),
        const SizedBox(height: 8),
        Text('SLA: Yüksek ${sla['high'] ?? 4} sa · Orta ${sla['medium'] ?? 24} sa · Düşük ${sla['low'] ?? 72} sa',
            style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final (v, l) in [('all', 'Tümü'), ('overdue', 'Süresi geçen'), ('high', 'Yüksek'), ('auto', 'Otomatik işaret')])
              Padding(padding: const EdgeInsets.only(right: 6), child: FilterChip(label: Text(l), selected: _filter == v, onSelected: (_) => setState(() => _filter = v))),
            if (d['aiPresortOn'] == true)
              ActionChip(
                avatar: const HadiIcon(Icons.auto_awesome_rounded, size: 16),
                label: const Text('YZ ile ön sırala'),
                onPressed: _busy ? null : _presort,
              ),
          ]),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Center(child: Text('Kuyruk boş. 🎉', style: TextStyle(color: HadiColors.ink3, fontSize: 16))),
          ),
        for (final it in items) _ItemCard(item: it, now: now, onDecide: () => _decide(it), onClaim: () => _claim(it)),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 92),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: HadiColors.tint(color), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(value, style: TextStyle(color: HadiColors.text(color), fontWeight: FontWeight.w900, fontSize: 17)),
          Text(label, style: TextStyle(color: HadiColors.ink2, fontSize: 11.5)),
        ]),
      );
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item, required this.now, required this.onDecide, required this.onClaim});
  final Map<String, dynamic> item;
  final DateTime now;
  final VoidCallback onDecide, onClaim;

  @override
  Widget build(BuildContext context) {
    final sev = '${item['severity'] ?? 'low'}';
    final due = OpsApi.time(item['dueAt']) ?? now;
    final overdue = due.isBefore(now);
    final snap = OpsApi.map(item['snapshot']);
    final media = snap['mediaUrl'] is String && (snap['mediaUrl'] as String).isNotEmpty ? snap['mediaUrl'] as String : null;
    final text = '${snap['text'] ?? ''}'.trim();
    final ai = item['aiSort'] is Map ? OpsApi.map(item['aiSort']) : null;
    final reasons = [for (final r in (item['reasons'] as List? ?? const [])) '$r'];
    final claimed = item['claimedName'] as String?;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _Pill(text: _sevLabel(sev), color: _sevColor(sev)),
            const SizedBox(width: 6),
            Expanded(child: AutoMarqueeText('${item['kindLabel'] ?? item['kind']}${'${item['where'] ?? ''}'.isNotEmpty ? ' · ${item['where']}' : ''}', style: TextStyle(color: HadiColors.ink, fontWeight: FontWeight.w800))),
            const SizedBox(width: 6),
            HadiIcon(Icons.timer_outlined, size: 16, color: overdue ? HadiColors.error : HadiColors.ink3),
            const SizedBox(width: 2),
            Text(overdue ? '${OpsApi.dur(now.difference(due))} geçti' : '${OpsApi.dur(due.difference(now))} kaldı',
                style: TextStyle(color: overdue ? HadiColors.error : HadiColors.ink3, fontWeight: FontWeight.w700, fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          Text(
            '${'${item['targetName'] ?? ''}'.isEmpty ? 'Üye' : item['targetName']} · '
            '${item['source'] == 'auto' ? 'otomatik işaret' : '${item['reports'] ?? 1} şikâyet'}',
            style: TextStyle(color: HadiColors.ink2, fontSize: 13),
          ),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final r in reasons) _Pill(text: r, color: HadiColors.pink, small: true)]),
          ],
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: HadiColors.mist, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (media != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(media, height: 160, width: double.infinity, fit: BoxFit.cover, errorBuilder: NetImageFallback.builder),
                ),
              if (media != null && text.isNotEmpty) const SizedBox(height: 6),
              if (text.isNotEmpty) Text(text, maxLines: 8, overflow: TextOverflow.ellipsis, style: TextStyle(color: HadiColors.ink)),
              if (media == null && text.isEmpty) Text('(içerik kopyası yok)', style: TextStyle(color: HadiColors.ink3)),
            ]),
          ),
          if (ai != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              HadiIcon(Icons.auto_awesome_rounded, size: 15, color: HadiColors.iletisim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'YZ ön sıralaması: ${_sevLabel('${ai['priority']}')}${'${ai['category'] ?? ''}'.isNotEmpty ? ' · ${ai['category']}' : ''}'
                  '${'${ai['note'] ?? ''}'.isNotEmpty ? ' — ${ai['note']}' : ''} (yalnızca sıralama; kararı sen verirsin)',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: HadiColors.ink2, fontSize: 12),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: item['source'] == 'auto' ? null : onClaim,
                icon: HadiIcon(claimed == null ? Icons.back_hand_outlined : Icons.person_off_outlined, size: 18),
                label: AutoMarqueeText(claimed == null ? 'Üstlen' : 'Bırak ($claimed)'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(onPressed: onDecide, icon: const HadiIcon(Icons.gavel_rounded, size: 18), label: const Text('Karar ver')),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color, this.small = false});
  final String text;
  final Color color;
  final bool small;
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: EdgeInsets.symmetric(horizontal: small ? 8 : 10, vertical: small ? 3 : 4),
        decoration: BoxDecoration(color: HadiColors.tint(color), borderRadius: BorderRadius.circular(99)),
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: HadiColors.text(color), fontWeight: FontWeight.w800, fontSize: small ? 11.5 : 12)),
      );
}

// ================================================================== karar penceresi

const _kQuickReasons = [
  'Taciz / hakaret içeriyor',
  'Müstehcen / uygunsuz içerik',
  'Spam veya yanıltıcı içerik',
  'Nefret söylemi',
  'Kişisel bilgi paylaşımı',
  'Topluluk kurallarına aykırı değil',
];

class _DecideSheet extends StatefulWidget {
  const _DecideSheet({required this.item, required this.caps});
  final Map<String, dynamic> item;
  final Set<String> caps;
  @override
  State<_DecideSheet> createState() => _DecideSheetState();
}

class _DecideSheetState extends State<_DecideSheet> {
  String _action = 'dismiss';
  int? _days = 7;
  final _reason = TextEditingController();
  final _warn = TextEditingController();
  bool _busy = false;
  String? _err;

  bool _has(List<String> any) => any.any(widget.caps.contains);

  List<(String, String, IconData, bool)> get _actions {
    final kind = '${widget.item['kind']}';
    final owner = widget.item['targetUid'] != null;
    return [
      ('hide', 'Gizle', Icons.visibility_off_rounded, kind != 'profile' && _has(['content.hide', 'content.remove', 'moderation.system'])),
      ('warn', 'Uyar', Icons.warning_amber_rounded, owner && _has(['users.warn', 'moderation.system'])),
      ('mute', 'Sustur', Icons.volume_off_rounded, owner && _has(['users.suspend', 'moderation.system'])),
      ('ban', 'Blokla', Icons.block_rounded, owner && _has(['moderation.system'])),
      ('dismiss', 'Kapat', Icons.check_circle_outline_rounded, true),
    ];
  }

  @override
  void dispose() {
    _reason.dispose();
    _warn.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason.text.trim();
    if (reason.length < 10) {
      setState(() => _err = 'Gerekçe zorunlu: en az 10 karakter (kayda geçer, üye görür).');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await OpsApi.mod('act', {
        'key': widget.item['key'],
        'action': _action,
        'reason': reason,
        if (_action == 'mute') 'days': _days ?? 7,
        if (_action == 'ban') 'days': _days,
        if (_action == 'warn' && _warn.text.trim().isNotEmpty) 'text': _warn.text.trim(),
      });
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop(true);
    } on AppFailure catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final acts = _actions;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text('Karar ver', style: TextStyle(color: HadiColors.ink, fontWeight: FontWeight.w900, fontSize: 18)),
        const SizedBox(height: 4),
        Text('Kararı sen verirsin; yapay zekâ yalnızca sıralamaya yardım eder. Gerekçe zorunludur ve kayda geçer; üye kararı ve gerekçeyi görür, itiraz edebilir.',
            style: TextStyle(color: HadiColors.ink3, fontSize: 12.5, height: 1.35)),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (v, l, ic, ok) in acts)
            ChoiceChip(
              avatar: HadiIcon(ic, size: 16),
              label: Text(l),
              selected: _action == v,
              onSelected: !ok || _busy
                  ? null
                  : (_) => setState(() {
                        _action = v;
                        _days = v == 'ban' ? 7 : v == 'mute' ? 3 : _days;
                      }),
            ),
        ]),
        if (_action == 'mute' || _action == 'ban') ...[
          const SizedBox(height: 10),
          Text(_action == 'mute' ? 'Susturma süresi' : 'Bloke süresi', style: TextStyle(color: HadiColors.ink2, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final dd in _action == 'mute' ? const <int?>[1, 3, 7, 30, 90] : const <int?>[1, 7, 30, 365, null])
              ChoiceChip(label: Text(dd == null ? 'Süresiz' : '$dd gün'), selected: _days == dd, onSelected: _busy ? null : (_) => setState(() => _days = dd)),
          ]),
        ],
        if (_action == 'warn') ...[
          const SizedBox(height: 10),
          TextField(
            controller: _warn,
            minLines: 2,
            maxLines: 4,
            maxLength: 1000,
            decoration: InputDecoration(
              labelText: 'Üyeye gidecek uyarı metni (boşsa gerekçe gider)',
              filled: true,
              fillColor: HadiColors.mist,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final r in _kQuickReasons) ActionChip(label: Text(r), onPressed: _busy ? null : () => setState(() => _reason.text = r)),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _reason,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: InputDecoration(
            labelText: 'Gerekçe (zorunlu, en az 10 karakter)',
            filled: true,
            fillColor: HadiColors.mist,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        if (_err != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_err!, style: TextStyle(color: HadiColors.text(HadiColors.error)))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _action == 'ban' || _action == 'hide' ? HadiColors.error : null, foregroundColor: _action == 'ban' || _action == 'hide' ? Colors.white : null),
          onPressed: _busy ? null : _submit,
          child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Kararı uygula'),
        ),
      ]),
    );
  }
}

// ================================================================== itirazlar

class _AppealsTab extends StatefulWidget {
  const _AppealsTab();
  @override
  State<_AppealsTab> createState() => _AppealsTabState();
}

class _AppealsTabState extends State<_AppealsTab> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>>? _items;
  String? _err;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await OpsApi.mod('appeals');
      if (mounted) setState(() => _items = OpsApi.list(d['items']));
    } on AppFailure catch (e) {
      if (mounted) setState(() => _err = e.message);
    }
  }

  Future<void> _decide(Map<String, dynamic> it, bool accept) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(accept ? 'İtirazı kabul et' : 'İtirazı reddet'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (accept && it['revertable'] == true) Text('Karar geri alınacak (gizlenen içerik geri gelir / susturma ya da bloke kalkar / uyarı silinir).', style: TextStyle(color: HadiColors.ink2, fontSize: 13)),
          if (accept && it['revertable'] != true) Text('Bu karar geri alınamaz (silinen mesaj); üyeye kabul notu gider.', style: TextStyle(color: HadiColors.ink2, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(controller: note, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Üyeye not (zorunlu, en az 10 karakter)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(accept ? 'Kabul et' : 'Reddet')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await OpsApi.mod('appealDecide', {'actionId': it['id'], 'accept': accept, 'note': note.text.trim()});
      await _load();
    } on AppFailure catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final items = _items;
    if (items == null) return _err != null ? InlineError(message: _err!, onRetry: _load) : const ListSkeleton(padding: EdgeInsets.all(12));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: EdgeInsets.fromLTRB(12, 8, 12, 24 + MediaQuery.paddingOf(context).bottom), children: [
        Text('İtirazı, kararı verenden farklı bir Sistem Moderatörü ya da kurucu sonuçlandırır (dört göz).', style: TextStyle(color: HadiColors.ink3, fontSize: 12.5)),
        const SizedBox(height: 8),
        if (items.isEmpty) Padding(padding: const EdgeInsets.only(top: 60), child: Center(child: Text('Açık itiraz yok.', style: TextStyle(color: HadiColors.ink3)))),
        for (final it in items)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  _Pill(text: '${it['actionLabel'] ?? it['action']}', color: HadiColors.iletisim),
                  const SizedBox(width: 6),
                  Expanded(child: AutoMarqueeText('${it['targetName'] ?? 'Üye'}${'${it['kindLabel'] ?? ''}'.isNotEmpty ? ' · ${it['kindLabel']}' : ''}', style: TextStyle(color: HadiColors.ink, fontWeight: FontWeight.w800))),
                ]),
                const SizedBox(height: 6),
                Text('Karar: ${it['reason'] ?? ''}', style: TextStyle(color: HadiColors.ink2, fontSize: 13)),
                Text('Veren: ${it['byName'] ?? ''} (${it['byRole'] ?? ''})', style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: HadiColors.mist, borderRadius: BorderRadius.circular(12)),
                  child: Text('İtiraz: ${it['appealText'] ?? ''}', style: TextStyle(color: HadiColors.ink)),
                ),
                const SizedBox(height: 10),
                if (it['byMe'] == true) Text('Bu karar senin; itirazı başka bir yetkili sonuçlandırmalı.', style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () => _decide(it, false), child: const Text('Reddet'))),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton(onPressed: () => _decide(it, true), child: const Text('Kabul et'))),
                ]),
              ]),
            ),
          ),
      ]),
    );
  }
}
