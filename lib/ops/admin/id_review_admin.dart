// HADİ — Kimlik doğrulama incelemesi (kurucu ya da `identity.review`).
//
// Otomatik kontroller (SOD imzası, DG1/DG2 özetleri, CSCA zinciri, cihaz üstü yüz eşleşmesi, canlılık,
// ad/doğum tarihi uyumu) yalnızca bilgi içindir: kararı her zaman yetkili verir. Kimlik elde fotoğrafı
// onay ya da retten sonra sunucuda silinir. Sunucu: functions/src/identity.ts.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:hadi/data/models.dart';
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/features/identity/identity_service.dart';
import 'event_policy_admin.dart' show EventIdRequirementCard;

import 'package:hadi/widgets/net_fallback.dart';
import 'package:hadi/features/fun/_placeholders.dart';
class IdReviewAdminTab extends StatefulWidget {
  const IdReviewAdminTab({super.key, this.embedded = true});
  final bool embedded;

  @override
  State<IdReviewAdminTab> createState() => _IdReviewAdminTabState();
}

class _IdReviewAdminTabState extends State<IdReviewAdminTab> {
  String _status = 'pending';
  List<IdReviewItem>? _items;
  String? _error, _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await IdentityService.instance.list(status: _status);
      if (mounted) setState(() => _items = r);
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
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

  Future<void> _approve(IdReviewItem r) async {
    final mrz = r.mrz;
    final names = r.userName.split(' ');
    final first = TextEditingController(text: names.length > 1 ? names.sublist(0, names.length - 1).join(' ') : r.userName);
    final last = TextEditingController(text: names.length > 1 ? names.last : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(scrollable: true, 
        title: const Text('Kimliği onayla'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Çipteki ad: ${mrz['givenNames'] ?? ''} ${mrz['surname'] ?? ''}'),
            const SizedBox(height: 8),
            const Text('Kimlik elde fotoğrafındaki yüz, kart ve profil fotoğrafı aynı kişi mi? Onaylanınca ad soyad kilitlenir. '
                'Türkçe harfleri düzeltmek için aşağıyı düzenleyebilirsin (çipteki adla aynı olmalı).'),
            TextField(controller: first, decoration: const InputDecoration(labelText: 'Ad')),
            TextField(controller: last, decoration: const InputDecoration(labelText: 'Soyad')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Onayla')),
        ],
      ),
    );
    final f = first.text.trim(), l = last.text.trim();
    first.dispose();
    last.dispose();
    if (ok != true) return;
    await _run(r.uid, () => IdentityService.instance.approve(r.uid, firstName: f.isEmpty ? null : f, lastName: l.isEmpty ? null : l), 'Kimlik onaylandı.');
  }

  Future<void> _reject(IdReviewItem r) async {
    final why = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(scrollable: true, 
        title: const Text('Reddet'),
        content: TextField(
          controller: why,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Gerekçe (üyeye gösterilir)', hintText: 'Ör. fotoğraf net değil / kart görünmüyor / yüz eşleşmiyor'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: HadiColors.fillForWhite(HadiColors.error), foregroundColor: Colors.white), onPressed: () => Navigator.pop(c, true), child: const Text('Reddet')),
        ],
      ),
    );
    final reason = why.text.trim();
    why.dispose();
    if (ok != true) return;
    if (reason.isEmpty) return _snack('Gerekçe yaz.');
    await _run(r.uid, () => IdentityService.instance.reject(r.uid, reason), 'Reddedildi.');
  }

  Widget _check(String label, Object? v, {String? detail}) {
    final ok = v == true || v == 'verified';
    final unknown = v == null || v == 'unverified';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(children: [
        Icon(ok ? Icons.check_circle_rounded : (unknown ? Icons.help_outline_rounded : Icons.cancel_rounded),
            size: 16, color: ok ? HadiColors.dostluk : (unknown ? HadiColors.ink3 : HadiColors.error)),
        const SizedBox(width: 6),
        Expanded(child: Text(detail == null ? label : '$label · $detail', style: const TextStyle(fontSize: 13))),
      ]),
    );
  }

  Widget _card(IdReviewItem r) {
    final c = r.checks;
    final mrz = r.mrz;
    final busy = _busy == r.uid;
    final score = (c['faceMatchScore'] as num?)?.toDouble();
    final thr = (c['faceThreshold'] as num?)?.toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (r.photoUrl != null)
              CircleAvatar(radius: 22, backgroundImage: CachedNetworkImageProvider(r.photoUrl!))
            else
              const CircleAvatar(radius: 22, child: Icon(Icons.person_rounded)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.userName.isEmpty ? r.uid : r.userName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                if (r.username != null) Text('@${r.username}', style: TextStyle(color: HadiColors.ink3)),
              ]),
            ),
            if (r.autoOk)
              const Chip(label: Text('Kontroller tamam'), avatar: Icon(Icons.verified_rounded, size: 16, color: HadiColors.dostluk)),
          ]),
          const SizedBox(height: 8),
          Text('Çip: ${mrz['givenNames'] ?? ''} ${mrz['surname'] ?? ''} · doğum ${mrz['birthDate'] ?? '-'} · '
              'geçerlilik ${mrz['expiry'] ?? '-'} · ${mrz['nationality'] ?? ''} ${mrz['docType'] ?? ''}'),
          const SizedBox(height: 8),
          _check('Devlet imzası (SOD)', c['signatureOk'], detail: c['hashAlg'] as String?),
          _check('İmzalı özet', c['messageDigestOk']),
          _check('MRZ verisi (DG1) çiple uyumlu', c['dg1HashOk']),
          _check('Fotoğraf verisi (DG2) çiple uyumlu', c['dg2HashOk']),
          _check('CSCA zinciri', c['chain'], detail: c['chain'] == 'unverified' ? 'kök sertifika tanımlı değil' : null),
          _check('Yüz eşleşmesi', score != null && thr != null ? score >= thr : null,
              detail: score == null ? null : '${(score * 100).round()}% (eşik ${((thr ?? 0) * 100).round()}%, ${c['faceSource'] == 'card_photo' ? 'kart fotoğrafı' : c['faceSource'] == 'dg2' ? 'çip fotoğrafı' : 'model yok'})'),
          _check('Canlılık', c['livenessOk']),
          _check('Ad kayıtla aynı', c['nameMatch']),
          _check('Doğum tarihi kayıtla aynı', c['birthMatch']),
          if (c['error'] != null) Text('Not: ${c['error']}', style: TextStyle(color: HadiColors.ink3, fontSize: 12)),
          if (r.handheldUrl != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: GestureDetector(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => Dialog(child: InteractiveViewer(child: CachedNetworkImage(imageUrl: r.handheldUrl!, errorWidget: NetImageFallback.builder))),
                ),
                child: CachedNetworkImage(imageUrl: r.handheldUrl!, height: 240, width: double.infinity, fit: BoxFit.cover, errorWidget: NetImageFallback.builder),
              ),
            ),
          ],
          if (r.reason != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Gerekçe: ${r.reason}')),
          if (r.status == 'pending') ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => _reject(r),
                  style: OutlinedButton.styleFrom(foregroundColor: HadiColors.text(HadiColors.error)),
                  child: const Text('Reddet'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(onPressed: busy ? null : () => _approve(r), child: const Text('Onayla'))),
            ]),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final body = Column(children: [
      // Etkinliğe katılımda kimlik doğrulaması ayarı (config/events.idRequirement; event_policy_admin.dart).
      const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 0), child: EventIdRequirementCard()),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'pending', label: FittedBox(fit: BoxFit.scaleDown, child: Text('Bekleyen', maxLines: 1))),
            ButtonSegment(value: 'approved', label: FittedBox(fit: BoxFit.scaleDown, child: Text('Onaylanan', maxLines: 1))),
            ButtonSegment(value: 'rejected', label: FittedBox(fit: BoxFit.scaleDown, child: Text('Reddedilen', maxLines: 1))),
          ],
          selected: {_status},
          onSelectionChanged: (v) {
            setState(() {
              _status = v.first;
              _items = null;
            });
            _load();
          },
        ),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: items == null
              ? (_error != null
                  ? ListView(children: [Padding(padding: const EdgeInsets.all(40), child: Text(_error!, textAlign: TextAlign.center))])
                  : const RowsSkeleton())
              : items.isEmpty
                  ? ListView(children: [
                      Padding(padding: EdgeInsets.all(40), child: Text('Kayıt yok.', textAlign: TextAlign.center, style: TextStyle(color: HadiColors.ink2))),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _card(items[i]),
                    ),
        ),
      ),
    ]);
    return widget.embedded ? body : Scaffold(appBar: AppBar(title: const Text('Kimlik doğrulamaları', maxLines: 1, overflow: TextOverflow.ellipsis)), body: body);
  }
}
