// HADİ Crew — Mağaza kampanyaları (24 Ekim 2026): liste, oluştur/düzenle, durdur/başlat, sil, örnekleri ekle, kullanım
// istatistikleri (kullanım, verilen indirim, kampanyalı ciro). Sunucu: `store` › adminCampaigns / adminCampaignSave /
// adminCampaignToggle / adminCampaignDelete / adminCampaignSeed (store_marketing.ts; hesap commerce_engine.ts).
// Fiyat her zaman sunucuda hesaplanır; bu ekran yalnızca kuralları yönetir. Yetki: kurucu ya da store.manage.
import 'package:flutter/material.dart';
import 'package:hadi/panel_ui/crew_ui.dart';

import 'package:hadi/core/format.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/data/store_service.dart' show StoreService, kStoreAudiences, kStoreCampaignTypes;
import 'package:hadi/theme/hadi_colors.dart';

import 'store_admin_common.dart';

StoreService _svc(BuildContext context) => StoreService.of(SessionScope.read(context).services);

class StoreCampaignsAdminTab extends StatefulWidget {
  const StoreCampaignsAdminTab({super.key, this.embedded = true});
  final bool embedded;

  @override
  State<StoreCampaignsAdminTab> createState() => _StoreCampaignsAdminTabState();
}

class _StoreCampaignsAdminTabState extends State<StoreCampaignsAdminTab> {
  List<Map<String, dynamic>>? _list;
  String? _error;
  final _busy = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_list == null && _error == null) _load();
  }

  Future<void> _load() async {
    try {
      final r = await _svc(context).adminCampaigns();
      if (mounted) {
        setState(() {
          _list = storeList(r['campaigns']);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = storeError(e));
    }
  }

  Future<void> _run(String key, Future<void> Function() f, String ok) async {
    setState(() => _busy.add(key));
    try {
      await f();
      if (mounted) storeToast(context, ok);
      await _load();
    } catch (e) {
      if (mounted) storeToast(context, e is StateError ? e.message : storeError(e));
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _edit([Map<String, dynamic>? c]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => _CampaignEditor(initial: c)));
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    final body = RefreshIndicator(
      onRefresh: _load,
      child: CrewListView(maxWidth: 960, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: const Text('Yeni kampanya')),
          OutlinedButton.icon(
            onPressed: _busy.contains('seed')
                ? null
                : () {
                    final svc = _svc(context);
                    _run('seed', () async {
                      final n = await svc.adminCampaignSeed();
                      if (n == 0) throw StateError('Örnekler zaten ekli.');
                    }, 'Örnek kampanyalar KAPALI olarak eklendi; incele, düzenle, sonra başlat.');
                  },
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Örnekleri ekle'),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          'İndirimler sunucuda, işletme siparişleriyle aynı kampanya motoruyla hesaplanır: uygun kampanyaların üye lehine en iyi birleşimi uygulanır. '
          '"Birleşmez" kampanyalar başka indirimle üst üste binmez. Kupon kodları büyük/küçük harf ve İ/I farkı gözetmez.',
          style: TextStyle(color: HadiColors.ink3, fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        if (_error != null) Text(_error!, style: TextStyle(color: HadiColors.text(HadiColors.error))),
        if (list == null && _error == null) const StoreCard(child: CrewLoading(rows: 3)),
        if (list != null && list.isEmpty)
          StoreCard(
            child: CrewEmpty(
              icon: Icons.local_offer_outlined,
              title: 'Henüz kampanya yok',
              message: 'Yeni kampanya oluştur ya da örnek kampanyaları (kapalı olarak) ekleyip düzenle.',
              action: FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Yeni kampanya')),
            ),
          ),
        for (final c in list ?? const <Map<String, dynamic>>[]) _CampaignCard(
          c: c,
          busy: _busy.contains('${c['id']}'),
          onToggle: (v) => _run('${c['id']}', () => _svc(context).adminCampaignToggle('${c['id']}', v), v ? 'Kampanya başladı.' : 'Kampanya durduruldu.'),
          onEdit: () => _edit(c),
          onDelete: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (d) => AlertDialog(
                title: const Text('Kampanya silinsin mi?'),
                content: const Text('Kullanılmış kampanyalar istatistik için arşivlenir (kapalı); hiç kullanılmamışlar tamamen silinir.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
                  FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Sil')),
                ],
              ),
            );
            if (ok == true && context.mounted) await _run('${c['id']}', () => _svc(context).adminCampaignDelete('${c['id']}'), 'Silindi.');
          },
        ),
      ]),
    );
    return widget.embedded ? body : Scaffold(appBar: AppBar(title: const Text('Mağaza kampanyaları')), body: body);
  }
}

String _typeLabel(String t) => kStoreCampaignTypes[t] ?? t;
String _audLabel(String a) => kStoreAudiences[a] ?? a;

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({required this.c, required this.busy, required this.onToggle, required this.onEdit, required this.onDelete});
  final Map<String, dynamic> c;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final active = c['active'] == true;
    final st = storeMap(c['stats']);
    final starts = storeTime(c['startsAt']), ends = storeTime(c['endsAt']);
    final expired = ends != null && ends.isBefore(DateTime.now());
    final scope = storeMap(c['scope']);
    final scopeText = switch ('${scope['kind'] ?? 'all'}') {
      'sections' => 'Kategoriler: ${[for (final x in (scope['sections'] as List? ?? const [])) storeCategoryLabel('$x')].join(', ')}',
      'items' => 'Ürünler: ${(scope['items'] as List? ?? const []).join(', ')}',
      _ => 'Tüm mağaza',
    };
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: StoreCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${c['label'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5)),
                Text('${c['badge'] ?? _typeLabel('${c['type']}')} · ${_typeLabel('${c['type']}')}', style: t.bodySmall?.copyWith(color: HadiColors.ink3)),
              ]),
            ),
            if (busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) else Switch(value: active, onChanged: onToggle),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _Tag(active ? (expired ? 'Süresi doldu' : 'Yayında') : 'Durduruldu', expired ? HadiColors.ink3 : (active ? HadiColors.dostluk : HadiColors.ink3)),
            _Tag(_audLabel('${c['audience'] ?? 'all'}'), HadiColors.aktivite),
            if ('${c['couponCode'] ?? ''}'.isNotEmpty) _Tag('Kupon: ${c['couponCode']}', HadiColors.iletisim),
            if (c['digital'] == true) _Tag('Dijitale de', HadiColors.aktivite),
            if (c['stackable'] == true) _Tag('Birleşir', HadiColors.heyecan),
            if (c['banner'] is Map) _Tag('Vitrinde bant', HadiColors.pink),
          ]),
          const SizedBox(height: 6),
          Text(scopeText, style: t.bodySmall),
          if (starts != null || ends != null) Text('${starts == null ? 'Hemen' : dateTimeLong(starts)} → ${ends == null ? 'süresiz' : dateTimeLong(ends)}', style: t.bodySmall),
          const SizedBox(height: 8),
          Wrap(spacing: 14, runSpacing: 4, children: [
            _Stat('Kullanım', '${storeNum(st['used']).toInt()}${storeNum(c['usageLimit']) > 0 ? ' / ${storeNum(c['usageLimit']).toInt()}' : ''}'),
            _Stat('Verilen indirim', money(storeNum(st['spentTl']))),
            _Stat('Kampanyalı ciro', money(storeNum(st['revenueTl']))),
            if (storeNum(c['stockLimit']) > 0) _Stat('Flaş stok', '${storeNum(st['stockUsed']).toInt()} / ${storeNum(c['stockLimit']).toInt()}'),
            if (storeNum(st['digitalElmas']) > 0) _Stat('Dijital indirim', '${storeNum(st['digitalElmas']).toInt()}💎'),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Düzenle')),
            TextButton.icon(onPressed: onDelete, icon: Icon(Icons.delete_outline_rounded, size: 18, color: HadiColors.text(HadiColors.error)), label: Text('Sil', style: TextStyle(color: HadiColors.text(HadiColors.error)))),
          ]),
        ]),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: HadiColors.wash(color), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: HadiColors.text(color), fontWeight: FontWeight.w800, fontSize: 11.5)),
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(fontSize: 11.5, color: HadiColors.ink3)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
      ]);
}

// ============================================================================ düzenleyici

class _CampaignEditor extends StatefulWidget {
  const _CampaignEditor({this.initial});
  final Map<String, dynamic>? initial;

  @override
  State<_CampaignEditor> createState() => _CampaignEditorState();
}

class _CampaignEditorState extends State<_CampaignEditor> {
  late final Map<String, dynamic> _c = {...?widget.initial};
  late String _type = '${_c['type'] ?? 'pct'}';
  late String _aud = '${_c['audience'] ?? 'all'}';
  late String _scope = '${storeMap(_c['scope'])['kind'] ?? 'all'}';
  late final Set<String> _sections = {for (final x in (storeMap(_c['scope'])['sections'] as List? ?? const [])) '$x'};
  late final Set<String> _items = {for (final x in (storeMap(_c['scope'])['items'] as List? ?? const [])) '$x'};
  late bool _active = _c['active'] == true;
  late bool _stackable = _c['stackable'] == true;
  late bool _digital = _c['digital'] == true;
  late bool _banner = _c['banner'] is Map;
  late DateTime? _starts = storeTime(_c['startsAt']);
  late DateTime? _ends = storeTime(_c['endsAt']);
  final _f = <String, TextEditingController>{};
  List<(String, String)> _products = const [];
  final _bundle = <(TextEditingController, TextEditingController)>[];
  bool _saving = false;

  TextEditingController _t(String k, [Object? init]) => _f.putIfAbsent(k, () {
        final v = init ?? _c[k];
        return TextEditingController(text: v == null || v == 0 || '$v' == '0' ? '' : '$v');
      });

  @override
  void initState() {
    super.initState();
    final b = storeMap(_c['banner']);
    _t('bannerTitle', b['title']);
    _t('bannerSubtitle', b['subtitle']);
    _t('bannerColor', b['color'] ?? '#F2801F');
    _t('bannerProduct', b['productId']);
    final bundle = storeMap(_c['bundle']);
    for (final x in storeList(bundle['items'])) {
      _bundle.add((TextEditingController(text: '${x['name'] ?? ''}'), TextEditingController(text: '${x['qty'] ?? 1}')));
    }
    if (_bundle.isEmpty) _bundle.add((TextEditingController(), TextEditingController(text: '1')));
    _t('bundlePrice', bundle['priceTl']);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final ps = await _svc(context).adminProducts();
        if (mounted) setState(() => _products = [for (final p in ps) (p.id, p.title)]);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    for (final c in _f.values) {
      c.dispose();
    }
    for (final (a, b) in _bundle) {
      a.dispose();
      b.dispose();
    }
    super.dispose();
  }

  num _n(String k) => num.tryParse(_t(k).text.trim().replaceAll(',', '.')) ?? 0;

  bool get _usesPct => const {'pct', 'cart_pct', 'nth_pct', 'flash', 'first_order'}.contains(_type);
  bool get _usesAmount => const {'amount_item', 'cart_amount', 'first_order'}.contains(_type);
  bool get _usesMinCart => const {'cart_pct', 'cart_amount', 'free_shipping'}.contains(_type);

  Future<void> _pickDate(bool start) async {
    final now = DateTime.now();
    final init = (start ? _starts : _ends) ?? now;
    final d = await showDatePicker(context: context, initialDate: init, firstDate: now.subtract(const Duration(days: 1)), lastDate: now.add(const Duration(days: 730)));
    if (d == null || !mounted) return;
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(init));
    final v = DateTime(d.year, d.month, d.day, tm?.hour ?? 0, tm?.minute ?? 0);
    setState(() => start ? _starts = v : _ends = v);
  }

  Future<void> _save() async {
    final label = _t('label').text.trim();
    if (label.isEmpty) return storeToast(context, 'Kampanyaya bir ad ver.');
    final m = <String, Object?>{
      if ('${_c['id'] ?? ''}'.isNotEmpty) 'id': _c['id'],
      'type': _type,
      'label': label,
      'active': _active,
      'audience': _aud,
      'scope': {'kind': _scope, 'sections': _sections.toList(), 'items': _items.toList()},
      'pct': _n('pct'),
      'amountTl': _n('amountTl'),
      'minCartTl': _n('minCartTl'),
      'maxDiscountTl': _n('maxDiscountTl'),
      'x': _n('x'),
      'y': _n('y'),
      'n': _n('n'),
      'bundle': {
        'items': [
          for (final (a, b) in _bundle)
            if (a.text.trim().isNotEmpty) {'name': a.text.trim(), 'qty': int.tryParse(b.text.trim()) ?? 1},
        ],
        'priceTl': _n('bundlePrice'),
      },
      'startsAt': _starts?.millisecondsSinceEpoch,
      'endsAt': _ends?.millisecondsSinceEpoch,
      'couponCode': _t('couponCode').text.trim(),
      'usageLimit': _n('usageLimit'),
      'perMemberLimit': _n('perMemberLimit'),
      'budgetTl': _n('budgetTl'),
      'stockLimit': _n('stockLimit'),
      'priority': _n('priority'),
      'stackable': _stackable,
      'digital': _digital,
      'note': _t('note').text.trim(),
      'banner': _banner
          ? {'title': _t('bannerTitle').text.trim(), 'subtitle': _t('bannerSubtitle').text.trim(), 'color': _t('bannerColor').text.trim(), 'productId': _t('bannerProduct').text.trim()}
          : null,
    };
    setState(() => _saving = true);
    try {
      await _svc(context).adminCampaignSave(m);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) storeToast(context, storeError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _num(String k, String label, {String? suffix, String? help}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _t(k),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, suffixText: suffix, helperText: help, isDense: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'Yeni kampanya' : 'Kampanyayı düzenle'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Kaydet')),
          ),
        ],
      ),
      body: CrewListView(maxWidth: CrewWidth.form, children: [
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _active, onChanged: (v) => setState(() => _active = v), title: const Text('Yayında', style: TextStyle(fontWeight: FontWeight.w800))),
            const SizedBox(height: 8),
            TextField(controller: _t('label'), maxLength: 60, decoration: const InputDecoration(labelText: 'Kampanya adı (üyeler görür)', isDense: true)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: kStoreCampaignTypes.containsKey(_type) ? _type : 'pct',
              decoration: const InputDecoration(labelText: 'Tür', isDense: true),
              items: [for (final e in kStoreCampaignTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: kStoreAudiences.containsKey(_aud) ? _aud : 'all',
              decoration: const InputDecoration(labelText: 'Kimlere', isDense: true, helperText: 'Doğum ayı ve davet bilgisi yalnızca uygunluk için sunucuda okunur; ekipte görünmez.'),
              items: [for (final e in kStoreAudiences.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _aud = v ?? _aud),
            ),
            StoreSectionTitle('Değer'),
            if (_usesPct) _num('pct', _type == 'nth_pct' ? 'N. üründe indirim (%100 = bedava)' : 'İndirim oranı', suffix: '%'),
            if (_usesAmount) _num('amountTl', _type == 'amount_item' ? 'Ürün başına indirim' : 'İndirim tutarı', suffix: 'TL'),
            if (_usesMinCart) _num('minCartTl', 'En az sepet tutarı', suffix: 'TL'),
            if (_type == 'pct' || _type == 'cart_pct' || _type == 'first_order') _num('maxDiscountTl', 'İndirim tavanı (boş: sınırsız)', suffix: 'TL'),
            if (_type == 'bxgy') Row(children: [Expanded(child: _num('x', 'X al')), const SizedBox(width: 10), Expanded(child: _num('y', 'Y öde'))]),
            if (_type == 'nth_pct') _num('n', 'Kaçıncı ürün (N)'),
            if (_type == 'flash') _num('stockLimit', 'Flaş stok (adet)'),
            if (_type == 'bundle') ...[
              Text('Paketteki ürünler (ürün kimliği + adet)', style: t.labelLarge),
              for (var i = 0; i < _bundle.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    Expanded(
                      flex: 3,
                      child: _products.isEmpty
                          ? TextField(controller: _bundle[i].$1, decoration: const InputDecoration(labelText: 'Ürün kimliği', isDense: true))
                          : DropdownButtonFormField<String>(
                              initialValue: _products.any((p) => p.$1 == _bundle[i].$1.text) ? _bundle[i].$1.text : null,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Ürün', isDense: true),
                              items: [for (final p in _products) DropdownMenuItem(value: p.$1, child: Text(p.$2, overflow: TextOverflow.ellipsis))],
                              onChanged: (v) => _bundle[i].$1.text = v ?? '',
                            ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(width: 70, child: TextField(controller: _bundle[i].$2, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Adet', isDense: true))),
                    IconButton(tooltip: 'Satırı sil', onPressed: _bundle.length < 2 ? null : () => setState(() => _bundle.removeAt(i)), icon: const Icon(Icons.remove_circle_outline)),
                  ]),
                ),
              TextButton.icon(onPressed: () => setState(() => _bundle.add((TextEditingController(), TextEditingController(text: '1')))), icon: const Icon(Icons.add_rounded), label: const Text('Ürün ekle')),
              _num('bundlePrice', 'Paket fiyatı', suffix: 'TL'),
            ],
            StoreSectionTitle('Kapsam'),
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'all', label: Text('Tümü')), ButtonSegment(value: 'sections', label: Text('Kategori')), ButtonSegment(value: 'items', label: Text('Ürün'))],
              selected: {_scope},
              onSelectionChanged: (v) => setState(() => _scope = v.first),
            ),
            const SizedBox(height: 8),
            if (_scope == 'sections')
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final (id, label, emoji) in kStoreCategories)
                  FilterChip(label: Text('$emoji $label'), selected: _sections.contains(id), onSelected: (v) => setState(() => v ? _sections.add(id) : _sections.remove(id))),
              ]),
            if (_scope == 'items')
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final (id, title) in _products) FilterChip(label: Text(title), selected: _items.contains(id), onSelected: (v) => setState(() => v ? _items.add(id) : _items.remove(id))),
                if (_products.isEmpty) const Text('Ürünler yükleniyor…'),
              ]),
            StoreSectionTitle('Zaman ve sınırlar'),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => _pickDate(true), child: Text(_starts == null ? 'Başlangıç: hemen' : 'Başlangıç: ${dateTimeLong(_starts!)}', overflow: TextOverflow.ellipsis))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: () => _pickDate(false), child: Text(_ends == null ? 'Bitiş: süresiz' : 'Bitiş: ${dateTimeLong(_ends!)}', overflow: TextOverflow.ellipsis))),
            ]),
            if (_starts != null || _ends != null) Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => setState(() => _starts = _ends = null), child: const Text('Tarihleri temizle'))),
            const SizedBox(height: 8),
            TextField(controller: _t('couponCode'), textCapitalization: TextCapitalization.characters, maxLength: 24, decoration: const InputDecoration(labelText: 'Kupon kodu (boş: kodsuz, kendiliğinden)', isDense: true)),
            Row(children: [
              Expanded(child: _num('usageLimit', 'Toplam kullanım (boş: sınırsız)')),
              const SizedBox(width: 10),
              Expanded(child: _num('perMemberLimit', 'Üye başı sınır')),
            ]),
            Row(children: [
              Expanded(child: _num('budgetTl', 'İndirim bütçesi', suffix: 'TL')),
              const SizedBox(width: 10),
              Expanded(child: _num('priority', 'Öncelik (0–100)')),
            ]),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _stackable, onChanged: (v) => setState(() => _stackable = v), title: const Text('Diğer kampanyalarla birleşebilir')),
            if (_type == 'pct' || _type == 'flash')
              SwitchListTile(contentPadding: EdgeInsets.zero, value: _digital, onChanged: (v) => setState(() => _digital = v), title: const Text('Dijital sürüm fiyatına da uygula (Elmas/Akçe)')),
            StoreSectionTitle('Vitrin bandı'),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: _banner, onChanged: (v) => setState(() => _banner = v), title: const Text('Mağaza vitrininin üstünde bant olarak göster')),
            if (_banner) ...[
              TextField(controller: _t('bannerTitle'), maxLength: 60, decoration: const InputDecoration(labelText: 'Bant başlığı', isDense: true)),
              TextField(controller: _t('bannerSubtitle'), maxLength: 120, decoration: const InputDecoration(labelText: 'Alt yazı', isDense: true)),
              Row(children: [
                Expanded(child: TextField(controller: _t('bannerColor'), decoration: const InputDecoration(labelText: 'Renk (#RRGGBB)', isDense: true))),
                const SizedBox(width: 10),
                Expanded(
                  child: _products.isEmpty
                      ? TextField(controller: _t('bannerProduct'), decoration: const InputDecoration(labelText: 'Ürün kimliği (isteğe bağlı)', isDense: true))
                      : DropdownButtonFormField<String>(
                          initialValue: _products.any((p) => p.$1 == _t('bannerProduct').text) ? _t('bannerProduct').text : '',
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Dokununca açılacak ürün', isDense: true),
                          items: [const DropdownMenuItem(value: '', child: Text('—')), for (final p in _products) DropdownMenuItem(value: p.$1, child: Text(p.$2, overflow: TextOverflow.ellipsis))],
                          onChanged: (v) => _t('bannerProduct').text = v ?? '',
                        ),
                ),
              ]),
            ],
            StoreSectionTitle('İç not'),
            TextField(controller: _t('note'), maxLength: 200, maxLines: 2, decoration: const InputDecoration(labelText: 'Ekip notu (üyeler görmez)', isDense: true)),
          ]),
    );
  }
}
