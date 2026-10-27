import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hadi/features/events/event_edit_screen.dart' show EventEditScreen;
import 'package:hadi/features/events/wizard/event_wizard.dart' show EventWizardLink;
import 'package:hadi/theme/hadi_colors.dart';

/// Kulüp etkinliği oluştur (yönetim kipi). Kaydedince [EventCreatedPage]'e geçer.
class EventCreateScreen extends StatelessWidget {
  const EventCreateScreen({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        // Uygulamanın telefon formu: geniş ekranda okunur genişlikte ortalanır. Üstte belirgin "Sihirbazla etkinlik oluştur" kartı
        // (hadi › features/events/wizard/event_wizard.dart; hizmet event_ai_assistant kapalıysa görünmez).
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(children: [
              const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 0), child: EventWizardLink(kind: 'club', prominent: true)),
              const Expanded(child: EventEditScreen(showWizardLink: false)),
            ]),
          ),
        ),
      );
}

/// Etkinlik kaydedildikten sonra (uygulamadaki `/etkinlik/{id}` yolunun Crew karşılığı).
class EventCreatedPage extends StatelessWidget {
  const EventCreatedPage({super.key, required this.id, this.fromMember = false});
  final String id;

  /// Üye etkinlikleri ekranından açıldıysa (yeni kayıt değil).
  final bool fromMember;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Etkinlik')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.event_available_rounded, size: 48, color: HadiColors.text(HadiColors.dostluk)),
              const SizedBox(height: 14),
              Text(fromMember ? 'Üye etkinliği yayında' : 'Etkinlik kaydedildi', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Üyeler uygulamada Etkinlikler sekmesinde görür.', textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: HadiColors.ink2)),
              const SizedBox(height: 4),
              SelectableText('Kimlik: $id', style: text.bodySmall?.copyWith(color: HadiColors.ink3)),
              const SizedBox(height: 20),
              Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
                FilledButton.icon(onPressed: () => context.go('/b/etkinlik-ekle'), icon: const Icon(Icons.add_rounded), label: const Text('Yeni etkinlik')),
                OutlinedButton(onPressed: () => context.go('/'), child: const Text('Panoya dön')),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
