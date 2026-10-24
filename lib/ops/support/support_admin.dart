import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hadi/panel_ui/crew_ui.dart' show CrewMaxWidth, crewCanvas;

import 'support_admin_desk.dart' show SupportDeskAdmin;

/// Yetkili (kurucu, yönetici, moderatör): "Destek masası" — HADİ Destek 2.0 talep kuyruğu, hazır cevaplar,
/// durum bandı, boşluklar ve günlük mesaj sınırları (support_admin_desk.dart).
/// Giriş: kurucu paneli sekmesi, Şikayetler ekranı ve bildirim bağlantısı (/destek-talepleri).
class SupportTicketsScreen extends StatelessWidget {
  const SupportTicketsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Genişte talep listesi en fazla 1040 px, ortada (satırlar ekran boyu uzamasın).
    return Scaffold(
      backgroundColor: crewCanvas(context),
      appBar: AppBar(title: const Text('Destek masası')),
      body: const CrewMaxWidth(maxWidth: 1040, padded: false, child: SupportDeskAdmin()),
    );
  }
}

/// Kısayol: yetkililer için Destek masasını açar.
void openSupportTickets(BuildContext context) => context.push('/b/destek');
