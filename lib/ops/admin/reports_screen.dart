import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hadi/core/capabilities.dart' show Cap;
import 'package:hadi/core/format.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/data/chat_models.dart';
import 'package:hadi/data/models.dart';
import 'package:hadi/panel_ui/crew_ui.dart';
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/common.dart';
import '../moderation/content_hide_staff.dart' show canHideContent;
import 'package:hadi/features/gif/gif_picker.dart' show GifView;

import 'package:hadi/widgets/net_fallback.dart';
import 'package:hadi/core/service_switches.dart';
import 'ops/mod_queue_screen.dart' show ModQueueScreen;
import 'package:hadi/data/privacy_hub_service.dart' show PrivacyHubApi;
/// Moderasyon kuyruğu: yalnızca şikâyet edenin gönderdiği kopya görünür (tek mesaj; "Raporla" ile gelen şikâyetlerde
/// şikâyet edenin seçtiği/gördüğü bağlam mesajları — hadimobile functions/src/chat_report.ts, secret_chat.ts), sohbetin
/// geri kalanına erişim yoktur. Her karar kayda geçer.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Stream<List<MessageReport>>? _stream;
  final _busy = <String>{};

  /// Bu oturumda Verime erişim günlüğüne yazılan şikayetler (ekranda içeriği gösterilen her şikayet bir kez; davaya bağlı).
  final _logged = <String>{};

  void _logShown(List<MessageReport> list) {
    for (final r in list) {
      if (_logged.add(r.id)) unawaited(PrivacyHubApi.instance.caseOpen('report', r.id));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= SessionScope.read(context).services.chat.watchOpenReports();
  }

  Future<void> _resolve(MessageReport r, bool remove) async {
    setState(() => _busy.add(r.id));
    try {
      await SessionScope.read(context).services.chat.resolveReport(r.id, remove: remove);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(remove ? 'Mesaj kaldırıldı.' : 'Şikayet kapatıldı.')));
    } on AppFailure catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final ses = SessionScope.of(context);
    // Diğer kuyruklara kısayollar tek menüde (telefonda üst çubuk sekiz simgeyle dolup başlığı eziyordu).
    final shortcuts = <(IconData, String, VoidCallback)>[
      if (!ServiceSwitches.instance.isHidden('mod_queue'))
        (Icons.gavel_rounded, 'Moderasyon kuyruğu', () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ModQueueScreen()))),
      (Icons.sensors_rounded, 'Canlı yayın şikâyetleri', () => context.push('/b/canli')),
      (Icons.shield_outlined, 'AI güvenliği', () => context.push('/b/ai-guvenligi')),
      (Icons.support_agent_rounded, 'Destek talepleri', () => context.push('/b/destek')),
      if (ses.isFounder || ses.can(Cap.identityReview)) (Icons.badge_rounded, 'Kimlik doğrulamaları', () => context.push('/b/kimlik')),
      if (ses.isFounder || ses.can(Cap.addressReview)) (Icons.home_work_rounded, 'Adres belgeleri', () => context.push('/b/adres')),
      if (ses.isFounder || ses.can(Cap.kahveSafety)) (Icons.coffee_rounded, 'Kahve güvenliği', () => context.push('/b/kahve')),
      if (canHideContent(ses)) (Icons.visibility_off_rounded, 'Gizlenen gönderiler', () => context.push('/b/gizlenen')),
    ];
    return Scaffold(
      backgroundColor: crewCanvas(context),
      appBar: AppBar(title: const Text('Mesaj şikâyetleri', maxLines: 1, overflow: TextOverflow.ellipsis), actions: [
        PopupMenuButton<int>(
          tooltip: 'Diğer kuyruklar',
          icon: const Icon(Icons.more_horiz_rounded),
          onSelected: (i) => shortcuts[i].$3(),
          itemBuilder: (_) => [
            for (var i = 0; i < shortcuts.length; i++)
              PopupMenuItem(value: i, child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(shortcuts[i].$1, size: 20), title: Text(shortcuts[i].$2))),
          ],
        ),
        const SizedBox(width: 8),
      ]),
      body: StreamBuilder<List<MessageReport>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) return CrewMaxWidth(maxWidth: 880, child: CrewError(message: '${snap.error}'));
          if (!snap.hasData) return const CrewMaxWidth(maxWidth: 880, child: Padding(padding: EdgeInsets.only(top: 24), child: CrewLoading()));
          final list = snap.data!;
          _logShown(list);
          final side = CrewSpace.gutter(context);
          return LayoutBuilder(builder: (context, cons) {
          final pad = cons.maxWidth > 880 + 2 * side ? (cons.maxWidth - 880) / 2 : side;
          return ListView(padding: EdgeInsets.fromLTRB(pad, 20, pad, 32), children: [
            const InfoNote(
              icon: Icons.policy_outlined,
              color: HadiColors.iletisim,
              text: 'Burada yalnızca şikâyet edenin gönderdiği kopyayı görürsün: tek mesaj ya da "Raporla" ile eklenen bağlam '
                  '(sohbet şikâyetinde en çok 50 mesaj). Sohbetin geri kalanına erişim yoktur. Kaldırma ve kapatma kararların yönetim kayıtlarına işlenir.',
            ),
            const SizedBox(height: 14),
            if (list.isEmpty)
              const CrewCard(child: CrewEmpty(icon: Icons.flag_outlined, title: 'Açık şikâyet yok', message: 'Bir mesaj şikâyet edilince burada görünür.')),
            for (final r in list)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                color: crewCardColor(context),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: HadiColors.pink.withValues(alpha: .12), borderRadius: BorderRadius.circular(99)),
                        child: Text(r.reason, style: TextStyle(fontWeight: FontWeight.w800, color: HadiColors.text(HadiColors.pink), fontSize: 12)),
                      ),
                      const Spacer(),
                      if (r.createdAt != null) Text(dateTimeLong(r.createdAt!), style: text.bodySmall),
                    ]),
                    const SizedBox(height: 10),
                    Text(
                      '${r.targetName.isEmpty ? 'Üye' : r.targetName} · ${switch (r.kind) {
                        'dm_chat' => 'sohbet şikâyeti (${r.items.length} mesaj)',
                        'secret_message' => 'gizli sohbet (doğrulanmış kopya)',
                        _ => r.chatType == 'channel' ? '#${r.chatTitle}' : r.chatType == 'group' ? 'grup sohbeti' : 'birebir sohbet',
                      }}',
                      style: text.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    if (r.items.isNotEmpty)
                      _Transcript(items: r.items, targetName: r.targetName)
                    else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: HadiColors.mist, borderRadius: BorderRadius.circular(12)),
                      child: switch (r.type) {
                        'image' when r.mediaUrl != null => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(r.mediaUrl!, height: 180, fit: BoxFit.cover, errorBuilder: NetImageFallback.builder)),
                            if (r.text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(r.text)),
                          ]),
                        // GIF: sohbet balonundaki gibi önizleme + zorunlu KLIPY atfı.
                        'gif' => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            GifView.fromMap(r.gif, maxWidth: 220) ??
                                (r.mediaUrl != null ? GifView(url: r.mediaUrl!, maxWidth: 220) : const Text('🎞️ GIF (önizleme yok)')),
                            if (r.text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(r.text)),
                          ]),
                        'voice' => const Text('🎤 Sesli mesaj (kopyası arşivde)'),
                        'location' || 'live' => const Text('📍 Konum paylaşımı'),
                        'poll' => Text('📊 Anket: ${r.text}'),
                        _ => Text(r.text.isEmpty ? '(boş)' : r.text),
                      },
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(spacing: CrewSpace.sm, runSpacing: CrewSpace.sm, children: [
                        OutlinedButton(onPressed: _busy.contains(r.id) ? null : () => _resolve(r, false), child: const Text('Şikâyeti kapat')),
                        // Sohbet şikâyeti (dm_chat) tek mesaja bağlı değil: yalnızca kapatılır.
                        if (r.hasMessage)
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: HadiColors.fillForWhite(HadiColors.error), foregroundColor: Colors.white),
                          onPressed: _busy.contains(r.id) ? null : () => _resolve(r, true),
                          child: const Text('Mesajı kaldır'),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
          ]);
          });
        },
      ),
    );
  }
}

/// "Raporla" ile gelen bağlam: şikâyet edenin gönderdiği mesaj kopyaları (eskiden yeniye). Odak mesaj vurgulu.
class _Transcript extends StatelessWidget {
  const _Transcript({required this.items, required this.targetName});
  final List<ReportItem> items;
  final String targetName;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 420),
      decoration: BoxDecoration(color: HadiColors.mist, borderRadius: BorderRadius.circular(12)),
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(10), children: [
        for (final it in items)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: it.focus ? HadiColors.pink.withValues(alpha: .10) : null,
              borderRadius: BorderRadius.circular(8),
              border: it.focus ? Border.all(color: HadiColors.pink.withValues(alpha: .5)) : null,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '${it.who.isEmpty ? 'Üye' : it.who}${it.at == null ? '' : ' · ${dateTimeLong(it.at!)}'}${it.focus ? ' · şikâyet edilen' : ''}',
                style: text.labelSmall?.copyWith(fontWeight: FontWeight.w800, color: it.who == targetName ? HadiColors.text(HadiColors.pink) : HadiColors.ink2),
              ),
              const SizedBox(height: 2),
              if (it.deleted)
                Text('🚫 Silinmiş mesaj', style: text.bodySmall?.copyWith(color: HadiColors.ink3))
              else if (it.type == 'image' && it.mediaUrl != null)
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(it.mediaUrl!, height: 140, fit: BoxFit.cover, errorBuilder: NetImageFallback.builder)),
                  if (it.text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(it.text)),
                ])
              else if (it.type == 'voice')
                Text(it.mediaUrl == null ? '🎤 Sesli mesaj' : '🎤 Sesli mesaj (kanıt kopyası kayıtlı)')
              else if (it.type == 'location' || it.type == 'live')
                const Text('📍 Konum paylaşımı')
              else if (it.type == 'gif')
                Text('🎞️ GIF ${it.text}')
              else
                Text(it.text.isEmpty ? '(boş)' : it.text),
            ]),
          ),
      ]),
    );
  }
}
