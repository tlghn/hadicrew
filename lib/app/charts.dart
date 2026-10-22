import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hadi/theme/hadi_colors.dart';

/// Grafik serisi: ad, renk, değerler (eksik gün null).
class ChartLine {
  const ChartLine({required this.name, required this.color, required this.values});
  final String name;
  final Color color;
  final List<double?> values;
}

String _fmt(double v) {
  if (v >= 10000) return '${(v / 1000).toStringAsFixed(v >= 100000 ? 0 : 1)} B'.replaceAll('.', ',');
  final i = v.round();
  final s = i.abs().toString();
  final b = StringBuffer();
  for (var k = 0; k < s.length; k++) {
    if (k > 0 && (s.length - k) % 3 == 0) b.write('.');
    b.write(s[k]);
  }
  return '${i < 0 ? '-' : ''}$b';
}

/// "2026-10-21" → "21 Eki"
String shortDay(String key) {
  const m = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
  final p = key.split('-');
  if (p.length != 3) return key;
  final mi = (int.tryParse(p[1]) ?? 1) - 1;
  return '${int.tryParse(p[2]) ?? p[2]} ${m[mi.clamp(0, 11)]}';
}

/// Çok serili çizgi grafiği: yumuşak çizgi, hafif dolgu, ızgara, dokununca/üstüne gelince gün özeti.
class LineChart extends StatefulWidget {
  const LineChart({super.key, required this.days, required this.lines, this.height = 220});
  final List<String> days;
  final List<ChartLine> lines;
  final double height;

  @override
  State<LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<LineChart> {
  int? _hover;

  void _pick(Offset p, Size size) {
    final n = widget.days.length;
    if (n == 0) return;
    const left = 44.0, right = 8.0;
    final w = size.width - left - right;
    final i = (((p.dx - left) / (w <= 0 ? 1 : w)) * (n - 1)).round().clamp(0, n - 1);
    if (i != _hover) setState(() => _hover = i);
  }

  @override
  Widget build(BuildContext context) {
    final i = _hover;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 14, runSpacing: 6, children: [
        for (final l in widget.lines)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: l.color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 6),
            Text(
              i != null && i < l.values.length && l.values[i] != null ? '${l.name}: ${_fmt(l.values[i]!)}' : l.name,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: HadiColors.ink2),
            ),
          ]),
        if (i != null && i < widget.days.length)
          Text(shortDay(widget.days[i]), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: HadiColors.ink)),
      ]),
      const SizedBox(height: 10),
      SizedBox(
        height: widget.height,
        child: LayoutBuilder(builder: (context, cons) {
          final size = Size(cons.maxWidth, widget.height);
          return MouseRegion(
            onHover: (e) => _pick(e.localPosition, size),
            onExit: (_) => setState(() => _hover = null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _pick(d.localPosition, size),
              onHorizontalDragUpdate: (d) => _pick(d.localPosition, size),
              child: CustomPaint(
                size: size,
                painter: _LinePainter(
                  days: widget.days,
                  lines: widget.lines,
                  hover: _hover,
                  grid: HadiColors.line,
                  label: HadiColors.ink3,
                  bg: Theme.of(context).colorScheme.surface,
                ),
              ),
            ),
          );
        }),
      ),
    ]);
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.days, required this.lines, required this.hover, required this.grid, required this.label, required this.bg});
  final List<String> days;
  final List<ChartLine> lines;
  final int? hover;
  final Color grid, label, bg;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 44.0, right = 8.0, top = 6.0, bottom = 22.0;
    final w = size.width - left - right, h = size.height - top - bottom;
    final n = days.length;
    if (n < 2 || w <= 0 || h <= 0) return;
    var maxV = 0.0;
    for (final l in lines) {
      for (final v in l.values) {
        if (v != null && v > maxV) maxV = v;
      }
    }
    // Yuvarlak üst sınır (1-2-5 basamakları).
    double nice(double v) {
      if (v <= 0) return 1;
      final p = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
      for (final m in const [1, 2, 2.5, 5, 10]) {
        if (v <= m * p) return m * p;
      }
      return 10 * p;
    }

    final top0 = nice(maxV * 1.08);
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var k = 0; k <= 4; k++) {
      final y = top + h - h * k / 4;
      canvas.drawLine(Offset(left, y), Offset(left + w, y), gp);
      tp.text = TextSpan(text: _fmt(top0 * k / 4), style: TextStyle(fontSize: 10.5, color: label));
      tp.layout();
      tp.paint(canvas, Offset(left - 6 - tp.width, y - tp.height / 2));
    }
    // X etiketleri: en çok 6 tane.
    final step = math.max(1, (n / 6).ceil());
    for (var i = 0; i < n; i += step) {
      final x = left + w * i / (n - 1);
      tp.text = TextSpan(text: shortDay(days[i]), style: TextStyle(fontSize: 10.5, color: label));
      tp.layout();
      tp.paint(canvas, Offset((x - tp.width / 2).clamp(left - 4, left + w - tp.width), top + h + 6));
    }
    Offset pt(int i, double v) => Offset(left + w * i / (n - 1), top + h - h * (v / top0));
    for (final l in lines) {
      // Kesintisiz parçalar (eksik günler boşluk bırakır).
      final segs = <List<Offset>>[];
      var cur = <Offset>[];
      for (var i = 0; i < n && i < l.values.length; i++) {
        final v = l.values[i];
        if (v == null) {
          if (cur.isNotEmpty) segs.add(cur);
          cur = <Offset>[];
        } else {
          cur.add(pt(i, v));
        }
      }
      if (cur.isNotEmpty) segs.add(cur);
      for (final s in segs) {
        final path = Path()..moveTo(s.first.dx, s.first.dy);
        for (var k = 1; k < s.length; k++) {
          final a = s[k - 1], b = s[k];
          final mx = (a.dx + b.dx) / 2;
          path.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
        }
        if (s.length > 1) {
          final fill = Path.from(path)
            ..lineTo(s.last.dx, top + h)
            ..lineTo(s.first.dx, top + h)
            ..close();
          canvas.drawPath(
            fill,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [l.color.withValues(alpha: .18), l.color.withValues(alpha: 0)],
              ).createShader(Rect.fromLTWH(left, top, w, h)),
          );
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = l.color
            ..strokeWidth = 2.2
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round,
        );
        if (s.length == 1) canvas.drawCircle(s.first, 3, Paint()..color = l.color);
      }
    }
    final hv = hover;
    if (hv != null && hv < n) {
      final x = left + w * hv / (n - 1);
      canvas.drawLine(Offset(x, top), Offset(x, top + h), Paint()
        ..color = label.withValues(alpha: .5)
        ..strokeWidth = 1);
      for (final l in lines) {
        final v = hv < l.values.length ? l.values[hv] : null;
        if (v == null) continue;
        final p = pt(hv, v);
        canvas.drawCircle(p, 5, Paint()..color = bg);
        canvas.drawCircle(p, 3.6, Paint()..color = l.color);
      }
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.hover != hover || old.lines != lines || old.days != days || old.grid != grid;
}

/// Küçük eğilim çizgisi (KPI kartları).
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, required this.color, this.height = 34});
  final List<double?> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(height: height, child: CustomPaint(painter: _SparkPainter(values, color), size: Size.infinite));
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);
  final List<double?> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = <Offset>[];
    final vs = values.whereType<double>().toList();
    if (vs.length < 2) return;
    final lo = vs.reduce(math.min), hi = vs.reduce(math.max);
    final span = (hi - lo) == 0 ? 1 : hi - lo;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) continue;
      pts.add(Offset(size.width * i / (values.length - 1), size.height - 2 - (size.height - 4) * (v - lo) / span));
    }
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(pts.last, 2.6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values || old.color != color;
}
