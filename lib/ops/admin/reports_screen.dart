import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:hadi/core/capabilities.dart' show Cap;
import 'package:hadi/core/format.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/data/chat_models.dart';
import 'package:hadi/data/models.dart';
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/common.dart';
import '../moderation/content_hide_staff.dart' show canHideContent;
import 'package:hadi/features/gif/gif_picker.dart' show GifView;

import 'package:hadi/widgets/net_fallback.dart';
import 'package:hadi/features/fun/_placeholders.dart';
import 'package:hadi/core/service_switches.dart';
import 'ops/mod_queue_screen.dart' show ModQueueScreen;
import 'package:hadi/data/privacy_hub_service.dart' show PrivacyHubApi;
/// Moderasyon kuyruğu: yalnızca şikayet edilen mesajın kopyası görünür,
/// sohbetin geri kalanı görünmez. Her karar kayda geçer.
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
    return Scaffold(
      appBar: AppBar(title: const Text('Şikayetler', maxLines: 1, overflow: TextOverflow.ellipsis), actions: [
        // Operasyon › Moderasyon kuyruğu (tek kuyruk, SLA, gerekçeli kararlar, itirazlar; hizmet anahtarı mod_queue).
        if (!ServiceSwitches.instance.isHidden('mod_queue'))
          IconButton(
            tooltip: 'Moderasyon kuyruğu',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ModQueueScreen())),
            icon: const Icon(Icons.gavel_rounded),
          ),
        TextButton.icon(
          onPressed: () => context.push('/b/canli'),
          icon: const Icon(Icons.sensors_rounded),
          label: const Text('Canlı yayın'),
        ),
        IconButton(
          tooltip: 'AI güvenliği',
          onPressed: () => context.push('/b/ai-guvenligi'),
          icon: const Icon(Icons.shield_outlined),
        ),
        IconButton(
          tooltip: 'Destek talepleri',
          onPressed: () => context.push('/b/destek'),
          icon: const Icon(Icons.support_agent_rounded),
        ),
        // Kimlik doğrulama incelemesi: kurucu ya da identity.review.
        if (SessionScope.of(context).isFounder || SessionScope.of(context).can(Cap.identityReview))
          IconButton(
            tooltip: 'Kimlik doğrulamaları',
            onPressed: () => context.push('/b/kimlik'),
            icon: const Icon(Icons.badge_rounded),
          ),
        // Adres belgeleri (adres doğrulaması) ve Kahve güvenlik incelemesi: kurucu ya da ilgili yetenek.
        if (SessionScope.of(context).isFounder || SessionScope.of(context).can(Cap.addressReview))
          IconButton(
            tooltip: 'Adres belgeleri',
            onPressed: () => context.push('/b/adres'),
            icon: const Icon(Icons.home_work_rounded),
          ),
        if (SessionScope.of(context).isFounder || SessionScope.of(context).can(Cap.kahveSafety))
          IconButton(
            tooltip: 'Kahve güvenliği',
            onPressed: () => context.push('/b/kahve'),
            icon: const Icon(Icons.coffee_rounded),
          ),
        // Gizlenen gönderiler (kurucu / `content.hide` yetenekli roller)
        if (canHideContent(SessionScope.of(context)))
          IconButton(
            tooltip: 'Gizlenen gönderiler',
            onPressed: () => context.push('/b/gizlenen'),
            icon: const Icon(Icons.visibility_off_rounded),
          ),
      ]),
      body: StreamBuilder<List<MessageReport>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Yüklenemedi: ${snap.error}'));
          if (!snap.hasData) return const RowsSkeleton();
          final list = snap.data!;
          _logShown(list);
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            const InfoNote(
              icon: Icons.policy_outlined,
              color: HadiColors.iletisim,
              text: 'Burada yalnızca şikayet edilen mesajın bir kopyasını görürsün; sohbetin geri kalanına erişim yoktur. '
                  'Kaldırma ve kapatma kararların yönetim kayıtlarına işlenir.',
            ),
            const SizedBox(height: 14),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 60),
                child: Center(child: Text('Açık şikayet yok. 🎉', style: text.titleMedium?.copyWith(color: HadiColors.ink3))),
              ),
            for (final r in list)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
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
                      '${r.targetName.isEmpty ? 'Üye' : r.targetName} · ${r.chatType == 'channel' ? '#${r.chatTitle}' : 'birebir sohbet'}',
                      style: text.titleSmall,
                    ),
                    const SizedBox(height: 8),
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
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(onPressed: _busy.contains(r.id) ? null : () => _resolve(r, false), child: const Text('Kapat')),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: HadiColors.fillForWhite(HadiColors.error), foregroundColor: Colors.white),
                          onPressed: _busy.contains(r.id) ? null : () => _resolve(r, true),
                          child: const Text('Mesajı kaldır'),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
