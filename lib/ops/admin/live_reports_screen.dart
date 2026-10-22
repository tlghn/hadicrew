import 'package:flutter/material.dart';

import 'package:hadi/core/format.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/data/live_service.dart';
import 'package:hadi/data/models.dart';
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/hadi_sheet.dart';
import 'package:hadi/features/fun/_placeholders.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Canlı yayın raporları', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          FilterChip(label: const Text('Açık'), selected: _onlyOpen, onSelected: (v) => setState(() => _onlyOpen = v)),
          const SizedBox(width: 12),
        ],
      ),
      body: StreamBuilder<List<LiveReport>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Yüklenemedi: ${snap.error}', textAlign: TextAlign.center));
          if (!snap.hasData) return const RowsSkeleton();
          final list = [for (final r in snap.data!) if (!_onlyOpen || r.open) r];
          if (list.isEmpty) {
            return Center(child: Padding(padding: EdgeInsets.all(28), child: Text('Bekleyen rapor yok 🎉', style: TextStyle(color: HadiColors.ink3))));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final r = list[i];
              final stopped = r.action == 'stopped';
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: HadiColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: r.open ? (stopped ? HadiColors.heyecan : HadiColors.line) : HadiColors.line),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(stopped ? '🔴 Durduruldu' : '⚠️ Uyarı', style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(r.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
                    if (r.createdAt != null) Text(dateTimeLong(r.createdAt!), style: TextStyle(color: HadiColors.ink3, fontSize: 11.5)),
                  ]),
                  const SizedBox(height: 6),
                  Text('${r.hostName} · kaynak: ${switch (r.source) { 'audio' => 'ses', 'video' => 'görüntü', 'chat' => 'sohbet', _ => r.source }} · güven ${(r.confidence * 100).round()}%',
                      style: TextStyle(color: HadiColors.ink2, fontSize: 12.5)),
                  if (r.reason.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(r.reason)),
                  if (r.evidence.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: HadiColors.mist, borderRadius: BorderRadius.circular(10)),
                      child: Text('“${r.evidence}”', style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13)),
                    ),
                  const SizedBox(height: 10),
                  if (r.open)
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(onPressed: _busy.contains(r.id) ? null : () => _decide(r), child: const Text('İncele ve karar ver')),
                    )
                  else
                    Text('✔ ${_decisionText[r.decision] ?? 'Kapatıldı'}', style: TextStyle(color: HadiColors.text(HadiColors.dostluk), fontWeight: FontWeight.w800)),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
