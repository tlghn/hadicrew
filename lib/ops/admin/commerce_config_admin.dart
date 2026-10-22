// HADİ — Kurucu paneli › İşletmeler › Anlaşmazlıklar: kargo ve gel-al süreleri (config/commerce; K1 · commerce_pricing.ts).
// Okuma yetkililere açık; değiştirme yalnızca ana kurucu. Kargo firması takip bağlantısı şablonları ({no}) buradan düzeltilir
// (firma sayfa adresini değiştirirse koda dokunmadan). API anahtarı GİRİLMEZ.
import 'package:flutter/material.dart';

import 'package:hadi/data/commerce_service.dart';
import 'package:hadi/theme/hadi_colors.dart';

class CommerceConfigCard extends StatefulWidget {
  const CommerceConfigCard({super.key});

  @override
  State<CommerceConfigCard> createState() => _CommerceConfigCardState();
}

class _CommerceConfigCardState extends State<CommerceConfigCard> {
  static const _fields = <(String, String, String)>[
    ('cargoConfirmDays', 'Kargo teslim onay süresi', 'gün'),
    ('cargoShipDays', 'Kargoya verme süresi (sonra "geldi mi?")', 'gün'),
    ('cargoAskDays', 'Kargoda kalma süresi (sonra üyeye sorulur)', 'gün'),
    ('cargoAnswerDays', 'Üyenin yanıt süresi (sonra yönetime)', 'gün'),
    ('pickupGraceMinutes', 'Gel-al toleransı', 'dk'),
  ];
  final Map<String, TextEditingController> _c = {for (final f in _fields) f.$1: TextEditingController()};
  final Map<String, TextEditingController> _urls = {for (final k in kCarriers) k.$1: TextEditingController()};
  bool _canEdit = false, _loaded = false, _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final x in [..._c.values, ..._urls.values]) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await CommerceService.instance.configGet();
      if (!mounted) return;
      setState(() {
        for (final f in _fields) {
          _c[f.$1]!.text = '${r[f.$1] ?? ''}';
        }
        final u = (r['carrierUrls'] as Map?) ?? const {};
        for (final k in _urls.keys) {
          _urls[k]!.text = '${u[k] ?? ''}';
        }
        _canEdit = r['canEdit'] == true;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await CommerceService.instance.configSet({
        for (final f in _fields)
          if (int.tryParse(_c[f.$1]!.text.trim()) != null) f.$1: int.parse(_c[f.$1]!.text.trim()),
        'carrierUrls': {for (final e in _urls.entries) e.key: e.value.text.trim()},
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kaydedildi.')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(commerceError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: HadiColors.mist, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Kargo ve gel-al süreleri', style: TextStyle(fontWeight: FontWeight.w900)),
        Text('Kargo: "Teslim edildi"den sonra üye yanıt vermezse onay süresi sonunda bloke işletmeye geçer. Gel-al: işletmenin süresine tolerans eklenir, sonra "teslim alınmadı".',
            style: TextStyle(color: HadiColors.ink2, fontSize: 12.5)),
        const SizedBox(height: 6),
        for (final f in _fields)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Expanded(child: Text(f.$2, style: const TextStyle(fontSize: 13))),
              SizedBox(
                width: 96,
                child: TextField(controller: _c[f.$1], enabled: _canEdit, keyboardType: TextInputType.number, decoration: InputDecoration(suffixText: f.$3, isDense: true)),
              ),
            ]),
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Kargo takip bağlantıları', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
          subtitle: Text('Boş = varsayılan. https:// ile başlamalı ve {no} içermeli.', style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
          children: [
            for (final k in kCarriers)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: TextField(controller: _urls[k.$1], enabled: _canEdit, keyboardType: TextInputType.url, decoration: InputDecoration(labelText: k.$2, isDense: true)),
              ),
          ],
        ),
        if (_canEdit) Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: _busy ? null : _save, child: const Text('Kaydet'))),
      ]),
    );
  }
}
