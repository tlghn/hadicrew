// HADİ Crew / Kurucu Paneli — Mağaza ayarları (config/store; store › adminConfig).
// Kargo ücreti (TL ve Elmas), ücretsiz kargo eşiği, hediye alıcısının adres seçme süresi, kargo firmaları
// (ad + takip bağlantısı şablonu, {no} = takip numarası) ve mağazanın açık/kapalı durumu.
import 'package:flutter/material.dart';

import 'package:hadi/panel_ui/crew_ui.dart';

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
        _saved = _snapshot();
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
      setState(() {
        _apply(r);
        _saved = _snapshot();
      });
      storeToast(context, 'Mağaza ayarları kaydedildi.');
    } catch (e) {
      if (mounted) storeToast(context, storeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Alan değişti mi (Kaydet çubuğu): son yüklenen/kaydedilen değerle karşılaştırılır.
  String _snapshot() => [
        _enabled,
        for (final f in _fields) _c[f.$1]!.text.trim(),
        for (final c in _carriers) '${c.name.text.trim()}|${c.url.text.trim()}',
      ].join('\u0001');
  String _saved = '';
  bool get _dirty => _loaded && _error == null && _snapshot() != _saved;

  void _addCarrier() => setState(() => _carriers.add(_Carrier(const {})));
  void _touch() => setState(() {});

  List<Widget> _content() {
    if (!_loaded) return const [CrewCard(child: CrewLoading(rows: 3))];
    if (_error != null) {
      return [
        CrewCard(child: CrewError(message: _error!, onRetry: () => setState(() {
          _loaded = false;
          _load();
        }))),
      ];
    }
    final wide = crewWide(context);
    return [
      CrewCard(children: [
        CrewSwitchRow(
          title: 'Mağaza açık',
          subtitle: _enabled
              ? 'Üyeler ürünleri görüp sipariş verebilir.'
              : 'Yeni sipariş ve dijital satın alma alınmaz; mevcut siparişler işlenmeye devam eder.',
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
      ]),
      CrewCard(
        title: 'Kargo ve hediye',
        icon: Icons.local_shipping_outlined,
        children: [
          CrewFormGrid(children: [
            for (final f in _fields)
              TextField(
                controller: _c[f.$1],
                onChanged: (_) => _touch(),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: f.$2, suffixText: f.$3),
              ),
          ]),
          const CrewNote(
            'Ücretsiz kargo eşiği kartla ödenen sepet toplamına uygulanır. Hediye alıcısı bu süre içinde adres seçmezse sipariş iptal edilip gönderene iade edilir.',
          ),
        ],
      ),
      CrewCard(
        title: 'Kargo firmaları',
        subtitle: 'Takip bağlantısında numaranın geleceği yere {no} yaz. Örn. https://kargotakip.ornek.com/?no={no}',
        icon: Icons.inventory_2_outlined,
        action: wide
            ? OutlinedButton.icon(onPressed: _addCarrier, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Firma ekle'))
            : IconButton.filledTonal(tooltip: 'Firma ekle', onPressed: _addCarrier, icon: const Icon(Icons.add_rounded)),
        children: [
          if (_carriers.isEmpty)
            CrewEmpty(
              icon: Icons.local_shipping_outlined,
              title: 'Henüz kargo firması yok',
              message: 'Siparişi kargoya verirken seçilecek firmaları buraya ekle.',
              action: FilledButton.icon(onPressed: _addCarrier, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Firma ekle')),
            ),
          for (var i = 0; i < _carriers.length; i++)
            CrewItemCard(
              key: ObjectKey(_carriers[i]),
              title: _carriers[i].name.text.trim().isEmpty ? 'Yeni firma' : _carriers[i].name.text.trim(),
              removeTooltip: 'Firmayı kaldır',
              onRemove: () => setState(() => _carriers.removeAt(i).dispose()),
              // Ad kısa, şablon uzun: genişte yan yana (ad 200 px), dar ekranda alt alta.
              child: LayoutBuilder(builder: (context, c) {
                    final name = TextField(
                      controller: _carriers[i].name,
                      onChanged: (_) => _touch(),
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Firma adı'),
                    );
                    final url = TextField(
                      controller: _carriers[i].url,
                      onChanged: (_) => _touch(),
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(labelText: 'Takip bağlantısı şablonu', hintText: 'https://…{no}'),
                    );
                    if (c.maxWidth < 520) return Column(spacing: CrewSpace.fieldGap, children: [name, url]);
                    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 200, child: name),
                      const SizedBox(width: CrewSpace.md),
                      Expanded(child: url),
                    ]);
                  }),
            ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => CrewPage(
        title: 'Mağaza ayarları',
        subtitle: 'Kargo ücreti, kargo firmaları, hediye süresi',
        embedded: widget.embedded,
        maxWidth: CrewWidth.form,
        onRefresh: _load,
        bottomBar: _loaded && _error == null
            ? CrewSaveBar(dirty: _dirty, busy: _busy, onSave: _save, onReset: _dirty ? () => setState(() {
                _loaded = false;
                _load();
              }) : null)
            : null,
        children: _content(),
      );
}
