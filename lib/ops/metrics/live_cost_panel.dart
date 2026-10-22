// Kurucu paneli › İstatistik › Canlı sohbet maliyeti (yalnızca ana kurucu).
// supportLive { op: costStats, days } → günlük toplam USD/TL, ortalama TL/dk, oturum başına, bot başına, en pahalı 10 oturum.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:hadi/data/callables.dart';
import 'package:hadi/data/firebase_services.dart' show kFunctionsRegion;
import 'package:hadi/theme/hadi_colors.dart';

class LiveCostPanel extends StatefulWidget {
  const LiveCostPanel({super.key});
  @override
  State<LiveCostPanel> createState() => _LiveCostPanelState();
}

class _LiveCostPanelState extends State<LiveCostPanel> {
  Map? _d;
  String? _err;
  bool _busy = false;
  int _days = 14;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final r = await FirebaseFunctions.instanceFor(region: kFunctionsRegion).hadiCallable('supportLive').call({'op': 'costStats', 'days': _days});
      if (mounted) setState(() => _d = r.data is Map ? r.data as Map : const {});
    } catch (e) {
      if (mounted) setState(() => _err = 'Maliyet verisi alınamadı.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static double _n(Object? v) => v is num ? v.toDouble() : 0;
  static String _f(double v, [int d = 2]) => v.toStringAsFixed(d).replaceAll('.', ',');
  String _money(double usd, Object? tl) => tl is num ? '${_f(tl.toDouble(), 0)} TL' : '\$${_f(usd)}';

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final rows = (d?['rows'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
    final top = (d?['top'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
    final fx = _n(d?['usdTry']);
    double sum(String k) => rows.fold(0.0, (a, r) => a + _n(r[k]));
    final usd = sum('usd'), mins = sum('minutes'), sessions = sum('sessions'), botSess = sum('botSessions'), botUsd = sum('botSessionsUsd'), fUsd = sum('founderUsd');
    final byKind = <String, double>{};
    for (final r in rows) {
      final m = r['byKind'];
      if (m is Map) {
        for (final e in m.entries) {
          byKind['${e.key}'] = (byKind['${e.key}'] ?? 0) + _n(e.value);
        }
      }
    }
    final kinds = byKind.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    String tl(double u) => fx > 0 ? '${_f(u * fx, 0)} TL' : '\$${_f(u)}';
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(color: HadiColors.heyecan.withValues(alpha: .08), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.graphic_eq_rounded, color: HadiColors.readableOn(HadiColors.heyecan, Color.alphaBlend(HadiColors.heyecan.withValues(alpha: .08), HadiColors.card), 3)),
          const SizedBox(width: 8),
          const Expanded(child: Text('Canlı sohbet maliyeti', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
          DropdownButton<int>(
            value: _days,
            underline: const SizedBox.shrink(),
            items: const [DropdownMenuItem(value: 1, child: Text('Bugün')), DropdownMenuItem(value: 7, child: Text('7 gün')), DropdownMenuItem(value: 14, child: Text('14 gün')), DropdownMenuItem(value: 30, child: Text('30 gün'))],
            onChanged: _busy ? null : (v) {
              setState(() => _days = v ?? 14);
              _load();
            },
          ),
          IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Yenile'),
        ]),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_err != null) Text(_err!, style: TextStyle(color: HadiColors.text(HadiColors.error))),
        if (fx <= 0 && d != null)
          Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('USD/TL kuru girilmemiş: tutarlar dolar. Destek sesi › Canlı sesli sohbet kartından gir.', style: TextStyle(color: HadiColors.ink2, fontSize: 12.5)),
          ),
        if (d != null) ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Tile('Toplam', tl(usd)),
            _Tile('Ort. / dk', mins > 0 ? tl(usd / mins) : '—'),
            _Tile('Oturum başına', sessions > 0 ? tl(usd / sessions) : '—'),
            _Tile('Botlu oturum başına', botSess > 0 ? tl(botUsd / botSess) : '—'),
            _Tile('Kurucu testleri', tl(fUsd)),
            _Tile('Süre', '${_f(mins, 0)} dk · ${sessions.toInt()} oturum'),
          ]),
          const SizedBox(height: 12),
          const Text('Günlük', style: TextStyle(fontWeight: FontWeight.w800)),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 92, child: Text('${r['day']}', style: const TextStyle(fontSize: 13))),
                Expanded(child: Text('${_money(_n(r['usd']), r['tl'])} · ${_f(_n(r['minutes']), 0)} dk · ${_n(r['sessions']).toInt()} oturum', style: const TextStyle(fontSize: 13))),
                Text(r['tlPerMin'] is num ? '${_f(_n(r['tlPerMin']))} TL/dk' : '', style: TextStyle(fontSize: 12.5, color: HadiColors.ink2)),
              ]),
            ),
          if (kinds.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Bot başına maliyet', style: TextStyle(fontWeight: FontWeight.w800)),
            for (final k in kinds.take(12))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [Expanded(child: Text(k.key == 'support' ? 'HADİ Destek' : k.key, style: const TextStyle(fontSize: 13))), Text(tl(k.value), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))]),
              ),
          ],
          if (top.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('En pahalı 10 oturum', style: TextStyle(fontWeight: FontWeight.w800)),
            for (final x in top)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(
                    child: Text('${x['name']}${x['founder'] == true ? ' (kurucu testi)' : ''} · ${x['day'] ?? ''} · ${(_n(x['sec']) / 60).toStringAsFixed(1)} dk · ${_n(x['bots']).toInt()} bot · ${_n(x['turns']).toInt()} tur',
                        style: const TextStyle(fontSize: 12.5)),
                  ),
                  Text(_money(_n(x['usd']), x['tl']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                ]),
              ),
          ],
        ],
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(fontSize: 12, color: HadiColors.ink2)),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        ]),
      );
}
