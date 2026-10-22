// HADİ Crew
// Kaynak: hadimobile/lib/features/feed/content_hide.dart (21 Ekim 2026'da HADİ Crew'e taşındı).
import 'package:flutter/material.dart';
import 'package:hadi/core/capabilities.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/data/models.dart';
import 'package:hadi/features/feed/content_hide.dart';
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/hadi_sheet.dart';
import 'package:hadi/widgets/instant.dart';

/// Gönderi "…" menüsüne eklenecek satır: "Gizle (tüm uygulamada)" / "Gizlemeyi kaldır".
/// Yetki yoksa boş liste döner. [sheet]: açık menünün context'i (kapatılır).
List<Widget> contentHideTiles(BuildContext context, BuildContext sheet, HideTarget t, {required bool hidden, VoidCallback? onChanged}) {
  final s = SessionScope.read(context);
  if (!canHideContent(s)) return const [];
  return [
    ListTile(
      leading: Icon(hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: hidden ? HadiColors.dostluk : HadiColors.error),
      title: Text(hidden ? 'Gizlemeyi kaldır' : 'Gizle (tüm uygulamada)', style: TextStyle(color: hidden ? null : HadiColors.error)),
      subtitle: Text(hidden ? 'Herkes yeniden görebilir.' : 'Yalnızca sahibi görür; sahibine gerekçesiyle bildirilir.'),
      onTap: () async {
        Navigator.pop(sheet);
        final ok = hidden ? await unhideContentFlow(context, t) : await hideContentFlow(context, t);
        if (ok) onChanged?.call();
      },
    ),
  ];
}

/// Gerekçe seç → onayla → gizle. Başarılıysa true.
Future<bool> hideContentFlow(BuildContext context, HideTarget t) async {
  final services = SessionScope.read(context).services;
  final messenger = ScaffoldMessenger.of(context);
  final custom = TextEditingController();
  final reason = await showHadiSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Text('Bu ${t.noun} tüm uygulamada gizlensin mi?', style: Theme.of(c).textTheme.titleLarge),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text('Akış, keşfet, profil, arama ve etiketlerden kalkar; yalnızca sahibi "Gizlendi" bandıyla görür. '
              'Sahibine seçtiğin gerekçe bildirilir ve itiraz edebilir.', style: TextStyle(color: HadiColors.ink3)),
        ),
        for (final r in kHideReasons) ListTile(dense: true, leading: const Icon(Icons.rule_rounded, size: 20), title: Text(r), onTap: () => Navigator.pop(c, r)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: custom,
                maxLength: 300,
                decoration: const InputDecoration(hintText: 'Başka bir gerekçe yaz…', counterText: ''),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                final v = custom.text.trim();
                if (v.length >= 3) Navigator.pop(c, v);
              },
              child: const Text('Gizle'),
            ),
          ]),
        ),
      ]),
    ),
  );
  custom.dispose();
  if (reason == null) return false;
  try {
    await ContentHide.hide(services, t, reason);
    messenger.showSnackBar(SnackBar(content: Text('${t.noun[0].toUpperCase()}${t.noun.substring(1)} tüm uygulamada gizlendi.')));
    return true;
  } on AppFailure catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
}

/// Onayla → gizlemeyi kaldır. Başarılıysa true.
Future<bool> unhideContentFlow(BuildContext context, HideTarget t) async {
  final services = SessionScope.read(context).services;
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Gizleme kaldırılsın mı?'),
      content: Text('Bu ${t.noun} yeniden herkese görünür olur; sahibine haber verilir.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kaldır')),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await ContentHide.unhide(services, t);
    messenger.showSnackBar(const SnackBar(content: Text('Gizleme kaldırıldı.')));
    return true;
  } on AppFailure catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
}

/// Kurucu paneli › Gizlenen gönderiler: liste, itirazlar ve "Gizlemeyi kaldır".
class HiddenContentScreen extends StatefulWidget {
  const HiddenContentScreen({super.key, this.embedded = false});

  /// true: başka bir sekmenin içinde (Scaffold'suz).
  final bool embedded;

  @override
  State<HiddenContentScreen> createState() => _HiddenContentScreenState();
}

class _HiddenContentScreenState extends State<HiddenContentScreen> {
  late Future<List<HiddenItem>> _f = _load();
  bool _appealsOnly = false;

  Future<List<HiddenItem>> _load() => ContentHide.list(SessionScope.read(context).services);

  void _reload() => setState(() { _f = _load(); });

  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
      onRefresh: () async => _reload(),
      child: FutureBuilder<List<HiddenItem>>(
        future: _f,
        builder: (context, snap) {
          if (snap.hasError) {
            return ListView(children: [
              Padding(padding: const EdgeInsets.all(24), child: Text(snap.error is AppFailure ? '${snap.error}' : 'Yüklenemedi. Aşağı çekip yenile.')),
            ]);
          }
          if (!snap.hasData) return const ListSkeleton();
          final all = snap.data!;
          final items = _appealsOnly ? all.where((x) => x.appeal != null).toList() : all;
          final appeals = all.where((x) => x.appeal != null).length;
          return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Wrap(spacing: 8, children: [
                ChoiceChip(label: Text('Tümü (${all.length})'), selected: !_appealsOnly, onSelected: (_) => setState(() => _appealsOnly = false)),
                ChoiceChip(label: Text('İtirazlar ($appeals)'), selected: _appealsOnly, onSelected: (_) => setState(() => _appealsOnly = true)),
              ]),
            ),
            if (items.isEmpty)
              Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Gizlenen içerik yok.', style: TextStyle(color: HadiColors.ink3)))),
            for (final x in items)
              Card(
                margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: x.thumb != null
                            ? Image.network(x.thumb!, fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: HadiColors.mist))
                            : ColoredBox(color: HadiColors.mist, child: Icon(Icons.notes_rounded, color: HadiColors.ink3)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${x.label} · ${x.ownerName}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        if (x.preview.isNotEmpty) Text(x.preview, maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text('Gerekçe: ${x.reason}', style: TextStyle(color: HadiColors.ink2, fontSize: 12)),
                        Text('Gizleyen: ${x.byName}${x.at != null ? ' · ${_date(x.at!)}' : ''}', style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
                        if (x.appeal != null)
                          Container(
                            margin: const EdgeInsets.only(top: 6),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: HadiColors.heyecanSoft, borderRadius: BorderRadius.circular(8)),
                            child: Text('İtiraz: ${x.appeal}', style: const TextStyle(fontSize: 12)),
                          ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            icon: const Icon(Icons.visibility_rounded, size: 18),
                            label: const Text('Gizlemeyi kaldır'),
                            onPressed: () async {
                              if (await unhideContentFlow(context, x.target)) _reload();
                            },
                          ),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Gizlenen gönderiler'), actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh_rounded))]),
      body: body,
    );
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Gönderi gizleme yetkisi: kurucular ve `content.hide` yetenekli roller.
bool canHideContent(Session s) => s.isFounder || s.can(Cap.contentHide);
