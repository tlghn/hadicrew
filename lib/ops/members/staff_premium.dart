// HADİ Crew
// Kaynak: hadimobile/lib/features/premium/premium.dart (21 Ekim 2026'da HADİ Crew'e taşındı).
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hadi/data/models.dart';
import 'package:hadi/features/premium/premium.dart';
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/hadi_sheet.dart';
import 'package:hadi/widgets/reason_dialog.dart';
export 'package:hadi/features/premium/premium_upsell.dart';

/// Yönetim: bir üyeye Premium ver ya da kaldır.
Future<void> staffPremiumSheet(BuildContext context, String uid, String name, {required bool isPremium}) async {
  final messenger = ScaffoldMessenger.of(context);
  final days = await showHadiSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('$name · Premium', style: Theme.of(c).textTheme.titleLarge)),
        for (final (d, t) in const [(30, '30 gün'), (90, '3 ay'), (365, '1 yıl'), (0, 'Süresiz')])
          ListTile(leading: const Text('👑'), title: Text('Premium ver: $t'), onTap: () => Navigator.pop(c, d)),
        if (isPremium)
          ListTile(
            leading: const Icon(Icons.remove_circle_outline_rounded, color: HadiColors.error),
            title: Text('Premium\'u kaldır', style: TextStyle(color: HadiColors.text(HadiColors.error))),
            onTap: () => Navigator.pop(c, -1),
          ),
      ])),
    ),
  );
  if (days == null || !context.mounted) return;
  // Zorunlu gerekçe: yönetimin verdiği/kaldırdığı Premium, işlemi yapan ve gerekçesiyle kayda geçer.
  final reason = await askReason(
    context,
    title: days < 0 ? '$name · Premium kaldırılsın mı?' : '$name · Premium ver',
    confirm: days < 0 ? 'Kaldır' : 'Ver',
    danger: days < 0,
    hint: days < 0 ? 'Neden? Örn. "Tanıtım süresi sona erdi."' : 'Neden? Örn. "Etkinlik gönüllüsü, 3 aylık teşekkür."',
  );
  if (reason == null) return;
  try {
    if (days < 0) {
      await PremiumApi.instance.revoke(uid, reason: reason);
      messenger.showSnackBar(const SnackBar(content: Text('Premium kaldırıldı.')));
    } else {
      await PremiumApi.instance.grant(uid, days: days, reason: reason);
      messenger.showSnackBar(const SnackBar(content: Text('Premium tanımlandı 👑')));
    }
  } on AppFailure catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}
