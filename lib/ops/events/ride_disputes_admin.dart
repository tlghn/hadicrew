// HADİ — Yönetim › Yolculuk anlaşmazlıkları (/yonetim/yolculuklar; rides.ts disputes / resolve).
// Sürücü ile yolcunun bildirimi çeliştiğinde bloke tutar burada karara bağlanır: sürücüye aktar, iade et ya da
// "yolcu gelmedi" (politikaya göre ücret + ceza). İsteğe bağlı sürücü cezası. Her karar gerekçeli ve denetim kaydında.
import 'package:hadi/widgets/instant.dart';
import 'package:flutter/material.dart';

import 'package:hadi/core/format.dart';
import 'package:hadi/data/models.dart';
import 'package:hadi/data/ride_service.dart';
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/hadi_sheet.dart';
import 'package:hadi/core/money.dart' show kElmas;

class RideDisputesScreen extends StatefulWidget {
  const RideDisputesScreen({super.key});
  @override
  State<RideDisputesScreen> createState() => _RideDisputesScreenState();
}

class _RideDisputesScreenState extends State<RideDisputesScreen> {
  bool _resolved = false;
  List<Map<String, Object?>>? _items;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _items = null);
    try {
      final v = await RideService.instance.disputes(resolved: _resolved);
      if (mounted) setState(() {
        _items = v;
        _err = null;
      });
    } on AppFailure catch (e) {
      if (mounted) setState(() {
        _items = const [];
        _err = e.message;
      });
    }
  }

  static String _mark(Object? v) => switch (v) {
        'present' => 'geldi',
        'absent' => 'gelmedi',
        'ok' => 'sorunsuz',
        'driver_noshow' => 'sürücü gelmedi',
        'problem' => 'sorun var',
        _ => '—',
      };

  Future<void> _resolve(Map<String, Object?> d) async {
    final r = await showHadiSheet<(String, String, bool)>(context: context, showDragHandle: true, builder: (_) => _ResolveSheet(d: d));
    if (r == null || !mounted) return;
    try {
      await RideService.instance.resolveDispute('${d['id']}', r.$1, r.$2, penalizeDriver: r.$3);
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Karar uygulandı.')));
      _load();
    } on AppFailure catch (e) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Yolculuk anlaşmazlıkları')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<bool>(
            segments: const [ButtonSegment(value: false, label: Text('Açık')), ButtonSegment(value: true, label: Text('Çözülen'))],
            selected: {_resolved},
            onSelectionChanged: (s) {
              _resolved = s.first;
              _load();
            },
          ),
        ),
        if (_err != null) Padding(padding: const EdgeInsets.all(12), child: Text(_err!, style: TextStyle(color: HadiColors.text(HadiColors.error)))),
        Expanded(
          child: items == null
              ? const ListSkeleton(count: 5)
              : items.isEmpty
                  ? Center(child: Text('Kayıt yok.', style: TextStyle(color: HadiColors.ink3)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final d = items[i];
                          final dep = d['departAt'] is num && (d['departAt'] as num) > 0 ? DateTime.fromMillisecondsSinceEpoch((d['departAt'] as num).toInt()) : null;
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${d['eventTitle'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w900)),
                                if (dep != null) Text('Kalkış ${dayLong(dep)} ${hm(dep)}', style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
                                const SizedBox(height: 8),
                                Text('Sürücü: ${d['driverName'] ?? ''} → yolcu için "${_mark(d['driverMark'])}"'),
                                if ('${d['driverNote'] ?? ''}'.isNotEmpty) Text('  “${d['driverNote']}”', style: TextStyle(color: HadiColors.ink2)),
                                Text('Yolcu: ${d['passengerName'] ?? ''} → "${_mark(d['passengerMark'])}"'),
                                if ('${d['passengerNote'] ?? ''}'.isNotEmpty) Text('  “${d['passengerNote']}”', style: TextStyle(color: HadiColors.ink2)),
                                const SizedBox(height: 6),
                                Text('Bloke: ${d['charged'] ?? 0}$kElmas (fiyat ${d['priceHp'] ?? 0}$kElmas)', style: const TextStyle(fontWeight: FontWeight.w700)),
                                if (_resolved) Text('Karar: ${d['outcome'] ?? ''} · ${d['note'] ?? ''}', style: TextStyle(color: HadiColors.ink3)),
                                if (!_resolved) ...[
                                  const SizedBox(height: 8),
                                  Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: () => _resolve(d), child: const Text('Karar ver'))),
                                ],
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ]),
    );
  }
}

class _ResolveSheet extends StatefulWidget {
  const _ResolveSheet({required this.d});
  final Map<String, Object?> d;
  @override
  State<_ResolveSheet> createState() => _ResolveSheetState();
}

class _ResolveSheetState extends State<_ResolveSheet> {
  String _action = 'refund';
  bool _penalize = false;
  final _note = TextEditingController();
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Karar', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: _action,
            onChanged: (v) => setState(() => _action = v ?? _action),
            child: const Column(children: [
              RadioListTile<String>(value: 'release', title: Text('Sürücüye aktar'), subtitle: Text('Yolculuk gerçekleşti.')),
              RadioListTile<String>(value: 'refund', title: Text('Yolcuya iade et'), subtitle: Text('Yolculuk olmadı ya da sorun sürücüde.')),
              RadioListTile<String>(value: 'noshow', title: Text('Yolcu gelmedi'), subtitle: Text('Politikaya göre ücret + yolcuya ceza.')),
            ]),
          ),
          SwitchListTile(
            value: _penalize,
            onChanged: (v) => setState(() => _penalize = v),
            title: const Text('Sürücüye araç paylaşımı cezası ver'),
          ),
          TextField(controller: _note, maxLength: 500, maxLines: 2, decoration: const InputDecoration(labelText: 'Gerekçe (zorunlu, en az 10 karakter)')),
          FilledButton(
            onPressed: () {
              if (_note.text.trim().length < 10) return;
              Navigator.pop(context, (_action, _note.text.trim(), _penalize));
            },
            child: const Text('Uygula'),
          ),
        ]),
      );
}
