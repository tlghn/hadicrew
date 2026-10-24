import 'package:flutter/material.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/data/member_models.dart' show MemberProfile;
import 'package:hadi/features/messages/chat_widgets.dart' show ChatAvatar;
import 'package:hadi/panel_ui/crew_ui.dart';
import 'package:hadi/theme/hadi_colors.dart';

import '../ops/admin/hp_economy_admin.dart' show showHpGrantSheet;
import '../ops/admin/roles_admin.dart' show openUserRolesSheet, pickMemberForRole;
import '../ops/members/staff_premium.dart' show staffPremiumSheet;
import '../ops/moderation/mod_sheet.dart' show openModSheet;
import 'package:hadi/core/ui_gate.dart';

/// Üye işlemleri: üyeyi bul, ardından rol / Premium / Elmas / moderasyon. Her işlem gerekçe ister ve kayda geçer
/// (sunucu). Uygulamada bu işlemler yoktur.
class MemberToolsScreen extends StatefulWidget {
  const MemberToolsScreen({super.key});

  @override
  State<MemberToolsScreen> createState() => _MemberToolsScreenState();
}

class _MemberToolsScreenState extends State<MemberToolsScreen> {
  /// Bu oturumda açılan üyeler (en yeni üstte; yalnızca bellekte).
  static final List<MemberProfile> _recent = [];

  Future<void> _find() async {
    final m = await pickMemberForRole(context, title: 'Üye bul');
    if (m == null || !mounted) return;
    setState(() {
      _recent.removeWhere((x) => x.uid == m.uid);
      _recent.insert(0, m);
      if (_recent.length > 12) _recent.removeLast();
    });
    _actions(m);
  }

  void _actions(MemberProfile m) {
    final s = SessionScope.read(context);
    uiOnce(context, () => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (c) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: ChatAvatar(uid: m.uid, name: m.publicName, photoUrl: m.photoUrl, size: 44),
            title: Text(m.staffLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text([if ((m.username ?? '').isNotEmpty) '@${m.username}', if (m.isPremium) 'Premium'].join(' · ')),
          ),
          const Divider(),
          if (s.isAdmin)
            _Action(
              icon: Icons.theater_comedy_rounded,
              title: 'Roller',
              subtitle: 'Rol ver ya da al (kapsamlı roller dahil)',
              onTap: () {
                Navigator.pop(c);
                openUserRolesSheet(context, uid: m.uid, name: m.staffLabel);
              },
            ),
          if (s.isAdmin)
            _Action(
              icon: Icons.workspace_premium_rounded,
              title: m.isPremium ? 'Premium (yönetim)' : 'Premium ver',
              subtitle: 'Süreli Premium; gerekçe zorunlu',
              onTap: () {
                Navigator.pop(c);
                staffPremiumSheet(context, m.uid, m.publicFirstName, isPremium: m.isPremium);
              },
            ),
          if (s.isFounder)
            _Action(
              icon: Icons.diamond_rounded,
              title: 'Elmas yükle ya da düş',
              subtitle: 'Gerekçeli; cüzdan defterine yazılır (kurucu)',
              onTap: () {
                Navigator.pop(c);
                showHpGrantSheet(context, uid: m.uid, name: m.staffLabel);
              },
            ),
          if (s.canModerate)
            _Action(
              icon: Icons.shield_moon_rounded,
              title: 'Moderasyon',
              subtitle: 'Uyarı ver, blokla, içerik kaldır, geçmiş',
              onTap: () {
                Navigator.pop(c);
                openModSheet(context, uid: m.uid, name: m.staffLabel);
              },
            ),
        ]),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CrewPage(
      title: 'Üye işlemleri',
      subtitle: 'Rol, Premium, Elmas, moderasyon — her işlem gerekçeyle kayda geçer',
      maxWidth: CrewWidth.form,
      children: [
        // Arama kutusu görünümlü düğme: üye seçiciyi açar.
        Material(
          color: crewCardColor(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: cs.outlineVariant)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _find,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: CrewSpace.lg, vertical: CrewSpace.lg),
              child: Row(children: [
                Icon(Icons.person_search_rounded, color: cs.primary),
                const SizedBox(width: CrewSpace.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Üye bul', style: Theme.of(context).textTheme.titleMedium),
                    Text('Ad, kullanıcı adı ya da telefon numarası', style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
                FilledButton(onPressed: _find, child: const Text('Ara')),
              ]),
            ),
          ),
        ),
        CrewListCard(
          title: 'Son açılanlar',
          subtitle: _recent.isEmpty ? null : 'Bu oturumda açtığın üyeler',
          empty: const CrewEmpty(
            icon: Icons.history_rounded,
            title: 'Henüz üye açılmadı',
            message: 'Bir üyeyi bulduğunda işlemler penceresi açılır; burada da listelenir.',
          ),
          children: [
            for (final m in _recent)
              ListTile(
                leading: ChatAvatar(uid: m.uid, name: m.publicName, photoUrl: m.photoUrl, size: 40),
                title: Text(m.staffLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: (m.username ?? '').isEmpty ? null : Text('@${m.username}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _actions(m),
              ),
          ],
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: HadiColors.aktivite),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      );
}
