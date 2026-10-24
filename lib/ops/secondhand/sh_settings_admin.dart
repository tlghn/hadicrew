// HADİ — 2. El ayarları (Kurucu Paneli › 2. El ayarları; Crew'de yalnızca kurucular kaydeder). config/secondhand
// (sunucu: secondhand_core.ts › normalizeShConfig; sınırlar sunucuda uygulanır). Ücretler kategori bazında geçersiz kılınabilir.
// Hizmeti açmak/kapatmak: Kurucu Paneli › Hizmetler › "HADİ 2. El" (ilk durumu KAPALI) ve alt anahtarları.
import 'package:flutter/material.dart';
import 'package:hadi/panel_ui/crew_ui.dart';

import 'sh_admin_common.dart';

class ShSettingsAdminTab extends StatefulWidget {
  const ShSettingsAdminTab({super.key, this.embedded = true});
  final bool embedded;
  @override
  State<ShSettingsAdminTab> createState() => _ShSettingsAdminTabState();
}

class _NumField {
  _NumField(this.path, this.label, this.suffix, {this.kurus = false});
  final List<String> path;
  final String label, suffix;
  final bool kurus;
  final c = TextEditingController();
}

class _CatFee {
  _CatFee(this.cat, Map<String, dynamic> m)
      : pct = TextEditingController(text: m['commissionPct']?.toString() ?? ''),
        min = TextEditingController(text: m['commissionMinK'] is num ? ((m['commissionMinK'] as num) / 100).toString() : ''),
        buyerPct = TextEditingController(text: m['buyerPct']?.toString() ?? '');
  String cat;
  final TextEditingController pct, min, buyerPct;
}

class _Carrier {
  _Carrier(Map<String, dynamic> m)
      : id = TextEditingController(text: '${m['id'] ?? ''}'),
        name = TextEditingController(text: '${m['name'] ?? ''}'),
        url = TextEditingController(text: '${m['trackUrl'] ?? ''}');
  final TextEditingController id, name, url;
}

class _ShSettingsAdminTabState extends State<ShSettingsAdminTab> {
  Map<String, dynamic>? _cfg;
  bool _canEdit = false, _busy = false, _dirty = false;
  String? _err;
  final List<_CatFee> _catFees = [];
  final List<_Carrier> _carriers = [];
  final Set<String> _closed = {};

  late final List<(String, List<_NumField>)> _groups = [
    ('Ücretler (genel)', [
      _NumField(['fees', 'commissionPct'], 'Satıcı komisyonu', '%'),
      _NumField(['fees', 'commissionMinK'], 'En az komisyon', '₺', kurus: true),
      _NumField(['fees', 'buyerFixedK'], 'Alıcı koruma ücreti (sabit)', '₺', kurus: true),
      _NumField(['fees', 'buyerPct'], 'Alıcı koruma ücreti (yüzde)', '%'),
      _NumField(['fees', 'buyerMaxK'], 'Alıcı koruma ücreti tavanı', '₺', kurus: true),
      _NumField(['minPriceK'], 'En düşük ilan fiyatı', '₺', kurus: true),
      _NumField(['maxPriceK'], 'En yüksek ilan fiyatı', '₺', kurus: true),
      _NumField(['bundleMaxPct'], 'Paket indirimi üst sınırı', '%'),
    ]),
    ('Anlaşmalı kargo (alıcı fiyatı / HADİ maliyeti)', [
      for (final s in const ['S', 'M', 'L', 'XL']) ...[
        _NumField(['shipping', s, 'priceK'], '$s · alıcıdan', '₺', kurus: true),
        _NumField(['shipping', s, 'costK'], '$s · maliyet', '₺', kurus: true),
      ],
    ]),
    ('Öne çıkarma ve Pro (Elmas)', [
      _NumField(['boosts', 'bumpElmas'], '24 saat öne çıkar', '💎'),
      _NumField(['boosts', 'bumpHours'], 'Öne çıkarma süresi', 'saat'),
      _NumField(['boosts', 'showcaseElmas'], 'Vitrin', '💎'),
      _NumField(['boosts', 'showcaseDays'], 'Vitrin süresi', 'gün'),
      _NumField(['boosts', 'dropBadgeElmas'], '"Fiyat düştü" rozeti', '💎'),
      _NumField(['boosts', 'dropBadgeDays'], 'Rozet süresi', 'gün'),
      _NumField(['pro', 'monthlyElmas'], 'HADİ Pro Satıcı (30 gün)', '💎'),
      _NumField(['pro', 'listingLimit'], 'Pro ilan sınırı', 'ilan'),
      _NumField(['pro', 'bulkMax'], 'Toplu ilan (tek seferde)', 'ilan'),
    ]),
    ('Süreler', [
      _NumField(['inspectHours'], 'Alıcının inceleme süresi', 'saat'),
      _NumField(['shipDays'], 'Kargolama süresi', 'gün'),
      _NumField(['meetupDays'], 'Elden teslim süresi', 'gün'),
      _NumField(['offerHours'], 'Teklif yanıt süresi', 'saat'),
      _NumField(['reserveHours'], 'Kabul edilen teklifle satın alma süresi', 'saat'),
      _NumField(['disputeReplyHours'], 'Satıcının uyuşmazlık yanıt süresi', 'saat'),
      _NumField(['listingDays'], 'İlan yayın süresi', 'gün'),
      _NumField(['wantedDays'], '"Aranıyor" süresi', 'gün'),
      _NumField(['wantedMax'], 'Kişi başına açık "Aranıyor"', 'ilan'),
    ]),
    ('Güven ve güvenlik', [
      for (var i = 0; i < 4; i++) ...[
        _NumField(['levels', '$i', 'maxActive'], 'Seviye $i · yayındaki ilan', 'ilan'),
        _NumField(['levels', '$i', 'maxPriceK'], 'Seviye $i · ilan başına üst fiyat', '₺', kurus: true),
        _NumField(['levels', '$i', 'maxOpenSales'], 'Seviye $i · açık satış', 'sipariş'),
      ],
      _NumField(['fraudThreshold'], 'Dolandırıcılık kuyruğu eşiği', '/100'),
      _NumField(['proSellerSales365'], 'Profesyonel satıcı · yıllık satış', 'satış'),
      _NumField(['proSellerNewListings30'], 'Profesyonel satıcı · 30 günde etiketli yeni ilan', 'ilan'),
    ]),
    ('KVKK saklama', [
      _NumField(['addressMaskDays'], 'Teslim adresi maskeleme', 'gün'),
      _NumField(['disputeRetentionDays'], 'Uyuşmazlık kanıtlarının saklanması', 'gün'),
    ]),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Object? _get(Map<String, dynamic> m, List<String> path) {
    Object? cur = m;
    for (final p in path) {
      if (cur is Map) {
        cur = cur[p];
      } else if (cur is List) {
        cur = int.tryParse(p) != null && int.parse(p) < cur.length ? cur[int.parse(p)] : null;
      } else {
        return null;
      }
    }
    return cur;
  }

  void _set(Map<String, dynamic> m, List<String> path, Object v) {
    Object cur = m;
    for (var i = 0; i < path.length - 1; i++) {
      final p = path[i];
      if (cur is Map) {
        cur = cur.putIfAbsent(p, () => <String, dynamic>{}) as Object;
      } else if (cur is List) {
        cur = cur[int.parse(p)] as Object;
      }
    }
    if (cur is Map) cur[path.last] = v;
  }

  Future<void> _load() async {
    final svc = shAdminOf(context);
    await svc.categories().catchError((Object _) => const <ShCategory>[]);
    if (!mounted) return;
    final r = await shAdminCall(context, 'adminConfig');
    if (!mounted) return;
    if (r == null) return setState(() => _err = 'Ayarlar okunamadı.');
    final cfg = (r['config'] as Map).cast<String, dynamic>();
    setState(() {
      _cfg = cfg;
      _canEdit = r['canEdit'] == true;
      _err = null;
      for (final g in _groups) {
        for (final f in g.$2) {
          final v = _get(cfg, f.path);
          f.c.text = v is num ? (f.kurus ? (v / 100).toString().replaceAll(RegExp(r'\.0$'), '') : v.toString()) : '';
        }
      }
      _catFees
        ..clear()
        ..addAll([for (final e in ((cfg['categoryFees'] as Map?) ?? const {}).entries) _CatFee('${e.key}', (e.value as Map).cast<String, dynamic>())]);
      _carriers
        ..clear()
        ..addAll([for (final c in (cfg['carriers'] as List? ?? const [])) _Carrier((c as Map).cast<String, dynamic>())]);
      _closed
        ..clear()
        ..addAll([for (final c in (cfg['closedCategories'] as List? ?? const [])) '$c']);
      _dirty = false;
    });
  }

  Future<void> _save() async {
    final reason = await askReason(context, title: '2. El ayarlarını kaydet', message: 'Ücret ve süre değişiklikleri yalnızca yeni ilan ve siparişlere uygulanır.');
    if (reason == null || !mounted) return;
    final next = (jsonClone(_cfg!) as Map).cast<String, dynamic>();
    for (final g in _groups) {
      for (final f in g.$2) {
        final n = num.tryParse(f.c.text.replaceAll(',', '.').trim());
        if (n != null) _set(next, f.path, f.kurus ? (n * 100).round() : n);
      }
    }
    next['categoryFees'] = {
      for (final c in _catFees)
        if (c.cat.isNotEmpty)
          c.cat: {
            if (num.tryParse(c.pct.text.replaceAll(',', '.')) != null) 'commissionPct': num.parse(c.pct.text.replaceAll(',', '.')),
            if (num.tryParse(c.min.text.replaceAll(',', '.')) != null) 'commissionMinK': (num.parse(c.min.text.replaceAll(',', '.')) * 100).round(),
            if (num.tryParse(c.buyerPct.text.replaceAll(',', '.')) != null) 'buyerPct': num.parse(c.buyerPct.text.replaceAll(',', '.')),
          },
    };
    next['carriers'] = [for (final c in _carriers) if (c.id.text.trim().isNotEmpty) {'id': c.id.text.trim(), 'name': c.name.text.trim(), 'trackUrl': c.url.text.trim()}];
    next['closedCategories'] = _closed.toList();
    setState(() => _busy = true);
    final r = await shAdminCall(context, 'adminConfigSave', {'config': next, 'reason': reason}, 'Kaydedildi.');
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    final cats = shAdminOf(context).categoriesCache;
    final cfg = _cfg;
    return CrewPage(
      title: '2. El ayarları',
      subtitle: 'Ücretler (kategori bazında), kargo, öne çıkarma, Pro, süreler, güven sınırları',
      maxWidth: CrewWidth.form,
      embedded: widget.embedded,
      onRefresh: _load,
      bottomBar: _canEdit ? CrewSaveBar(dirty: _dirty, busy: _busy, onSave: _save, onReset: _load) : null,
      children: [
        if (cfg == null && _err == null) const CrewLoading(),
        if (_err != null) CrewError(message: _err!, onRetry: _load),
        if (cfg != null) ...[
          CrewCard(children: [
            CrewNote(_canEdit
                ? 'Hizmeti açıp kapatmak için Kurucu Paneli › Hizmetler › "HADİ 2. El" (ilk durumu kapalı) ve alt anahtarlarını (kargo, elden, takas, bağış, öne çıkarma, Pro, grup pazarları, Aranıyor) kullan.'
                : 'Ayarları yalnızca kurucular değiştirebilir; burada görüntülüyorsun.'),
          ]),
          for (final g in _groups)
            CrewCard(
              title: g.$1,
              children: [
                CrewFormGrid(children: [
                  for (final f in g.$2)
                    TextField(
                      controller: f.c,
                      enabled: _canEdit,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _dirty ? null : setState(() => _dirty = true),
                      decoration: InputDecoration(labelText: f.label, suffixText: f.suffix),
                    ),
                ]),
              ],
            ),
          CrewCard(
            title: 'Kategori ücretleri',
            subtitle: 'Boş bırakılan alan genel ücreti kullanır. Yaprak kategori üst kategoriyi geçersiz kılar.',
            action: _canEdit ? TextButton.icon(onPressed: () => setState(() {
                      _catFees.add(_CatFee('', const {}));
                      _dirty = true;
                    }), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Kategori ekle')) : null,
            children: [
              if (_catFees.isEmpty) const CrewNote('Kategoriye özel ücret yok. "Kategori ekle" ile başla.'),
              for (final c in _catFees)
                CrewItemCard(
                  title: cats.expand((r) => [r, ...r.children]).where((x) => x.id == c.cat).firstOrNull?.label ?? (c.cat.isEmpty ? 'Yeni kategori' : c.cat),
                  onRemove: _canEdit ? () => setState(() => (_catFees.remove(c), _dirty = true)) : null,
                  child: CrewFormGrid(children: [
                    DropdownButtonFormField<String>(
                      initialValue: c.cat.isEmpty ? null : c.cat,
                      items: [
                        for (final r in cats) ...[
                          DropdownMenuItem(value: r.id, child: Text('${r.emoji} ${r.label}')),
                          for (final x in r.children) DropdownMenuItem(value: x.id, child: Text('    ${x.label}')),
                        ],
                      ],
                      onChanged: _canEdit ? (v) => setState(() => (c.cat = v ?? '', _dirty = true)) : null,
                      decoration: const InputDecoration(labelText: 'Kategori'),
                    ),
                    TextField(controller: c.pct, enabled: _canEdit, onChanged: (_) => setState(() => _dirty = true), decoration: const InputDecoration(labelText: 'Komisyon', suffixText: '%')),
                    TextField(controller: c.min, enabled: _canEdit, onChanged: (_) => setState(() => _dirty = true), decoration: const InputDecoration(labelText: 'En az komisyon', suffixText: '₺')),
                    TextField(controller: c.buyerPct, enabled: _canEdit, onChanged: (_) => setState(() => _dirty = true), decoration: const InputDecoration(labelText: 'Alıcı koruma (yüzde)', suffixText: '%')),
                  ]),
                ),
            ],
          ),
          CrewCard(
            title: 'Kargo firmaları',
            subtitle: 'Takip bağlantısında {code} takip numarasıyla değişir.',
            action: _canEdit ? TextButton.icon(onPressed: () => setState(() {
                      _carriers.add(_Carrier(const {}));
                      _dirty = true;
                    }), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Firma ekle')) : null,
            children: [
              if (_carriers.isEmpty) const CrewNote('Henüz kargo firması yok. "Firma ekle" ile başla.'),
              for (final c in _carriers)
                CrewItemCard(
                  title: c.name.text.isEmpty ? 'Yeni firma' : c.name.text,
                  onRemove: _canEdit ? () => setState(() => (_carriers.remove(c), _dirty = true)) : null,
                  child: CrewFormGrid(children: [
                    TextField(controller: c.id, enabled: _canEdit, onChanged: (_) => setState(() => _dirty = true), decoration: const InputDecoration(labelText: 'Kimlik (ör. yurtici)')),
                    TextField(controller: c.name, enabled: _canEdit, onChanged: (_) => setState(() => _dirty = true), decoration: const InputDecoration(labelText: 'Görünen ad')),
                    CrewSpan.full(TextField(controller: c.url, enabled: _canEdit, onChanged: (_) => setState(() => _dirty = true), decoration: const InputDecoration(labelText: 'Takip bağlantısı (https://…{code})'))),
                  ]),
                ),
            ],
          ),
          CrewCard(
            title: 'Kapalı kategoriler',
            subtitle: 'Kapalı kategoride yeni ilan açılamaz; yayındaki ilanlar sürer.',
            children: [
              Wrap(spacing: CrewSpace.sm, runSpacing: CrewSpace.sm, children: [
                for (final r in cats)
                  FilterChip(
                    label: Text('${r.emoji} ${r.shortLabel}'),
                    selected: _closed.contains(r.id),
                    onSelected: _canEdit ? (on) => setState(() => (on ? _closed.add(r.id) : _closed.remove(r.id), _dirty = true)) : null,
                  ),
              ]),
            ],
          ),
        ],
      ],
    );
  }
}

/// Derin kopya (JSON uyumlu harita/liste).
Object? jsonClone(Object? v) => v is Map ? {for (final e in v.entries) '${e.key}': jsonClone(e.value)} : v is List ? [for (final x in v) jsonClone(x)] : v;
