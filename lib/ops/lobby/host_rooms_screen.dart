import 'package:flutter/material.dart';
import 'package:hadi/panel_ui/crew_ui.dart';
import 'package:go_router/go_router.dart';

import 'package:hadi/core/session.dart';
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/common.dart';
import 'package:hadi/widgets/instant.dart';

/// Yönetim: bekleyen adayların Bekleme Salonları. Salona ev sahibi olarak
/// girilir (`/salon/:room` → LobbyScreen(asHost: true)). Route: `/salonlar`.
class HostRoomsScreen extends StatefulWidget {
  const HostRoomsScreen({super.key});

  @override
  State<HostRoomsScreen> createState() => _HostRoomsScreenState();
}

class _HostRoomsScreenState extends State<HostRoomsScreen> {
  Future<List<Map<String, Object?>>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<List<Map<String, Object?>>> _load() => SessionScope.read(context).services.candidates.rooms();

  Future<void> _refresh() async {
    final f = _load();
    setState(() { _future = f; });
    try {
      await f;
    } catch (_) {
      // Hata FutureBuilder'da gösterilir.
    }
  }

  static String _s(Object? v) => v is String ? v : (v == null ? '' : '$v');
  static int _i(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? 0 : 0);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Bekleme salonları')),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _future,
        builder: (context, snap) {
          final children = <Widget>[
            const InfoNote(
              icon: Icons.forum_outlined,
              color: HadiColors.gold,
              text: 'Ev sahibi olarak salona katıldığında mesajların "Ev sahibi" rozetiyle görünür. Adayların sorularını cevaplayabilirsin. Bir adayın fotoğrafına ya da adına dokunursan "Aday özeti" açılır.',
            ),
            const SizedBox(height: 16),
          ];
          if (snap.hasError) {
            children.add(Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(children: [
                Text('Salonlar yüklenemedi. Yetkin olduğundan emin ol.', style: text.bodyMedium, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                TextButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded), label: const Text('Tekrar dene')),
              ]),
            ));
          } else if (!snap.hasData) {
            children.add(const ListSkeleton(count: 3));
          } else if (snap.data!.isEmpty) {
            children.add(const CrewCard(
              child: CrewEmpty(icon: Icons.meeting_room_outlined, title: 'Şu an bekleyen aday yok', message: 'Bir aday salona girince burada görünür.'),
            ));
          } else {
            for (final r in snap.data!) {
              final room = _s(r['room']);
              if (room.isEmpty) continue;
              final name = _s(r['name']).isEmpty ? room : _s(r['name']);
              final waiting = _i(r['waiting']);
              children.add(Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: HadiColors.goldSoft,
                      child: Icon(Icons.meeting_room_outlined, color: HadiColors.gold),
                    ),
                    title: Text('$name · $waiting aday bekliyor', style: text.titleMedium),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/salon/${Uri.encodeComponent(room)}'),
                  ),
                ),
              ));
            }
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: CrewListView(maxWidth: 820, children: children),
          );
        },
      ),
    );
  }
}
