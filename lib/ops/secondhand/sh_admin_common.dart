// HADİ Crew — 2. El yönetimi ortak parçaları. Sunucu: `secondhand` callable'ının "admin*" op'ları (functions/src/secondhand_admin.ts).
// Yetki: kurucu ya da `secondhand.manage`; asıl denetim sunucudadır. Tanıtım (PANEL_DEMO): lib/data/secondhand_demo.dart.
// Arayüz: package:hadi/panel_ui/crew_ui.dart (CrewPage, CrewCard, CrewListCard, CrewPill…) — kendi tema/alan süslemesi yok.
import 'package:flutter/material.dart';
import 'package:hadi/core/capabilities.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/data/models.dart' show AppFailure;
import 'package:hadi/data/secondhand_service.dart';
import 'package:hadi/panel_ui/crew_ui.dart';
import 'package:hadi/theme/hadi_colors.dart';

export 'package:hadi/data/secondhand_service.dart';

/// 2. El yönetimini görebilir mi.
bool canManageSecondhand(Session s) => s.isFounder || s.can(Cap.secondhandManage);

SecondhandService shAdminOf(BuildContext context) => SecondhandService.of(SessionScope.read(context).services);

Future<Map<String, dynamic>?> shAdminCall(BuildContext context, String op, [Map<String, Object?> data = const {}, String? ok]) async {
  try {
    final r = await shAdminOf(context).admin(op, data);
    if (ok != null && context.mounted) crewToast(context, ok);
    return r;
  } catch (e) {
    if (context.mounted) crewToast(context, e is AppFailure ? e.message : 'İşlem tamamlanamadı.');
    return null;
  }
}

DateTime? shMs(Object? v) => v is num && v > 0 ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

String shWhen(Object? v) {
  final d = shMs(v);
  if (d == null) return '—';
  const months = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
  return '${d.day} ${months[d.month - 1]} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

const kShQueueKinds = <(String, String, IconData)>[
  ('listing', 'İlan incelemesi', Icons.fact_check_outlined),
  ('appeal', 'İtirazlar', Icons.gavel_rounded),
  ('report', 'Şikâyetler', Icons.flag_outlined),
  ('fraud', 'Dolandırıcılık', Icons.policy_outlined),
  ('dispute', 'Uyuşmazlıklar', Icons.report_outlined),
  ('shipping', 'Kargo kaydı', Icons.local_shipping_outlined),
];

String shKindLabel(String k) => kShQueueKinds.where((x) => x.$1 == k).firstOrNull?.$2 ?? k;
IconData shKindIcon(String k) => kShQueueKinds.where((x) => x.$1 == k).firstOrNull?.$3 ?? Icons.inbox_outlined;

Color shPriorityColor(String p) => switch (p) {
      'high' => HadiColors.error,
      'low' => HadiColors.dostluk,
      _ => HadiColors.heyecan,
    };
String shPriorityLabel(String p) => switch (p) {
      'high' => 'Yüksek',
      'low' => 'Düşük',
      _ => 'Orta',
    };

Color shOrderColor(String s) => switch (s) {
      'completed' => HadiColors.dostluk,
      'disputed' || 'returning' => HadiColors.error,
      'cancelled' || 'refunded' => HadiColors.navy,
      'delivered' => HadiColors.gold,
      _ => HadiColors.aktivite,
    };

const kShOrderStatuses = <(String, String)>[
  ('', 'Tümü'), ('paid', 'Ödendi'), ('shipped', 'Kargoda'), ('delivered', 'Teslim'), ('disputed', 'Uyuşmazlık'), ('returning', 'İade'),
  ('completed', 'Tamamlandı'), ('cancelled', 'İptal'), ('refunded', 'İade edildi'),
];

/// Liste satırı küçük görseli (fotoğraf yoksa kategori emojisi).
class ShAdminThumb extends StatelessWidget {
  const ShAdminThumb({super.key, this.url, this.emoji = '📦', this.size = 48});
  final String? url;
  final String emoji;
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: size,
          height: size,
          child: url == null || url!.isEmpty
              ? ColoredBox(color: HadiColors.wash(HadiColors.dostluk, .85), child: Center(child: Text(emoji, style: TextStyle(fontSize: size * .45))))
              : Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => Center(child: Text(emoji))),
        ),
      );
}
