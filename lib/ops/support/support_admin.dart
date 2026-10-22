import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'support_admin_desk.dart' show SupportDeskAdmin;

/// Yetkili (kurucu, yönetici, moderatör): "Destek masası" — HADİ Destek 2.0 talep kuyruğu, hazır cevaplar,
/// durum bandı, boşluklar ve günlük mesaj sınırları (support_admin_desk.dart).
/// Giriş: kurucu paneli sekmesi, Şikayetler ekranı ve bildirim bağlantısı (/destek-talepleri).
class SupportTicketsScreen extends StatelessWidget {
  const SupportTicketsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Destek masası')), body: const SupportDeskAdmin());
  }
}

/// Kısayol: yetkililer için Destek masasını açar.
void openSupportTickets(BuildContext context) => context.push('/b/destek');
