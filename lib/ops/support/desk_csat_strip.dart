// Destek masası memnuniyet (CSAT) şeridi: destek masası ekranında (yetkili ekip).
import 'package:flutter/material.dart';
import 'package:hadi/core/service_switches.dart';
import 'package:hadi/data/models.dart' show AppFailure;
import 'package:hadi/data/support_desk_service.dart';
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/theme/hadi_icons.dart';
import 'package:hadi/widgets/auto_marquee_text.dart';

/// Destek masasının üstündeki çözüm puanı (CSAT) şeridi — son 30 gün. Hizmet anahtarı support_desk_plus.
class DeskCsatStrip extends StatefulWidget {
  const DeskCsatStrip({super.key});
  @override
  State<DeskCsatStrip> createState() => _DeskCsatStripState();
}

class _DeskCsatStripState extends State<DeskCsatStrip> {
  Map? _d;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await SupportDesk.instance.csat();
      if (mounted) setState(() => _d = d);
    } on AppFailure {
      // sessiz: şerit yalnızca bilgi amaçlı
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: ServiceSwitches.instance,
        builder: (context, _) {
          final d = _d;
          if (ServiceSwitches.instance.isHidden('support_desk_plus') || d == null) return const SizedBox.shrink();
          final avg = d['avg'];
          final dist = (d['dist'] as List?) ?? const [];
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: HadiColors.goldSoft, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const HadiIcon(Icons.star_rounded, color: HadiColors.gold, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: AutoMarqueeText(
                    avg is num
                        ? 'CSAT (30 gün): ${avg.toStringAsFixed(2).replaceAll('.', ',')}/5 · ${d['n']} puan · memnun %${d['satisfied'] ?? '—'} · '
                            'yanıt oranı %${d['responseRate'] ?? '—'} · dağılım ${[for (var i = 0; i < dist.length; i++) '${i + 1}★${dist[i]}'].join(' ')}'
                        : 'CSAT (30 gün): henüz puan yok · ${d['resolved'] ?? 0} çözülen talep',
                    style: TextStyle(color: HadiColors.ink, fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                ),
              ]),
            ),
          );
        },
      );
}
