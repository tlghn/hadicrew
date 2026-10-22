import 'package:flutter/material.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/data/chat_models.dart';
import 'package:hadi/data/chat_service.dart' show ChannelDraft;
import 'package:hadi/data/models.dart' show AppFailure;
import 'package:hadi/features/channels/channel_edit_sheet.dart' show kChannelDeleted, showChannelEditSheet;
import 'package:hadi/features/messages/bot_widgets.dart' show BotPicker, saveBotPlacement;
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/instant.dart' show InlineError, ListSkeleton;

/// Kanallar: kanal / grup kur, düzenle, bot yerleştir, duyuru kanallarına yaz. (Uygulamada yalnızca üye görünümü var.)
class ChannelsAdminScreen extends StatefulWidget {
  const ChannelsAdminScreen({super.key});

  @override
  State<ChannelsAdminScreen> createState() => _ChannelsAdminScreenState();
}

class _ChannelsAdminScreenState extends State<ChannelsAdminScreen> {
  Stream<List<Chat>>? _stream;

  static const _presets = [
    ChannelDraft(title: 'Duyurular', about: 'Kulübün resmi duyuruları', emoji: '📣', color: 0, kind: 'channel', posting: Posting.staff),
    ChannelDraft(title: 'Sohbet', about: 'Herkesin buluştuğu ana grup', emoji: '💬', color: 1),
    ChannelDraft(title: 'Etkinlik fikirleri', about: 'Yeni etkinlik önerileri ve oylamalar', emoji: '💡', color: 3),
    ChannelDraft(title: 'Doğa & spor', about: 'Yürüyüş, kamp, bisiklet', emoji: '🌲', color: 2),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= SessionScope.read(context).services.chat.watchChannels();
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _create([ChannelDraft? preset]) async {
    final id = await showChannelEditSheet(context, preset: preset);
    if (id != null && id != kChannelDeleted && mounted) _toast('Kanal hazır.');
  }

  Future<void> _edit(Chat c) async {
    final r = await showChannelEditSheet(context, chat: c);
    if (r == kChannelDeleted && mounted) _toast('Kanal silindi.');
  }

  Future<void> _bots(Chat c) async {
    List<String>? ids;
    final save = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (x) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${c.title} · botlar', style: Theme.of(x).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          BotPicker(env: c.botEnv, onChanged: (v) => ids = v),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(x, true), child: const Text('Kaydet'))),
        ]),
      ),
    );
    if (save != true || !mounted) return;
    final err = await saveBotPlacement(SessionScope.read(context), c.botEnv, ids);
    if (mounted) _toast(err ?? 'Botlar güncellendi.');
  }

  Future<void> _announce(Chat c) async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('${c.emoji} ${c.title}'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            maxLength: 4000,
            decoration: const InputDecoration(hintText: 'Duyuru metni', border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(d, ctrl.text.trim()), child: const Text('Gönder')),
        ],
      ),
    );
    ctrl.dispose();
    if (text == null || text.isEmpty || !mounted) return;
    final s = SessionScope.read(context);
    try {
      await s.services.chat.send(c.id, s.uid!, OutgoingMessage.text(text));
      if (mounted) _toast('Gönderildi.');
    } on AppFailure catch (e) {
      if (mounted) _toast(e.message);
    } catch (_) {
      if (mounted) _toast('Gönderilemedi. Bağlantını kontrol edip tekrar dene.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Kanallar')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add_rounded), label: const Text('Yeni kanal')),
      body: StreamBuilder<List<Chat>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) return InlineError(message: 'Kanallar yüklenemedi.', onRetry: () => setState(() => _stream = SessionScope.read(context).services.chat.watchChannels()));
          if (!snap.hasData) return const ListSkeleton();
          final all = [...snap.data!]..sort((a, b) => a.order.compareTo(b.order));
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
            Text('Hızlı başlangıç', style: text.labelLarge?.copyWith(color: HadiColors.ink3, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in _presets) ActionChip(avatar: Text(p.emoji), label: Text(p.title), onPressed: () => _create(p)),
            ]),
            const SizedBox(height: 20),
            if (all.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Center(child: Text('Henüz kanal yok.', style: text.titleSmall)))
            else
              for (final c in all)
                Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8),
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.surface, child: Text(c.emoji.isEmpty ? '#' : c.emoji)),
                    title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([
                      c.isAnnouncement ? 'Duyuru kanalı' : 'Grup',
                      '${c.memberCount} üye',
                      switch (c.posting) { Posting.all => 'herkes yazar', Posting.staff => 'yalnızca ekip yazar', Posting.off => 'yazışma kapalı' },
                    ].join(' · ')),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) => switch (v) {
                        'edit' => _edit(c),
                        'bots' => _bots(c),
                        'announce' => _announce(c),
                        _ => null,
                      },
                      itemBuilder: (_) => [
                        if (c.posting != Posting.off) const PopupMenuItem(value: 'announce', child: Text('Mesaj / duyuru gönder')),
                        const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                        const PopupMenuItem(value: 'bots', child: Text('Botlar')),
                      ],
                    ),
                    onTap: () => _edit(c),
                  ),
                ),
          ]);
        },
      ),
    );
  }
}
