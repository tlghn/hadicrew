// HADİ Crew / Kurucu Paneli — Mağaza ayarları (config/store; store › adminConfig).
// Kargo ücreti (TL ve Elmas), ücretsiz kargo eşiği, hediye alıcısının adres seçme süresi, kargo firmaları
// (ad + takip bağlantısı şablonu, {no} = takip numarası) ve mağazanın açık/kapalı durumu.
import 'package:flutter/material.dart';

import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/skeleton.dart';

import 'store_admin_common.dart';
import 'store_preview_bridge.dart' show storeAdminConfig;

class StoreSettingsAdminTab extends StatefulWidget {
  const StoreSettingsAdminTab({super.key, this.embedded = true});
  final bool embedded;

  @override
  State<StoreSettingsAdminTab> createState() => _StoreSettingsAdminTabState();
}

class _Carrier {
  _Carrier(Map<String, dynamic> m)
      : id = '${m['id'] ?? ''}',
        name = TextEditingController(text: '${m['name'] ?? ''}'),
        url = TextEditingController(text: '${m['urlTemplate'] ?? ''}');
  String id;
  final TextEditingController name, url;

  void dispose() {
    name.dispose();
    url.dispose();
  }
}

class _StoreSettingsAdminTabState extends State<StoreSettingsAdminTab> {
  static const _fields = <(String, String, String)>[
    ('shippingTl', 'Kargo ücreti (kartla ödemede)', '₺'),
    ('shippingElmas', 'Kargo ücreti (Elmasla ödemede)', '💎'),
    ('freeShippingOverTl', 'Ücretsiz kargo eşiği (0 = yok)', '₺'),
    ('giftAddressDays', 'Hediye alıcısının adres seçme süresi', 'gün'),
  ];
  final Map<String, TextEditingController> _c = {for (final f in _fields) f.$1: TextEditingController()};
  final List<_Carrier> _carriers = [];
  bool _enabled = true, _loaded = false, _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    for (final c in _carriers) {
      c.dispose();
    }
    super.dispose();
  }

  void _apply(Map<String, dynamic> cfg) {
    for (final f in _fields) {
      final v = cfg[f.$1];
      _c[f.$1]!.text = v is num ? (v == v.roundToDouble() ? '${v.toInt()}' : '$v') : '';
    }
    for (final c in _carriers) {
      c.dispose();
    }
    _carriers
      ..clear()
      ..addAll([for (final m in storeList(cfg['carriers'])) _Carrier(m)]);
    _enabled = cfg['enabled'] != false;
  }

  Future<void> _load() async {
    try {
      final r = await storeAdminConfig(context);
      if (!mounted) return;
      setState(() {
        _apply(r);
        _loaded = true;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loaded = true;
          _error = storeError(e);
        });
      }
    }
  }

  String _slug(String s) {
    const tr = {'ç': 'c', 'ğ': 'g', 'ı': 'i', 'i̇': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u'};
    var x = s.toLowerCase();
    tr.forEach((k, v) => x = x.replaceAll(k, v));
    return x.replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  }

  Future<void> _save() async {
    final carriers = <Map<String, Object?>>[];
    final seen = <String>{};
    for (final c in _carriers) {
      final name = c.name.text.trim(), url = c.url.text.trim();
      if (name.isEmpty && url.isEmpty) continue;
      if (name.isEmpty) return storeToast(context, 'Kargo firmasının adını yaz.');
      if (url.isNotEmpty && (!url.startsWith('https://') || !url.contains('{no}'))) {
        return storeToast(context, '$name: takip bağlantısı https:// ile başlamalı ve {no} içermeli.');
      }
      var id = c.id.isNotEmpty ? c.id : _slug(name);
      if (id.isEmpty) id = 'kargo${carriers.length + 1}';
      while (seen.contains(id)) {
        id = '${id}_2';
      }
      seen.add(id);
      carriers.add({'id': id, 'name': name, 'urlTemplate': url});
    }
    final set = <String, Object?>{'enabled': _enabled, 'carriers': carriers};
    for (final f in _fields) {
      final t = _c[f.$1]!.text.trim().replaceAll(',', '.');
      if (t.isEmpty) continue;
      final n = num.tryParse(t);
      if (n == null || n < 0) return storeToast(context, '${f.$2}: geçerli bir sayı yaz.');
      set[f.$1] = n;
    }
    setState(() => _busy = true);
    try {
      final r = await storeAdminConfig(context, set: set);
      if (!mounted) return;
      setState(() => _apply(r));
      storeToast(context, 'Mağaza ayarları kaydedildi.');
    } catch (e) {
      if (mounted) storeToast(context, storeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _body() {
    if (!_loaded) return const Padding(padding: EdgeInsets.all(16), child: Column(children: [ListTileSkeleton(), ListTileSkeleton()]));
    if (_error != null) {
      return ListView(padding: const EdgeInsets.all(24), children: [
        Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: HadiColors.ink2)),
        const SizedBox(height: 12),
        Center(child: OutlinedButton(onPressed: () => setState(() {
          _loaded = false;
          _load();
        }), child: const Text('Tekrar dene'))),
      ]);
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            StoreCard(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
                title: const Text('Mağaza açık', style: TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text(
                  _enabled
                      ? 'Üyeler ürünleri görüp sipariş verebilir.'
                      : 'Yeni sipariş ve dijital satın alma alınmaz; mevcut siparişler işlenmeye devam eder.',
                  style: TextStyle(color: HadiColors.ink2, fontSize: 12.5),
                ),
              ),
            ),
            const StoreSectionTitle('Kargo ve hediye'),
            StoreCard(
              child: Column(children: [
                for (final f in _fields)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Expanded(child: Text(f.$2, style: const TextStyle(fontSize: 13.5))),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _c[f.$1],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(suffixText: f.$3, isDense: true),
                        ),
                      ),
                    ]),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Ücretsiz kargo eşiği kartla ödenen sepet toplamına uygulanır. Hediye alıcısı bu süre içinde adres seçmezse sipariş iptal edilip gönderene iade edilir.',
                    style: TextStyle(color: HadiColors.ink3, fontSize: 12),
                  ),
                ),
              ]),
            ),
            StoreSectionTitle('Kargo firmaları',
                trailing: TextButton.icon(
                  onPressed: () => setState(() => _carriers.add(_Carrier(const {}))),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Firma ekle'),
                )),
            StoreCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Takip bağlantısında takip numarasının geleceği yere {no} yaz. Örn. https://kargotakip.ornek.com/?no={no}',
                    style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
                if (_carriers.isEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text('Henüz kargo firması yok.', style: TextStyle(color: HadiColors.ink2))),
                for (var i = 0; i < _carriers.length; i++)
                  Padding(
                    key: ObjectKey(_carriers[i]),
                    padding: const EdgeInsets.only(top: 10),
                    child: LayoutBuilder(builder: (context, cons) {
                      final c = _carriers[i];
                      final name = TextField(controller: c.name, decoration: const InputDecoration(labelText: 'Firma adı', isDense: true));
                      final url = TextField(
                        controller: c.url,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(labelText: 'Takip bağlantısı şablonu', hintText: 'https://…{no}', isDense: true),
                      );
                      final del = IconButton(
                        tooltip: 'Kaldır',
                        onPressed: () => setState(() => _carriers.removeAt(i).dispose()),
                        icon: Icon(Icons.delete_outline_rounded, color: HadiColors.error),
                      );
                      if (cons.maxWidth < 520) {
                        return Column(children: [Row(children: [Expanded(child: name), del]), url]);
                      }
                      return Row(children: [SizedBox(width: 180, child: name), const SizedBox(width: 10), Expanded(child: url), del]);
                    }),
                  ),
              ]),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded),
                label: const Text('Kaydet'),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(onRefresh: _load, child: _body());
    return widget.embedded
        ? body
        : Scaffold(appBar: AppBar(title: const Text('Mağaza ayarları', maxLines: 1, overflow: TextOverflow.ellipsis)), body: body);
  }
}
