// HADİ — Kurucu paneli › Bildirim stüdyosu ayarları (24 Ekim 2026; yalnızca kurucu). Sunucu: notify_studio.ts › configGet /
// configSet / rebuild (config/notify_studio). Onay eşiği, sıklık sınırları, sessiz saatler, rıza (marketingDefaultOn — avukat
// "anlık bildirimde önceden rıza gerekmez" derse), rıza metni sürümü, teşekkür Akçe'si, kitle verisini şimdi yenile.
import 'package:flutter/material.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/data/ops_api.dart';
import 'package:hadi/panel_ui/crew_ui.dart';
import 'package:hadi/theme/hadi_colors.dart';

import 'ns_api.dart';

class NotifyStudioSettingsTab extends StatefulWidget {
  const NotifyStudioSettingsTab({super.key, this.embedded = true});
  final bool embedded;

  @override
  State<NotifyStudioSettingsTab> createState() => _NotifyStudioSettingsTabState();
}

class _NotifyStudioSettingsTabState extends State<NotifyStudioSettingsTab> {
  Map<String, dynamic>? _orig, _c;
  Map<String, dynamic> _aud = {};
  String? _err;
  bool _busy = false;
  int _formRev = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final r = await NsApi.configGet(SessionScope.read(context).services);
      if (!mounted) return;
      setState(() {
        _orig = OpsApi.map(r['config']);
        _c = {..._orig!};
        _aud = OpsApi.map(r['audience']);
        _err = null;
        _formRev++;
      });
    } catch (e) {
      if (mounted) setState(() => _err = '$e'.replaceFirst('AppFailure: ', ''));
    }
  }

  bool get _dirty => _c != null && _orig != null && _c!.entries.any((e) => '${_orig![e.key]}' != '${e.value}');

  Future<void> _save() async {
    if (_c!['marketingDefaultOn'] == true && _orig!['marketingDefaultOn'] != true) {
      final ok = await crewConfirm(
        context,
        title: 'Varsayılan izni açmak istediğine emin misin?',
        message: 'Hiç seçim yapmamış üyeler pazarlama bildirimine açık sayılır. Bunu yalnızca hukuk danışmanı "uygulama içi anlık bildirimde önceden açık rıza gerekmez" dediyse aç. '
            '"Hayır" diyen ya da izni geri alan üyeler her durumda hariç kalır; 18 yaş altına asla gitmez.',
        confirm: 'Aç',
        danger: true,
      );
      if (!ok) return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final r = await NsApi.configSet(SessionScope.read(context).services, _c!);
      if (!mounted) return;
      setState(() => (_orig = OpsApi.map(r['config']), _c = {...OpsApi.map(r['config'])}));
      crewToast(context, 'Bildirim stüdyosu ayarları kaydedildi.');
    } catch (e) {
      if (mounted) crewToast(context, '$e'.replaceFirst('AppFailure: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rebuild() async {
    setState(() => _busy = true);
    try {
      final r = await NsApi.rebuild(SessionScope.read(context).services);
      if (mounted) crewToast(context, 'Kitle verisi yenilendi: ${r['total']} üye.');
      await _load();
    } catch (e) {
      if (mounted) crewToast(context, '$e'.replaceFirst('AppFailure: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _num(String k, String label, {String? suffix, String? helper}) => TextFormField(
        key: ValueKey('$k$_formRev'),
        initialValue: '${_c![k] ?? ''}',
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, suffixText: suffix, helperText: helper),
        onChanged: (x) => setState(() => _c![k] = int.tryParse(x.trim()) ?? _orig![k]),
      );

  @override
  Widget build(BuildContext context) {
    const title = 'Bildirim stüdyosu ayarları';
    const sub = 'Onay, sıklık, sessiz saat, rıza ve kitle verisi';
    if (_err != null) return CrewPage(title: title, subtitle: sub, embedded: widget.embedded, body: CrewError(message: _err!, onRetry: _load));
    if (_c == null) return CrewPage(title: title, subtitle: sub, embedded: widget.embedded, body: const CrewLoading());
    final built = OpsApi.time(_aud['builtAt']);
    return CrewPage(
      title: title,
      subtitle: sub,
      embedded: widget.embedded,
      maxWidth: CrewWidth.form,
      onRefresh: _load,
      bottomBar: CrewSaveBar(dirty: _dirty, busy: _busy, onSave: _save, onReset: _load),
      children: [
        CrewCard(title: 'Onay (dört göz)', icon: Icons.verified_user_outlined, children: [
          CrewFormGrid(children: [
            _num('approvalThreshold', 'Bu kişi sayısının üstü onaya gider', suffix: 'kişi', helper: 'Kurucu doğrudan gönderir'),
            _num('smallAudience', 'Küçük kitle uyarısı', suffix: 'kişi', helper: 'Süzgeçle bundan az kişi seçilirse'),
          ]),
        ]),
        CrewCard(title: 'Sıklık ve sessiz saat', icon: Icons.bedtime_outlined, children: [
          CrewFormGrid(children: [
            _num('marketingPerDay', 'Pazarlama: üye başına günde en çok', suffix: 'bildirim'),
            _num('otherPerDay', 'Duyuru + etkinlik: günde en çok', suffix: 'bildirim', helper: '0 = sınır yok; hizmet her zaman sınırsız'),
          ]),
          CrewSwitchRow(
            title: 'Genel sessiz saat',
            subtitle: 'Hizmet dışındaki bildirimler bu aralıkta gönderilmez, sabaha kayar (İstanbul saati).',
            value: _c!['quietOn'] != false,
            onChanged: (x) => setState(() => _c!['quietOn'] = x),
          ),
          if (_c!['quietOn'] != false)
            CrewFormGrid(children: [
              _num('quietStart', 'Başlangıç', suffix: ':00'),
              _num('quietEnd', 'Bitiş', suffix: ':00'),
            ]),
          CrewFormGrid(children: [
            _num('perMinute', 'Gönderim hızı', suffix: '/dk'),
            _num('staleHours', 'Ertelenen bildirim en çok', suffix: 'saat', helper: 'Daha eskiyse gönderilmez'),
            _num('conversionHours', 'Dönüşüm penceresi', suffix: 'saat', helper: 'Açtıktan sonra katılım / satın alma'),
          ]),
        ]),
        CrewCard(title: 'Kampanya izni (rıza)', icon: Icons.handshake_outlined, children: [
          CrewSwitchRow(
            title: 'Seçim yapmamış üyeyi izinli say (marketingDefaultOn)',
            subtitle: 'Varsayılan KAPALI. Yalnızca hukuk görüşüyle aç. Açıkça "hayır" diyen ve izni geri alan her zaman hariç; 18 yaş altı ve yaşı bilinmeyen asla.',
            value: _c!['marketingDefaultOn'] == true,
            onChanged: (x) => setState(() => _c!['marketingDefaultOn'] = x),
          ),
          CrewFormGrid(children: [
            TextFormField(
              key: ValueKey('cv$_formRev'),
              initialValue: '${_c!['consentVersion'] ?? ''}',
              decoration: const InputDecoration(labelText: 'Rıza metni sürümü', helperText: 'Her verme/geri almaya yazılır'),
              onChanged: (x) => setState(() => _c!['consentVersion'] = x.trim()),
            ),
            _num('reaskDays', '"Şimdi değil" diyene yeniden sor', suffix: 'gün sonra'),
            _num('consentBonusAkce', 'İzin verene bir kerelik hediye', suffix: '🪙 Akçe', helper: '0 = yok. Vermeyen hiçbir şeyden mahrum kalmaz'),
          ]),
          const CrewNote('Teşekkür hediyesi Hareketler\'de "Fırsat bildirimleri hediyesi" olarak görünür; izin geri alınınca da üyede kalır. '
              'Kurucu paneli › Hizmetler › "Bildirim stüdyosu · rıza teşekkür Akçe\'si" ile tamamen kapatılabilir.'),
        ]),
        CrewCard(
          title: 'Kitle verisi',
          icon: Icons.groups_2_outlined,
          subtitle: 'Süzgeçlerin kullandığı yalın üye özeti; her gece 03:40\'ta yenilenir.',
          action: TextButton.icon(onPressed: _busy ? null : _rebuild, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Şimdi yenile')),
          children: [
            CrewInfoRow('Üye sayısı', '${_aud['total'] ?? '-'}'),
            CrewInfoRow('Son güncelleme', built == null ? 'henüz kurulmadı' : '${OpsApi.dur(DateTime.now().difference(built))} önce'),
            const CrewNote('Özel nitelikli veri (sağlık, din, siyaset, cinsel yönelim…) bu özete hiç girmez; hassas topluluk ve etkinlik türleri ayıklanır.', icon: Icons.shield_outlined, color: HadiColors.dostluk),
          ],
        ),
      ],
    );
  }
}
