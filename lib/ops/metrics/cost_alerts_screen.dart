// Operasyon › Maliyet uyarıları (20 Ekim 2026; YALNIZCA ANA KURUCU). Sunucu: functions/src/ops_cost.ts (opsCost).
// Pahalı API'lerin günlük kullanımı (Gemini, Gemini Live dakika, TTS, AI video, fonksiyon çağrıları, Firestore, depolama)
// ve eşikler. Eşik aşılınca her gün 08:07'de ana kurucuya bildirim gider. IAM / faturalama / API anahtarına dokunulmaz.
// Hizmet anahtarı: cost_alerts.
import 'package:flutter/material.dart';
import 'package:hadi/panel_ui/crew_ui.dart';
import 'package:flutter/services.dart';

import 'package:hadi/core/service_switches.dart';
import 'package:hadi/data/models.dart' show AppFailure;
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/theme/hadi_icons.dart';
import 'package:hadi/widgets/auto_marquee_text.dart';
import 'package:hadi/widgets/instant.dart' show InlineError, ListSkeleton;
import 'package:hadi/data/ops_api.dart';

class CostAlertsScreen extends StatefulWidget {
  const CostAlertsScreen({super.key});
  @override
  State<CostAlertsScreen> createState() => _CostAlertsScreenState();
}

class _CostAlertsScreenState extends State<CostAlertsScreen> {
  Map<String, dynamic>? _d;
  String? _err;
  bool _busy = false;
  int _days = 14;
  final _thr = <String, TextEditingController>{};
  bool _notify = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _thr.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final d = await OpsApi.cost('summary', {'days': _days});
      final t = OpsApi.map(d['thresholds']);
      for (final m in OpsApi.list(d['metrics'])) {
        final k = '${m['key']}';
        (_thr[k] ??= TextEditingController()).text = t[k] is num ? '${t[k]}' : '';
      }
      if (mounted) {
        setState(() {
          _d = d;
          _notify = d['notify'] != false;
        });
      }
    } on AppFailure catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await OpsApi.cost('configSet', {
        'thresholds': {for (final e in _thr.entries) if (e.value.text.trim().isNotEmpty) e.key: double.tryParse(e.value.text.trim().replaceAll(',', '.')) ?? 0},
        'notify': _notify,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Eşikler kaydedildi.')));
      await _load();
    } on AppFailure catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runNow() async {
    setState(() => _busy = true);
    try {
      final r = await OpsApi.cost('runNow');
      final ex = (r['exceeded'] as List?)?.length ?? 0;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ex > 0 ? 'Bugün $ex kalem eşiği aştı; bildirim gönderildi.' : 'Bugün eşik aşımı yok.')));
      await _load();
    } on AppFailure catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ServiceSwitches.instance,
      builder: (context, _) {
        final off = ServiceSwitches.instance.isHidden('cost_alerts');
        return Scaffold(
          appBar: AppBar(
            title: const AutoMarqueeText('Maliyet uyarıları'),
            actions: [
              if (!off)
                PopupMenuButton<int>(
                  tooltip: 'Gün',
                  initialValue: _days,
                  onSelected: (v) {
                    setState(() => _days = v);
                    _load();
                  },
                  itemBuilder: (_) => [for (final v in const [7, 14, 30, 60]) PopupMenuItem(value: v, child: Text('$v gün'))],
                  icon: const HadiIcon(Icons.date_range_rounded),
                ),
              if (!off) IconButton(tooltip: 'Yenile', onPressed: _busy ? null : _load, icon: const HadiIcon(Icons.refresh_rounded)),
            ],
          ),
          body: off
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text('Maliyet uyarıları kapalı. Yönetim, Hizmetler › Maliyet uyarıları ile açabilir.', textAlign: TextAlign.center, style: TextStyle(color: HadiColors.ink2)),
                  ),
                )
              : _body(),
        );
      },
    );
  }

  Widget _body() {
    final d = _d;
    if (d == null) return _err != null ? InlineError(message: _err!, onRetry: _load) : const ListSkeleton(padding: EdgeInsets.all(12));
    final metrics = OpsApi.list(d['metrics']);
    final rows = OpsApi.list(d['rows']);
    final thr = OpsApi.map(d['thresholds']);
    return RefreshIndicator(
      onRefresh: _load,
      child: CrewListView(maxWidth: 1040, children: [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Text('Değerler sunucu sayaçlarından ve Google Cloud Monitoring\'den (salt okuma) gelir; "—" ölçülemedi demektir. '
            'Tahmini değerlerdir; kesin tutar için Google Cloud faturasına bak.', style: TextStyle(color: HadiColors.ink3, fontSize: 12.5, height: 1.35)),
        const SizedBox(height: 10),
        for (final m in metrics) _MetricCard(metric: m, rows: rows, threshold: thr['${m['key']}']),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Günlük eşikler', style: TextStyle(color: HadiColors.ink, fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 4),
              Text('Boş bırakılan kalem için uyarı yok. Eşik aşılınca sana bildirim (push) gelir; aynı gün aynı kalem için bir kez.', style: TextStyle(color: HadiColors.ink3, fontSize: 12.5)),
              const SizedBox(height: 8),
              for (final m in metrics)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: _thr['${m['key']}'] ??= TextEditingController(),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    decoration: InputDecoration(labelText: '${m['label']} (${m['unit']})', isDense: true),
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _notify,
                onChanged: _busy ? null : (v) => setState(() => _notify = v),
                title: const Text('Eşik aşılınca bana bildir'),
              ),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: _busy ? null : _runNow, child: const AutoMarqueeText('Bugünü şimdi hesapla'))),
                const SizedBox(width: 8),
                Expanded(child: FilledButton(onPressed: _busy ? null : _save, child: const Text('Kaydet'))),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric, required this.rows, required this.threshold});
  final Map<String, dynamic> metric;
  final List<Map<String, dynamic>> rows;
  final Object? threshold;

  @override
  Widget build(BuildContext context) {
    final k = '${metric['key']}';
    final vals = [for (final r in rows) OpsApi.map(r['values'])[k]];
    final today = vals.isNotEmpty ? vals.first : null;
    final nums = vals.whereType<num>().toList();
    final maxV = nums.isEmpty ? 0.0 : nums.reduce((a, b) => a > b ? a : b).toDouble();
    final lim = threshold is num ? (threshold as num).toDouble() : null;
    final top = [maxV, lim ?? 0].reduce((a, b) => a > b ? a : b);
    final over = today is num && lim != null && today > lim;
    final digits = k == 'live_usd' || k == 'storage_gb' || k == 'live_minutes' ? 1 : 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: AutoMarqueeText('${metric['label']}', style: TextStyle(color: HadiColors.ink, fontWeight: FontWeight.w800))),
            const SizedBox(width: 8),
            Text('${OpsApi.fmt(today, digits: digits)} ${metric['unit']}',
                style: TextStyle(color: over ? HadiColors.error : HadiColors.ink, fontWeight: FontWeight.w900)),
          ]),
          Text('Bugün (kısmi)${lim != null ? ' · eşik ${OpsApi.fmt(lim, digits: digits)}' : ' · eşik yok'}', style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
          const SizedBox(height: 8),
          // Günlük çubuklar (eskiden yeniye). Eşiği aşan gün kırmızı.
          SizedBox(
            height: 36,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final v in vals.reversed)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Container(
                      height: v is num && top > 0 ? (v / top * 34).clamp(2, 34).toDouble() : 2,
                      decoration: BoxDecoration(
                        color: v is! num ? HadiColors.line : (lim != null && v > lim ? HadiColors.error : HadiColors.aktivite),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
