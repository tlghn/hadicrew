// HADİ — Yetkili inceleme kuyrukları:
//   • Adres belgeleri (adres doğrulaması; e-Devlet yerleşim yeri belgesi, elle doğrulama) — `address.review`
//   • Kahve güvenlik incelemesi (yapay zekânın risk gördüğü Kahve Eşleşmesi üyeleri) — `kahve.safety`
// Kurucular her zaman görür. Sunucu: functions/src/address_verification.ts, functions/src/kahve_profile.ts.
import 'package:flutter/material.dart';
import 'package:hadi/panel_ui/crew_ui.dart' show CrewMaxWidth;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hadi/data/address_service.dart';
import 'package:hadi/data/kahve_service.dart';
import 'package:hadi/data/models.dart';
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/core/app_lock.dart';
import 'package:hadi/widgets/place_picker.dart';
import 'package:hadi/features/fun/_placeholders.dart';

String _when(DateTime? d) => d == null
    ? ''
    : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

Widget _wrap(bool embedded, String title, Widget body) =>
    embedded ? body : Scaffold(appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)), body: CrewMaxWidth(maxWidth: 900, padded: false, child: body));

Widget _empty(String text) => ListView(children: [
      Padding(padding: const EdgeInsets.all(40), child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: HadiColors.ink2))),
    ]);

// ============================================================================ Adres belgeleri

class AddressReviewAdminTab extends StatefulWidget {
  const AddressReviewAdminTab({super.key, this.embedded = true});
  final bool embedded;

  @override
  State<AddressReviewAdminTab> createState() => _AddressReviewAdminTabState();
}

class _AddressReviewAdminTabState extends State<AddressReviewAdminTab> {
  List<AddressReview>? _items;
  String? _error;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await AddressService.instance.pending();
      if (mounted) setState(() {
        _items = r;
        _error = null;
      });
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _approve(AddressReview r) async {
    final il = TextEditingController(), ilce = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Adresi onayla'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Belgeyi e-Devlet belge doğrulama sayfasında kontrol ettin mi? Adın üyeyle aynı olmalı. '
              'Yalnızca il ve ilçe saklanır; belge silinir.'),
          // Aranabilir il ve ile bağlı ilçe (belgede yazana göre).
          StatefulBuilder(
            builder: (c2, set) => Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 10),
              ProvinceField(
                value: il.text.isEmpty ? null : il.text,
                onChanged: (v) => set(() {
                  if ((v ?? '') != il.text) ilce.text = '';
                  il.text = v ?? '';
                }),
              ),
              const SizedBox(height: 10),
              DistrictField(
                province: il.text.isEmpty ? null : il.text,
                value: ilce.text.isEmpty ? null : ilce.text,
                onChanged: (v) => set(() => ilce.text = v ?? ''),
              ),
            ]),
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Onayla')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(r.uid, () => AddressService.instance.approve(r.uid, il: il.text.trim(), ilce: ilce.text.trim()), 'Adres onaylandı.');
  }

  Future<void> _reject(AddressReview r) async {
    final why = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(scrollable: true, 
        title: const Text('Belgeyi reddet'),
        content: TextField(
          controller: why,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Gerekçe (üyeye gösterilir)', hintText: 'Ör. belge doğrulanamadı / ad uyuşmuyor / süresi geçmiş'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: HadiColors.fillForWhite(HadiColors.error), foregroundColor: Colors.white), onPressed: () => Navigator.pop(c, true), child: const Text('Reddet')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(r.uid, () => AddressService.instance.reject(r.uid, why.text.trim()), 'Belge reddedildi.');
  }

  Future<void> _run(String uid, Future<void> Function() f, String done) async {
    setState(() => _busy = uid);
    try {
      await f();
      _snack(done);
      await _load();
    } on AppFailure catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return _wrap(
      widget.embedded,
      'Adres belgeleri',
      RefreshIndicator(
        onRefresh: _load,
        child: items == null
            ? (_error != null ? _empty(_error!) : const RowsSkeleton())
            : items.isEmpty
                ? _empty('Bekleyen adres belgesi yok.')
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final r = items[i];
                      final busy = _busy == r.uid;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(r.name.isEmpty ? r.uid : r.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                            if (r.phone.isNotEmpty) Text(r.phone, style: TextStyle(color: HadiColors.ink3)),
                            Text('Gönderim: ${_when(r.submittedAt)}', style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
                            const SizedBox(height: 8),
                            Row(children: [
                              Expanded(child: SelectableText('Barkod: ${r.code}', style: const TextStyle(fontWeight: FontWeight.w700))),
                              IconButton(
                                tooltip: 'Kopyala',
                                icon: const Icon(Icons.copy_rounded, size: 18),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: r.code));
                                  _snack('Barkod kopyalandı.');
                                },
                              ),
                            ]),
                            Wrap(spacing: 8, runSpacing: 4, children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.picture_as_pdf_rounded),
                                label: const Text('Belgeyi aç'),
                                onPressed: r.pdfUrl == null ? null : () => AppLock.instance.external(() => launchUrl(Uri.parse(r.pdfUrl!), mode: LaunchMode.externalApplication)),
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.verified_outlined),
                                label: const Text('e-Devlet\'te doğrula'),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: r.code));
                                  AppLock.instance.external(() => launchUrl(Uri.parse(AddressService.edevletVerifyUrl), mode: LaunchMode.externalApplication));
                                },
                              ),
                            ]),
                            const SizedBox(height: 6),
                            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                              TextButton(onPressed: busy ? null : () => _reject(r), child: const Text('Reddet')),
                              const SizedBox(width: 8),
                              FilledButton(onPressed: busy ? null : () => _approve(r), child: const Text('Onayla')),
                            ]),
                          ]),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

// ============================================================================ Kahve güvenlik incelemesi

class KahveSafetyAdminTab extends StatefulWidget {
  const KahveSafetyAdminTab({super.key, this.embedded = true});
  final bool embedded;

  @override
  State<KahveSafetyAdminTab> createState() => _KahveSafetyAdminTabState();
}

const _catLabels = {
  'siddet': 'Şiddet',
  'tehdit': 'Tehdit',
  'taciz': 'Taciz',
  'cinsel_taciz': 'Cinsel taciz',
  'israrli_takip': 'Israrlı takip',
  'baski_kontrol': 'Baskı/kontrol',
  'nefret': 'Nefret söylemi',
};

class _KahveSafetyAdminTabState extends State<KahveSafetyAdminTab> {
  List<KahveSafetyItem>? _items;
  String? _error;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await KahveService.instance.safetyList();
      if (mounted) setState(() {
        _items = r;
        _error = null;
      });
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _decide(KahveSafetyItem it, String decision) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(scrollable: true, 
        title: Text(decision == 'clear' ? 'Eşleşmeye geri al' : 'Kahve Eşleşmesi dışında tut'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(decision == 'clear'
              ? 'Yapay zekâ yanılmış: üye yeniden eşleşebilir, puanı sıfırlanır.'
              : 'Üye Kahve Eşleşmesi\'ne katılamaz. Bu karar yalnızca Kahve Eşleşmesi\'ni etkiler; üyelik için ayrıca şikâyet/uyarı süreci gerekir.'),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'Not (isteğe bağlı, denetim kaydına)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kaydet')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = it.uid);
    try {
      await KahveService.instance.safetyDecide(it.uid, decision, note: note.text.trim());
      await _load();
    } on AppFailure catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return _wrap(
      widget.embedded,
      'Kahve güvenlik incelemesi',
      RefreshIndicator(
        onRefresh: _load,
        child: items == null
            ? (_error != null ? _empty(_error!) : const RowsSkeleton())
            : items.isEmpty
                ? _empty('Bekleyen Kahve güvenlik incelemesi yok.')
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      if (i == 0) {
                        return Text(
                          'Yapay zekâ bu üyelerin kendi yazdıklarında risk gördü ve onları yalnızca Kahve Eşleşmesi\'nden geçici olarak çıkardı. '
                          'Alıntılar, üyenin açık rızasıyla ve yalnızca bu karar için gösterilir; karar verilince silinir.',
                          style: TextStyle(color: HadiColors.ink2, fontSize: 12.5, height: 1.35),
                        );
                      }
                      final it = items[i - 1];
                      final busy = _busy == it.uid;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(it.name.isEmpty ? it.uid : it.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                              Text('Risk ${(it.score * 100).round()}%', style: TextStyle(color: HadiColors.text(HadiColors.error), fontWeight: FontWeight.w800)),
                            ]),
                            Text(_when(it.at), style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
                            const SizedBox(height: 6),
                            Wrap(spacing: 6, runSpacing: 6, children: [
                              for (final c in it.categories) Chip(label: Text(_catLabels[c] ?? c), visualDensity: VisualDensity.compact),
                            ]),
                            for (final e in it.evidence)
                              Container(
                                margin: const EdgeInsets.only(top: 6),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: HadiColors.mist, borderRadius: BorderRadius.circular(10)),
                                child: Text('“$e”', style: TextStyle(fontStyle: FontStyle.italic, color: HadiColors.ink)),
                              ),
                            const SizedBox(height: 8),
                            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                              TextButton(onPressed: busy ? null : () => _decide(it, 'clear'), child: const Text('Eşleşmeye geri al')),
                              const SizedBox(width: 8),
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: HadiColors.fillForWhite(HadiColors.error), foregroundColor: Colors.white),
                                onPressed: busy ? null : () => _decide(it, 'exclude'),
                                child: const Text('Dışarıda tut'),
                              ),
                            ]),
                          ]),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
