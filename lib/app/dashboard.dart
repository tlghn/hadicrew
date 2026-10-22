import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/data/models.dart' show AppFailure;
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/instant.dart' show InlineError;

import 'charts.dart';
import 'crew_api.dart';
import 'sections.dart';
import 'shell.dart' show openSection;

/// Panodaki son veri: kenar çubuğu ve alt menü rozetleri de bunu dinler.
final ValueNotifier<CrewDash?> crewDashNotifier = ValueNotifier<CrewDash?>(null);

/// Pano: bekleyen işler, topluluk özeti ve günlük eğilimler. 60 sn'de bir kendiliğinden yenilenir.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _days = 30;
  bool _loading = false;
  String? _error;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _tick = Timer.periodic(const Duration(seconds: 60), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (_loading || !mounted) return;
    setState(() {
      _loading = true;
      if (!quiet) _error = null;
    });
    try {
      final d = await CrewApi.dash(SessionScope.read(context).services, days: _days);
      crewDashNotifier.value = d;
      if (mounted) setState(() => _error = null);
    } on AppFailure catch (e) {
      if (mounted && !quiet) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && !quiet) setState(() => _error = 'Pano yüklenemedi. Bağlantını kontrol edip tekrar dene.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pano'),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            onPressed: _loading ? null : _load,
            icon: _loading
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ValueListenableBuilder<CrewDash?>(
          valueListenable: crewDashNotifier,
          builder: (context, d, _) {
            if (d == null) {
              if (_error != null) return ListView(children: [InlineError(message: _error!, onRetry: _load)]);
              return const _Skeleton();
            }
            return _Body(dash: d, session: s, days: _days, onDays: (v) {
              setState(() => _days = v);
              _load();
            });
          },
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.dash, required this.session, required this.days, required this.onDays});
  final CrewDash dash;
  final Session session;
  final int days;
  final ValueChanged<int> onDays;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final queues = [for (final x in visibleSections(session)) if (x.queue && x.countKey != null) x];
    final c = dash.counts;
    final community = <(String, int?, IconData, Color)>[
      if (c.containsKey('members')) ('Üye', c['members'], Icons.groups_rounded, HadiColors.aktivite),
      if (c.containsKey('premium')) ('Premium', c['premium'], Icons.workspace_premium_rounded, HadiColors.gold),
      if (c.containsKey('dau')) ('Bugün aktif', c['dau'], Icons.bolt_rounded, HadiColors.dostluk),
      if (c.containsKey('wau')) ('7 günde aktif', c['wau'], Icons.calendar_view_week_rounded, HadiColors.iletisim),
      if (c.containsKey('mau')) ('30 günde aktif', c['mau'], Icons.calendar_month_rounded, HadiColors.iletisim),
      if (c.containsKey('liveNow')) ('Şu an canlı', c['liveNow'], Icons.sensors_rounded, HadiColors.pink),
      if (c.containsKey('eventsNext7d')) ('7 gün içinde etkinlik', c['eventsNext7d'], Icons.event_available_rounded, HadiColors.heyecan),
    ];
    final series = dash.series;
    final w = MediaQuery.sizeOf(context).width;
    final pad = w < 600 ? 16.0 : 24.0;
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, 8, pad, 32 + MediaQuery.paddingOf(context).bottom),
      children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(dash.pendingTotal == 0 ? 'Bekleyen iş yok 🎉' : '${dash.pendingTotal} bekleyen iş',
                  style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('Son güncelleme ${_hm(dash.at)} · dakikada bir yenilenir', style: text.bodySmall?.copyWith(color: HadiColors.ink3)),
            ]),
          ),
          _RoleChip(role: dash.role),
        ]),
        const SizedBox(height: 16),
        if (queues.isNotEmpty) ...[
          _Title('Kuyruklar'),
          _Grid(children: [
            for (final q in queues)
              _QueueTile(section: q, count: q.id == 'isletmeler' ? _sum(c, const ['businessApps', 'businessEvents']) : c[q.countKey!]),
          ]),
          const SizedBox(height: 22),
        ],
        if (community.isNotEmpty) ...[
          _Title('Topluluk'),
          _Grid(children: [
            for (final (label, n, icon, color) in community)
              _StatTile(label: label, value: n, icon: icon, color: color, spark: label == 'Bugün aktif' ? series?.of('dau') : null),
          ]),
          const SizedBox(height: 22),
        ],
        if (series != null) ...[
          Row(children: [
            Expanded(child: _Title('Eğilimler')),
            SegmentedButton<int>(
              segments: const [ButtonSegment(value: 7, label: Text('7 gün')), ButtonSegment(value: 30, label: Text('30 gün')), ButtonSegment(value: 90, label: Text('90 gün'))],
              selected: {days},
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onSelectionChanged: (v) => onDays(v.first),
            ),
          ]),
          const SizedBox(height: 10),
          _ChartCard(
            title: 'Aktif üyeler',
            child: LineChart(days: series.days, lines: [
              ChartLine(name: 'Günlük aktif', color: HadiColors.aktivite, values: series.of('dau')),
            ]),
          ),
          _ChartCard(
            title: 'Büyüme ve katılım',
            child: LineChart(days: series.days, lines: [
              ChartLine(name: 'Yeni üye', color: HadiColors.dostluk, values: series.of('newMembers')),
              ChartLine(name: 'Etkinlik katılımı', color: HadiColors.heyecan, values: series.of('eventJoins')),
            ]),
          ),
          _ChartCard(
            title: 'İçerik',
            child: LineChart(days: series.days, lines: [
              ChartLine(name: 'Gönderi', color: HadiColors.iletisim, values: series.of('posts')),
            ]),
          ),
          _ChartCard(
            title: 'Destek ve şikâyet',
            child: LineChart(days: series.days, lines: [
              ChartLine(name: 'Destek talebi', color: HadiColors.aktivite, values: series.of('tickets')),
              ChartLine(name: 'Şikâyet', color: HadiColors.error, values: series.of('reports')),
            ]),
          ),
          Text('Günlük toplamlar her gece hesaplanır; bugün kısmidir. Kişi düzeyinde veri gösterilmez.',
              style: text.bodySmall?.copyWith(color: HadiColors.ink3)),
        ],
      ],
    );
  }
}

int? _sum(Map<String, int?> c, List<String> keys) {
  int? t;
  for (final k in keys) {
    final v = c[k];
    if (v != null) t = (t ?? 0) + v;
  }
  return t;
}

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _n(int? v) {
  if (v == null) return '—';
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '$b';
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      );
}

/// Kartlar: dar ekranda 2 sütun, genişledikçe artar.
class _Grid extends StatelessWidget {
  const _Grid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, cons) {
        final cols = (cons.maxWidth / 200).floor().clamp(2, 6);
        const gap = 10.0;
        final w = (cons.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [for (final c in children) SizedBox(width: w, child: c)]);
      });
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({required this.section, required this.count});
  final CrewSection section;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final busy = (count ?? 0) > 0;
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: busy ? HadiColors.heyecan.withValues(alpha: .10) : cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openSection(context, section),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(section.icon, size: 20, color: busy ? HadiColors.text(HadiColors.heyecan) : HadiColors.ink3),
              const Spacer(),
              Icon(Icons.chevron_right_rounded, size: 18, color: HadiColors.ink3),
            ]),
            const SizedBox(height: 8),
            Text(_n(count), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: busy ? HadiColors.ink : HadiColors.ink3, height: 1)),
            const SizedBox(height: 4),
            Text(section.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: HadiColors.ink2, fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.icon, required this.color, this.spark});
  final String label;
  final int? value;
  final IconData icon;
  final Color color;
  final List<double?>? spark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: HadiColors.text(color)),
        const SizedBox(height: 8),
        Text(_n(value), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: HadiColors.ink, height: 1)),
        const SizedBox(height: 4),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: HadiColors.ink2, fontSize: 13)),
        if (spark != null) ...[const SizedBox(height: 6), Sparkline(values: spark!, color: color, height: 26)],
      ]),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: HadiColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          child,
        ]),
      );
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (role) {
      'founder' => ('Kurucu', HadiColors.gold),
      'admin' => ('Yönetici', HadiColors.aktivite),
      'moderator' => ('Moderatör', HadiColors.iletisim),
      _ => ('Operasyon', HadiColors.dostluk),
    };
    final f = HadiColors.brandFill(color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: f.bg, borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: TextStyle(color: f.fg, fontWeight: FontWeight.w800, fontSize: 12.5)),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.surfaceContainerLow;
    Widget box(double h) => Container(height: h, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(16)));
    return ListView(padding: const EdgeInsets.all(16), children: [
      box(34),
      const SizedBox(height: 18),
      _Grid(children: [for (var i = 0; i < 6; i++) box(96)]),
      const SizedBox(height: 22),
      box(260),
    ]);
  }
}
