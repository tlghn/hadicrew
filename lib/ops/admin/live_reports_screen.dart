import 'package:flutter/material.dart';

import 'package:hadi/core/format.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/data/live_service.dart';
import 'package:hadi/data/models.dart';
import 'package:hadi/panel_ui/crew_ui.dart';
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/hadi_sheet.dart';

/// Canlı yayın denetim raporları: otomatik denetimin durdurduğu ya da uyardığı
/// yayınlar. Yönetim inceler; hatalıysa yayıncıya haber verilir, ağırsa süreli
/// kısıtlama uygulanır. Her karar kayda geçer.
class LiveReportsScreen extends StatefulWidget {
  const LiveReportsScreen({super.key});

  @override
  State<LiveReportsScreen> createState() => _LiveReportsScreenState();
}

class _LiveReportsScreenState extends State<LiveReportsScreen> {
  Stream<List<LiveReport>>? _stream;
  bool _onlyOpen = true;
  final _busy = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= SessionScope.read(context).services.live.watchReports();
  }

  Future<void> _decide(LiveReport r) async {
    final note = TextEditingController();
    final decision = await showHadiSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Karar: ${r.hostName}', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            TextField(controller: note, maxLength: 300, decoration: const InputDecoration(hintText: 'Not (isteğe bağlı)')),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, 'dismiss'),
              icon: const Icon(Icons.undo_rounded),
              label: const Text('Hatalı tespit — yayıncıya haber ver'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(onPressed: () => Navigator.pop(ctx, 'uphold'), child: const Text('Onayla (kısıtlama yok)')),
            const SizedBox(height: 8),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'ban7'), child: const Text('Onayla + 7 gün yayın kısıtlaması')),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: HadiColors.fillForWhite(HadiColors.heyecan), foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, 'ban30'),
              child: const Text('Onayla + 30 gün yayın kısıtlaması'),
            ),
          ]),
        ),
      ),
    );
    final text = note.text.trim();
    note.dispose();
    if (decision == null || !mounted) return;
    setState(() => _busy.add(r.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SessionScope.read(context).services.live.resolveReport(r.id, decision, note: text);
      messenger.showSnackBar(const SnackBar(content: Text('Karar kaydedildi.')));
    } on AppFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  static const _decisionText = {
    'dismiss': 'Hatalı tespit',
    'uphold': 'Onaylandı',
    'ban7': '7 gün kısıtlama',
    'ban30': '30 gün kısıtlama',
  };

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LiveReport>>(
      stream: _stream,
      builder: (context, snap) {
        final List<Widget> children;
        if (snap.hasError) {
          children = [CrewCard(child: CrewError(message: '${snap.error}'))];
        } else if (!snap.hasData) {
          children = const [CrewCard(child: CrewLoading())];
        } else {
          final list = [for (final r in snap.data!) if (!_onlyOpen || r.open) r];
          children = [
            if (list.isEmpty)
              CrewCard(
                child: CrewEmpty(
                  icon: Icons.live_tv_outlined,
                  title: _onlyOpen ? 'Bekleyen rapor yok' : 'Rapor yok',
                  message: 'Otomatik denetim bir yayını durdurur ya da uyarırsa burada görünür.',
                ),
              ),
            for (final r in list) _item(r),
          ];
        }
        return CrewPage(
          title: 'Canlı yayın raporları',
          subtitle: 'Otomatik denetimin durdurduğu ya da uyardığı yayınlar',
          maxWidth: 920,
          gap: CrewSpace.md,
          toolbar: CrewFilterChips<bool>(
            options: const [(true, 'Açık'), (false, 'Tümü')],
            value: _onlyOpen,
            onChanged: (v) => setState(() => _onlyOpen = v),
          ),
          children: children,
        );
      },
    );
  }

  Widget _item(LiveReport r) {
    final t = Theme.of(context).textTheme;
    final src = switch (r.source) { 'audio' => 'ses', 'video' => 'görüntü', 'chat' => 'sohbet', _ => r.source };
    return CrewQueueCard(
      title: '${r.hostName} · ${r.label}',
      // Konuşmada küfür denetimi (functions/src/live_speech_guard.ts): muted = 1 dk sessize alındı, speech_off = yayın boyunca
      // mikrofonu kapatıldı (tekrar; incelemeye düşer).
      pill: switch (r.action) {
        'stopped' => const CrewPill('Durduruldu', color: HadiColors.error),
        'muted' => const CrewPill('1 dk sessize alındı', color: HadiColors.heyecan),
        'speech_off' => const CrewPill('Mikrofonu kapatıldı', color: HadiColors.error),
        _ => const CrewPill('Uyarı', color: HadiColors.heyecan),
      },
      meta: '${r.createdAt != null ? '${dateTimeLong(r.createdAt!)} · ' : ''}kaynak: $src · güven ${(r.confidence * 100).round()}%',
      details: [
        if (r.reason.isNotEmpty) Text(r.reason, style: t.bodyMedium),
        if (r.evidence.isNotEmpty) CrewQuote('“${r.evidence}”', color: HadiColors.ink3),
        if (r.status == 'auto')
          Text('Kendiliğinden uygulandı; inceleme gerekmiyor.', style: t.bodySmall?.copyWith(color: HadiColors.ink3))
        else if (!r.open) Text('Karar: ${_decisionText[r.decision] ?? 'Kapatıldı'}', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: HadiColors.text(HadiColors.dostluk))),
      ],
      actions: [
        if (r.open) FilledButton(onPressed: _busy.contains(r.id) ? null : () => _decide(r), child: const Text('İncele ve karar ver')),
      ],
    );
  }
}
