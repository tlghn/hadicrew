// Operasyon › Ürün metrikleri (20 Ekim 2026; YALNIZCA ANA KURUCU). Sunucu: functions/src/ops_metrics.ts (opsMetrics).
// DAU/WAU/MAU, kayıt, D1/D7/D30 tutunma, etkinlik katılımı, Elmas satın alma ve üyelik (onboarding) hunisi.
// YALNIZCA TOPLAM SAYILAR: kişi düzeyi veri yok. Kaynak: metrics_daily/{gün}.product (her gece 01:15).
// Hizmet anahtarı: product_metrics.
import 'package:flutter/material.dart';
import 'package:hadi/panel_ui/crew_ui.dart';

import 'package:hadi/core/service_switches.dart';
import 'package:hadi/data/models.dart' show AppFailure;
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/theme/hadi_icons.dart';
import 'package:hadi/widgets/auto_marquee_text.dart';
import 'package:hadi/widgets/instant.dart' show InlineError, ListSkeleton;
import 'package:hadi/data/ops_api.dart';

class ProductMetricsScreen extends StatefulWidget {
  const ProductMetricsScreen({super.key});
  @override
  State<ProductMetricsScreen> createState() => _ProductMetricsScreenState();
}

class _ProductMetricsScreenState extends State<ProductMetricsScreen> {
  Map<String, dynamic>? _d;
  String? _err;
  bool _busy = false;
  int _days = 30;

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
      final d = await OpsApi.metrics('dashboard', {'days': _days});
      if (mounted) setState(() => _d = d);
    } on AppFailure catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backfill() async {
    setState(() => _busy = true);
    try {
      final r = await OpsApi.metrics('backfill', {'days': 14});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${r['done'] ?? 0} gün hesaplandı.')));
      await _load();
    } on AppFailure catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: ServiceSwitches.instance,
        builder: (context, _) {
          final off = ServiceSwitches.instance.isHidden('product_metrics');
          return Scaffold(
            appBar: AppBar(
              title: const AutoMarqueeText('Ürün metrikleri'),
              actions: [
                if (!off)
                  PopupMenuButton<int>(
                    tooltip: 'Aralık',
                    initialValue: _days,
                    onSelected: (v) {
                      setState(() => _days = v);
                      _load();
                    },
                    itemBuilder: (_) => [for (final v in const [7, 30, 90]) PopupMenuItem(value: v, child: Text('$v gün'))],
                    icon: const HadiIcon(Icons.date_range_rounded),
                  ),
                if (!off) IconButton(tooltip: 'Yenile', onPressed: _busy ? null : _load, icon: const HadiIcon(Icons.refresh_rounded)),
              ],
            ),
            body: off
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text('Ürün metrikleri kapalı. Kurucu paneli › Hizmetler › Ürün metrikleri ile aç.', textAlign: TextAlign.center, style: TextStyle(color: HadiColors.ink2)),
                    ),
                  )
                : _body(),
          );
        },
      );

  Widget _body() {
    final d = _d;
    if (d == null) return _err != null ? InlineError(message: _err!, onRetry: _load) : const ListSkeleton(padding: EdgeInsets.all(12));
    final latest = OpsApi.map(d['latest']);
    final s = OpsApi.map(d['series']);
    final t = OpsApi.map(d['totals']);
    final r = OpsApi.map(d['retention']);
    final f = OpsApi.map(d['funnel']);
    final missing = (d['missing'] as num?)?.toInt() ?? 0;
    List<num?> ser(String k) => [for (final v in (s[k] as List? ?? const [])) v is num ? v : null];
    String p(Object? v) => v is num ? '%${OpsApi.fmt(v, digits: 1)}' : '—';
    return RefreshIndicator(
      onRefresh: _load,
      child: CrewListView(maxWidth: 1040, children: [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Text('Yalnızca toplam sayılar; kişi düzeyi veri yok. Aktiflik = o gün uygulamayı açan üye. Her gece 01:15\'te hesaplanır.',
            style: TextStyle(color: HadiColors.ink3, fontSize: 12.5, height: 1.35)),
        if (missing > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Expanded(child: Text('$missing gün henüz hesaplanmamış.', style: TextStyle(color: HadiColors.ink2, fontSize: 12.5))),
              TextButton(onPressed: _busy ? null : _backfill, child: const Text('Son 14 günü hesapla')),
            ]),
          ),
        const SizedBox(height: 10),
        _Section(title: 'Aktif üyeler${latest['day'] != null ? ' · ${latest['day']}' : ''}', children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Kpi(label: 'DAU', value: OpsApi.fmt(latest['dau']), color: HadiColors.aktivite),
            _Kpi(label: 'WAU', value: OpsApi.fmt(latest['wau']), color: HadiColors.dostluk),
            _Kpi(label: 'MAU', value: OpsApi.fmt(latest['mau']), color: HadiColors.iletisim),
            _Kpi(label: 'DAU/MAU', value: p(latest['stickiness']), color: HadiColors.heyecan),
          ]),
          const SizedBox(height: 10),
          _Bars(label: 'DAU', values: ser('dau'), color: HadiColors.aktivite),
          _Bars(label: 'MAU', values: ser('mau'), color: HadiColors.iletisim),
        ]),
        _Section(title: 'Büyüme ve kullanım ($_days gün)', children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Kpi(label: 'Yeni üye', value: OpsApi.fmt(t['signups']), color: HadiColors.dostluk),
            _Kpi(label: 'Etkinlik katılımı', value: OpsApi.fmt(t['eventJoins']), color: HadiColors.heyecan),
            _Kpi(label: 'Elmas satın alma', value: OpsApi.fmt(t['purchases']), color: HadiColors.gold),
            _Kpi(label: 'Alınan Elmas', value: OpsApi.fmt(t['elmasBought']), color: HadiColors.gold),
            _Kpi(label: 'Ciro (TL)', value: OpsApi.fmt(t['tlBought'], digits: 2), color: HadiColors.gold),
          ]),
          const SizedBox(height: 10),
          _Bars(label: 'Yeni üye', values: ser('signups'), color: HadiColors.dostluk),
          _Bars(label: 'Etkinlik katılımı', values: ser('eventJoins'), color: HadiColors.heyecan),
          _Bars(label: 'Elmas satın alma', values: ser('purchases'), color: HadiColors.gold),
        ]),
        _Section(title: 'Tutunma (kayıt kohortları)', children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (k, l) in [('d1', 'D1'), ('d7', 'D7'), ('d30', 'D30')])
              _Kpi(label: '$l · ${OpsApi.fmt(OpsApi.map(r[k])['size'])} kişi', value: p(OpsApi.map(r[k])['pct']), color: HadiColors.aktivite),
          ]),
          const SizedBox(height: 10),
          _Bars(label: 'D1 %', values: ser('d1'), color: HadiColors.aktivite),
          _Bars(label: 'D7 %', values: ser('d7'), color: HadiColors.dostluk),
          _Bars(label: 'D30 %', values: ser('d30'), color: HadiColors.iletisim),
        ]),
        _Section(title: 'Üyelik hunisi (başvurudan 7 gün sonra)', children: [
          for (final (k, l) in [('submitted', 'Başvuru gönderdi'), ('verified', 'Kimliğini doğruladı'), ('approved', 'Onaylandı'), ('profileComplete', 'Profilini tamamladı'), ('activeWeek1', 'İlk hafta aktif')])
            _FunnelRow(label: l, value: OpsApi.n(f[k]), base: OpsApi.n(f['submitted'])),
        ]),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AutoMarqueeText(title, style: TextStyle(color: HadiColors.ink, fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 10),
            ...children,
          ]),
        ),
      );
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, required this.color});
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 100, maxWidth: 170),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: HadiColors.tint(color), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: HadiColors.text(color), fontWeight: FontWeight.w900, fontSize: 18)),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: HadiColors.ink2, fontSize: 12)),
        ]),
      );
}

/// Basit günlük çubuk grafiği (eskiden yeniye); eksik gün ince gri.
class _Bars extends StatelessWidget {
  const _Bars({required this.label, required this.values, required this.color});
  final String label;
  final List<num?> values;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final nums = values.whereType<num>().toList();
    final top = nums.isEmpty ? 0.0 : nums.reduce((a, b) => a > b ? a : b).toDouble();
    final last = nums.isEmpty ? null : nums.last;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: HadiColors.ink2, fontSize: 12.5, fontWeight: FontWeight.w700))),
          Text('son: ${OpsApi.fmt(last, digits: last is double && last % 1 != 0 ? 1 : 0)} · en yüksek: ${OpsApi.fmt(top, digits: 0)}', style: TextStyle(color: HadiColors.ink3, fontSize: 11.5)),
        ]),
        const SizedBox(height: 4),
        SizedBox(
          height: 40,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final v in values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: .5),
                  child: Container(
                    height: v != null && top > 0 ? (v / top * 38).clamp(2, 38).toDouble() : 2,
                    decoration: BoxDecoration(color: v == null ? HadiColors.line : color, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _FunnelRow extends StatelessWidget {
  const _FunnelRow({required this.label, required this.value, required this.base});
  final String label;
  final double value, base;
  @override
  Widget build(BuildContext context) {
    final frac = base > 0 ? (value / base).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: AutoMarqueeText(label, style: TextStyle(color: HadiColors.ink, fontSize: 13))),
          Text('${OpsApi.fmt(value)}${base > 0 ? ' · %${OpsApi.fmt(frac * 100, digits: 1)}' : ''}', style: TextStyle(color: HadiColors.ink2, fontWeight: FontWeight.w800, fontSize: 12.5)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: frac, minHeight: 8, backgroundColor: HadiColors.mist, color: HadiColors.dostluk),
        ),
      ]),
    );
  }
}
