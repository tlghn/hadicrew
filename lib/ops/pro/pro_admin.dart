// HADİ Crew / Kurucu Paneli — Profesyonel profil yönetimi (arayüz: package:hadi/panel_ui/crew_ui.dart; rehber crew_ui_guide).
//
//   ProLicenseAdminTab   Lisans doğrulama kuyruğu (dört göz: ilk yetkili "ön onay", BAŞKA bir yetkili "onay"), bildirilen
//                        değerlendirmeler, profil gizleme. Yetki: kurucu ya da `pro.review`.
//   ProCatalogAdminTab   Meslek kataloğu (yalnızca kurucu): meslek ekle/düzenle/gizle, bloklar ve düğmeler, izin bayrakları
//                        (allowPrices, allowReviews, allowBooking, allowBeforeAfter), lisans/bilgilendirme, özel bloklar, ayarlar.
// Sunucu: functions/src/pro_profiles.ts (admin* op'ları); istemci: hadi › lib/data/pro_profile_service.dart (tanıtım modu dahil).
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hadi/core/capabilities.dart';
import 'package:hadi/core/format.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/data/hadi_call.dart' show asList, asMap;
import 'package:hadi/data/models.dart' show AppFailure;
import 'package:hadi/data/pro_profile_service.dart';
import 'package:hadi/panel_ui/crew_ui.dart';
import 'package:hadi/theme/hadi_colors.dart';

/// Lisans kuyruğunu görebilir mi (kurucu ya da `pro.review`).
bool canReviewPro(Session s) => s.isFounder || s.can(Cap.proReview);

ProProfileService _svc(BuildContext context) => ProProfileService.of(SessionScope.read(context).services);
String _err(Object e) => e is AppFailure ? e.message : 'İşlem tamamlanamadı.';
DateTime? _ms(Object? v) => v is num && v > 0 ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

// ================================================================== lisans kuyruğu

class ProLicenseAdminTab extends StatelessWidget {
  const ProLicenseAdminTab({super.key, this.embedded = true});
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    const tabs = TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [Tab(text: 'Lisans başvuruları'), Tab(text: 'Bildirilen değerlendirmeler'), Tab(text: 'Profil gizle')]);
    const views = TabBarView(children: [_Licenses(), _ReportedReviews(), _HideProfile()]);
    if (embedded) {
      return const DefaultTabController(length: 3, child: Column(children: [tabs, Expanded(child: views)]));
    }
    return const DefaultTabController(
      length: 3,
      child: CrewPage(title: 'Lisans doğrulama', subtitle: 'Profesyonel profil: meslek belgeleri, değerlendirmeler', bottom: tabs, body: views),
    );
  }
}

class _Licenses extends StatefulWidget {
  const _Licenses();
  @override
  State<_Licenses> createState() => _LicensesState();
}

class _LicensesState extends State<_Licenses> {
  String _status = '';
  Future<({List<Map<String, Object?>> items, bool fourEyes, String me, Map<String, Object?> docTypes})>? _f;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= _svc(context).adminLicenses();
  }

  Future<void> _reload() async {
    setState(() => _f = _svc(context).adminLicenses(status: _status.isEmpty ? null : _status));
    await _f;
  }

  Future<void> _open(String id) async {
    try {
      final url = await _svc(context).adminLicenseDoc(id);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) crewToast(context, _err(e));
    }
  }

  Future<void> _decide(Map<String, Object?> x, String decision) async {
    var note = '';
    if (decision == 'approve') {
      final ok = await crewConfirm(
        context,
        title: 'Onayla: ${x['name']} · ${x['professionLabel']}',
        message: 'Belgeyi ilgili kurumun kaydıyla (e-Devlet barkodu, baro/oda sorgusu) karşılaştırdıysan onayla. Dört göz açıksa ikinci onayı başka bir yetkili verir.',
      );
      if (!ok) return;
    } else {
      final r = await crewAskReason(context, title: 'Reddet: ${x['professionLabel']}', message: 'Gerekçe üyeye gösterilir; belge karardan sonra silinir.', confirm: 'Reddet', danger: true);
      if (r == null) return;
      note = r;
    }
    if (!mounted) return;
    try {
      final st = await _svc(context).adminLicenseDecide('${x['id']}', decision, note: note);
      if (!mounted) return;
      crewToast(context, switch (st) { 'first_ok' => 'Ön onay verildi; ikinci onayı başka bir yetkili verecek.', 'approved' => 'Onaylandı; belge silindi, üyeye bildirildi.', _ => 'Reddedildi; belge silindi, üyeye bildirildi.' });
      await _reload();
    } catch (e) {
      if (mounted) crewToast(context, _err(e));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _f,
        builder: (context, s) => CrewPage(
          title: '',
          embedded: true,
          onRefresh: _reload,
          toolbar: CrewToolbar(
            filters: CrewFilterChips<String>(
              options: const [('', 'Bekleyenler'), ('first_ok', 'Ön onaylı'), ('approved', 'Onaylanan'), ('rejected', 'Reddedilen'), ('all', 'Tümü')],
              value: _status,
              onChanged: (v) {
                _status = v;
                _reload();
              },
            ),
          ),
          children: [
            if (s.hasError)
              CrewError(message: _err(s.error!), onRetry: _reload)
            else if (!s.hasData)
              const CrewLoading()
            else ...[
              CrewNote(s.data!.fourEyes
                  ? 'Dört göz açık: onay için iki farklı yetkili gerekir. Belge karar verilir verilmez silinir; her açılış üyenin "Verime erişimler" ekranına yazılır.'
                  : 'Dört göz kapalı (Kurucu Paneli › Profesyonel profiller › Ayarlar).'),
              if (s.data!.items.isEmpty) const CrewEmpty(title: 'Bekleyen başvuru yok', message: 'Yeni lisans belgesi gelince burada ve panoda görünür.', icon: Icons.verified_outlined),
              for (final x in s.data!.items) _card(x, s.data!.me, s.data!.docTypes),
            ],
          ],
        ),
      );

  Widget _card(Map<String, Object?> x, String me, Map<String, Object?> docTypes) {
    final reviews = [for (final v in asList(x['reviews'])) asMap(v)];
    final st = '${x['status']}';
    final queue = st == 'pending' || st == 'first_ok';
    final iApproved = reviews.any((v) => v['by'] == me && v['decision'] == 'approve');
    final at = _ms(x['createdAt']);
    final (label, color) = switch (st) {
      'pending' => ('Bekliyor', HadiColors.heyecan),
      'first_ok' => ('Ön onaylı', HadiColors.aktivite),
      'approved' => ('Onaylandı', HadiColors.dostluk),
      'rejected' => ('Reddedildi', HadiColors.error),
      'expired' => ('Süresi doldu', HadiColors.ink3),
      _ => (st, HadiColors.ink3),
    };
    return CrewCard(
      title: '${x['name']} · ${x['professionLabel']}',
      icon: Icons.badge_outlined,
      action: CrewPill(label, color: color),
      children: [
        CrewInfoRow('Belge', '${docTypes[x['docType']] ?? x['docType']}'),
        if ('${x['unvan'] ?? ''}'.isNotEmpty) CrewInfoRow('Unvan', '${x['unvan']}'),
        if ('${x['institution'] ?? ''}'.isNotEmpty) CrewInfoRow('Kurum / oda', '${x['institution']}'),
        if ('${x['registryMasked'] ?? ''}'.isNotEmpty) CrewInfoRow('Sicil no', '${x['registryMasked']}'),
        if (at != null) CrewInfoRow('Başvuru', dateTimeLong(at)),
        for (final v in reviews) CrewInfoRow(v['decision'] == 'approve' ? 'Onay' : 'Ret', '${v['byName']}${'${v['note'] ?? ''}'.isEmpty ? '' : ' — ${v['note']}'}'),
        if (queue)
          Wrap(spacing: CrewSpace.sm, runSpacing: CrewSpace.sm, children: [
            OutlinedButton.icon(onPressed: x['hasDoc'] == true ? () => _open('${x['id']}') : null, icon: const Icon(Icons.description_outlined, size: 18), label: const Text('Belgeyi aç (10 dk)')),
            FilledButton(onPressed: iApproved ? null : () => _decide(x, 'approve'), child: Text(st == 'first_ok' ? 'İkinci onay' : 'Onayla')),
            TextButton(onPressed: () => _decide(x, 'reject'), child: const Text('Reddet')),
          ]),
        if (queue && iApproved) const CrewNote('Ön onayı sen verdin; ikinci onayı başka bir yetkili vermeli.'),
      ],
    );
  }
}

class _ReportedReviews extends StatefulWidget {
  const _ReportedReviews();
  @override
  State<_ReportedReviews> createState() => _ReportedReviewsState();
}

class _ReportedReviewsState extends State<_ReportedReviews> {
  Future<List<Map<String, Object?>>>? _f;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= _svc(context).adminReviews();
  }

  Future<void> _reload() async {
    setState(() => _f = _svc(context).adminReviews());
    await _f;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, Object?>>>(
        future: _f,
        builder: (context, s) => CrewPage(
          title: '',
          embedded: true,
          onRefresh: _reload,
          children: [
            if (s.hasError)
              CrewError(message: _err(s.error!), onRetry: _reload)
            else if (!s.hasData)
              const CrewLoading()
            else
              CrewListCard(
                title: 'Bildirilen değerlendirmeler',
                empty: const CrewEmpty(title: 'Bildirilen değerlendirme yok', message: 'Üyeler bir değerlendirmeyi bildirince burada görünür.', icon: Icons.reviews_outlined),
                children: [
                  for (final r in s.data!)
                    ListTile(
                      title: Text('${r['fromName']} · ${'★' * ((r['score'] as num?)?.toInt() ?? 0)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${r['text']}\nBildirim: ${[for (final x in asList(r['reports'])) asMap(x)['reason']].join(' · ')}', maxLines: 3, overflow: TextOverflow.ellipsis),
                      isThreeLine: true,
                      trailing: TextButton(
                        onPressed: () async {
                          try {
                            await _svc(context).adminReviewHide('${r['id']}', r['status'] != 'hidden');
                            await _reload();
                          } catch (e) {
                            if (context.mounted) crewToast(context, _err(e));
                          }
                        },
                        child: Text(r['status'] == 'hidden' ? 'Geri aç' : 'Gizle'),
                      ),
                    ),
                ],
              ),
          ],
        ),
      );
}

class _HideProfile extends StatefulWidget {
  const _HideProfile();
  @override
  State<_HideProfile> createState() => _HideProfileState();
}

class _HideProfileState extends State<_HideProfile> {
  final _uid = TextEditingController();

  @override
  void dispose() {
    _uid.dispose();
    super.dispose();
  }

  Future<void> _go(bool hide) async {
    final uid = _uid.text.trim();
    if (uid.isEmpty) return crewToast(context, 'Üye kimliğini yaz.');
    var reason = '';
    if (hide) {
      final r = await crewAskReason(context, title: 'Profesyonel profili gizle', message: 'Gerekçe üyeye gösterilir.', confirm: 'Gizle', danger: true);
      if (r == null) return;
      reason = r;
    }
    if (!mounted) return;
    try {
      await _svc(context).adminProfileHide(uid, hide, reason: reason);
      if (mounted) crewToast(context, hide ? 'Profesyonel profil gizlendi; üyeye bildirildi.' : 'Gizleme kaldırıldı.');
    } catch (e) {
      if (mounted) crewToast(context, _err(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CrewPage(
      title: '',
      embedded: true,
      maxWidth: CrewWidth.form,
      children: [
        CrewCard(
          title: 'Profil gizle',
          subtitle: 'Kurallara aykırı profesyonel profili keşiften ve profilden kaldırır; bireysel profil etkilenmez.',
          children: [
            TextField(controller: _uid, decoration: const InputDecoration(labelText: 'Üye kimliği (uid)')),
            Wrap(spacing: CrewSpace.sm, children: [
              FilledButton(style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError), onPressed: () => _go(true), child: const Text('Gizle')),
              OutlinedButton(onPressed: () => _go(false), child: const Text('Gizlemeyi kaldır')),
            ]),
          ],
        ),
      ],
    );
  }
}

// ================================================================== meslek kataloğu (Kurucu Paneli)

class ProCatalogAdminTab extends StatefulWidget {
  const ProCatalogAdminTab({super.key, this.embedded = true});
  final bool embedded;
  @override
  State<ProCatalogAdminTab> createState() => _ProCatalogAdminTabState();
}

class _ProCatalogAdminTabState extends State<ProCatalogAdminTab> {
  Future<Map<String, Object?>>? _f;
  String _q = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _f ??= _svc(context).adminCatalog();
  }

  Future<void> _reload() async {
    setState(() => _f = _svc(context).adminCatalog());
    await _f;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, Object?>>(
        future: _f,
        builder: (context, s) {
          final m = s.data;
          final profs = [for (final p in asList(m?['professions'])) ProProfession.fromMap(p)];
          final blocks = [for (final b in asList(m?['blocks'])) ProBlockDef.fromMap(b)];
          final ctas = [for (final c in asList(m?['ctas'])) ProCta.fromMap(c)];
          final groups = [for (final g in asList(m?['groups'])) asMap(g)];
          final defaults = {for (final d in asList(m?['defaults'])) '$d'};
          final overrides = asMap(m?['overrides']);
          final counts = asMap(m?['counts']);
          final cfg = asMap(m?['config']);
          final q = _q.trim().toLowerCase();
          final shown = [for (final p in profs) if (q.isEmpty || p.label.toLowerCase().contains(q) || p.id.contains(q)) p];
          return CrewPage(
            title: 'Profesyonel profiller',
            subtitle: 'Meslek kataloğu, bloklar, izinler',
            embedded: widget.embedded,
            onRefresh: _reload,
            actions: [FilledButton.icon(onPressed: m == null ? null : () => _edit(null, blocks, ctas, groups), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Yeni meslek'))],
            toolbar: CrewToolbar(search: CrewSearchField(hint: 'Meslek ara', onChanged: (v) => setState(() => _q = v))),
            children: [
              if (s.hasError)
                CrewError(message: _err(s.error!), onRetry: _reload)
              else if (m == null)
                const CrewLoading()
              else ...[
                _ConfigCard(key: ValueKey(cfg.toString()), cfg: cfg, onSaved: _reload),
                const CrewNote('Yeni meslek kod gerektirmez: bloklar ve düğmeler listeden seçilir. Reklam yasağı olan meslekleri (sağlık, hukuk) "Bilgilendirme profili" yap.'),
                for (final g in groups)
                  if (shown.any((p) => p.group == '${g['id']}'))
                    CrewListCard(
                      title: '${g['emoji']} ${g['label']}',
                      children: [
                        for (final p in shown.where((p) => p.group == '${g['id']}'))
                          ListTile(
                            leading: Text(p.emoji, style: const TextStyle(fontSize: 22)),
                            title: Text(p.label + (p.active ? '' : ' (kapalı)'), maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text([
                              if (p.licensed) 'lisanslı',
                              if (p.informational) 'bilgilendirme',
                              if (!p.flags.allowPrices) 'fiyat yok',
                              if (!p.flags.allowReviews) 'yorum yok',
                              if (!p.flags.allowBooking) 'randevu yok',
                              if (p.flags.allowBeforeAfter) 'öncesi–sonrası',
                              '${p.blocks.length} blok',
                              if (overrides.containsKey(p.id)) 'düzenlendi',
                              if (!defaults.contains(p.id)) 'özel',
                            ].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: CrewPill('${counts[p.id] ?? 0} profil'),
                            onTap: () => _edit(p, blocks, ctas, groups),
                          ),
                      ],
                    ),
                CrewCard(
                  title: 'Test kullanıcıları',
                  subtitle: 'Profesyonel profili olan test kullanıcılarını kendi meslekleriyle yeniden üretir: kapak, vitrin, genel profil (meslek, kurum, biyografi, ilgi alanları).',
                  icon: Icons.science_outlined,
                  action: TextButton.icon(
                    onPressed: () async {
                      if (!await crewConfirm(context, title: 'Test profilleri yenilensin mi?', message: 'Yalnızca test kullanıcılarının örnek verisi üzerine yazılır.')) return;
                      if (!context.mounted) return;
                      try {
                        final r = await _svc(context).adminSeedDummies(reseed: true);
                        if (context.mounted) crewToast(context, '${r.length} test profili yenilendi.');
                      } catch (e) {
                        if (context.mounted) crewToast(context, _err(e));
                      }
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Yenile'),
                  ),
                ),
                _BlocksCard(blocks: blocks, custom: asMap(cfg['customBlocks']), onSaved: _reload),
              ],
            ],
          );
        },
      );

  Future<void> _edit(ProProfession? p, List<ProBlockDef> blocks, List<ProCta> ctas, List<Map<String, Object?>> groups) async {
    final r = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => _ProfessionEditor(p: p, blocks: blocks, ctas: ctas, groups: groups)));
    if (r != null) await _reload();
  }
}

class _ConfigCard extends StatefulWidget {
  const _ConfigCard({super.key, required this.cfg, required this.onSaved});
  final Map<String, Object?> cfg;
  final Future<void> Function() onSaved;
  @override
  State<_ConfigCard> createState() => _ConfigCardState();
}

class _ConfigCardState extends State<_ConfigCard> {
  late bool _fourEyes = widget.cfg['fourEyes'] != false;
  late final _max = TextEditingController(text: '${widget.cfg['maxProfessions'] ?? 3}');
  late final _days = TextEditingController(text: '${widget.cfg['docRetentionDays'] ?? 30}');
  late final _rpd = TextEditingController(text: '${widget.cfg['requestsPerDay'] ?? 20}');
  bool _busy = false;

  @override
  void dispose() {
    _max.dispose();
    _days.dispose();
    _rpd.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await _svc(context).adminConfig({
        'fourEyes': _fourEyes,
        'maxProfessions': int.tryParse(_max.text.trim()) ?? 3,
        'docRetentionDays': int.tryParse(_days.text.trim()) ?? 30,
        'requestsPerDay': int.tryParse(_rpd.text.trim()) ?? 20,
      });
      if (mounted) crewToast(context, 'Ayarlar kaydedildi.');
      await widget.onSaved();
    } catch (e) {
      if (mounted) crewToast(context, _err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CrewCard(
        title: 'Ayarlar',
        icon: Icons.tune_rounded,
        action: FilledButton(onPressed: _busy ? null : _save, child: const Text('Kaydet')),
        children: [
          CrewSwitchRow(title: 'Dört göz', subtitle: 'Lisans onayı için iki farklı yetkili gerekir.', value: _fourEyes, onChanged: (v) => setState(() => _fourEyes = v)),
          CrewFormGrid(children: [
            TextField(controller: _max, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Üye başına en çok meslek', helperText: '1–5')),
            TextField(controller: _days, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Karar verilmeyen belge saklama', suffixText: 'gün', helperText: '3–90')),
            TextField(controller: _rpd, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Günlük talep sınırı (üye)', helperText: '1–200')),
          ]),
          const CrewNote('Hizmeti tamamen kapatmak için: Kurucu Paneli › Hizmetler › "Profesyonel profil".'),
        ],
      );
}

class _BlocksCard extends StatelessWidget {
  const _BlocksCard({required this.blocks, required this.custom, required this.onSaved});
  final List<ProBlockDef> blocks;
  final Map<String, Object?> custom;
  final Future<void> Function() onSaved;

  bool _isDefault(String key) => ProProfileService.builtinCatalog.block(key) != null;

  @override
  Widget build(BuildContext context) => CrewCard(
        title: 'Blok türleri',
        subtitle: 'Mesleklere eklenebilen bölümler; özel bloklar silinebilir.',
        icon: Icons.view_agenda_outlined,
        action: TextButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _BlockEditor(onSaved: onSaved))),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Özel blok'),
        ),
        children: [
          Wrap(spacing: CrewSpace.sm, runSpacing: CrewSpace.sm, children: [
            for (final b in blocks)
              InputChip(
                label: Text('${b.emoji} ${b.title} · ${b.type}${b.priced ? ' · ₺' : ''}${b.info ? ' · bilgi' : ''}'),
                onDeleted: custom.containsKey(b.key) && !_isDefault(b.key)
                    ? () async {
                        if (!await crewConfirm(context, title: '"${b.title}" bloğu silinsin mi?', danger: true, confirm: 'Sil')) return;
                        if (!context.mounted) return;
                        try {
                          await _svc(context).adminConfig({'blockKey': b.key, 'blockDelete': true});
                          await onSaved();
                        } catch (e) {
                          if (context.mounted) crewToast(context, _err(e));
                        }
                      }
                    : null,
              ),
          ]),
        ],
      );
}

class _BlockEditor extends StatefulWidget {
  const _BlockEditor({required this.onSaved});
  final Future<void> Function() onSaved;
  @override
  State<_BlockEditor> createState() => _BlockEditorState();
}

class _BlockEditorState extends State<_BlockEditor> {
  final _key = TextEditingController(), _title = TextEditingController(), _emoji = TextEditingController(text: '✨'), _hint = TextEditingController();
  String _type = 'list';
  bool _priced = false, _info = false, _busy = false;

  @override
  void dispose() {
    for (final c in [_key, _title, _emoji, _hint]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await _svc(context).adminConfig({
        'blockKey': _key.text.trim(),
        'blockDef': {'type': _type, 'title': _title.text.trim(), 'emoji': _emoji.text.trim(), 'hint': _hint.text.trim(), 'priced': _priced, 'info': _info},
      });
      await widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        crewToast(context, _err(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) => CrewPage(
        title: 'Özel blok',
        maxWidth: CrewWidth.form,
        bottomBar: CrewSaveBar(onSave: _save, busy: _busy, label: 'Ekle'),
        children: [
          CrewCard(children: [
            CrewFormGrid(children: [
              TextField(controller: _key, decoration: const InputDecoration(labelText: 'Anahtar', helperText: 'a-z, 0-9, _')),
              TextField(controller: _title, decoration: const InputDecoration(labelText: 'Başlık')),
              TextField(controller: _emoji, decoration: const InputDecoration(labelText: 'Emoji')),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Tür'),
                items: [for (final t in const ['about', 'text', 'tags', 'list', 'timeline', 'media', 'tracks', 'services', 'booking', 'offer']) DropdownMenuItem(value: t, child: Text(t))],
                onChanged: (v) => setState(() => _type = v ?? 'list'),
              ),
              CrewSpan.full(TextField(controller: _hint, decoration: const InputDecoration(labelText: 'İpucu (üyeye gösterilir)'))),
            ]),
            CrewSwitchRow(title: 'Fiyat girilebilir', value: _priced, onChanged: (v) => setState(() => _priced = v)),
            CrewSwitchRow(title: 'Bilgilendirme profilinde kullanılabilir', subtitle: 'Sağlık/hukuk profillerinde görünür.', value: _info, onChanged: (v) => setState(() => _info = v)),
          ]),
        ],
      );
}

class _ProfessionEditor extends StatefulWidget {
  const _ProfessionEditor({this.p, required this.blocks, required this.ctas, required this.groups});
  final ProProfession? p;
  final List<ProBlockDef> blocks;
  final List<ProCta> ctas;
  final List<Map<String, Object?>> groups;
  @override
  State<_ProfessionEditor> createState() => _ProfessionEditorState();
}

class _ProfessionEditorState extends State<_ProfessionEditor> {
  late final _id = TextEditingController(text: widget.p?.id ?? '');
  late final _label = TextEditingController(text: widget.p?.label ?? '');
  late final _emoji = TextEditingController(text: widget.p?.emoji ?? '✨');
  late final _spec = TextEditingController(text: widget.p?.specialties.join(', ') ?? '');
  late final _docs = TextEditingController(text: widget.p?.verifyDocs ?? '');
  late String _group = widget.p?.group ?? 'hizmet';
  late bool _licensed = widget.p?.licensed ?? false;
  late bool _info = widget.p?.informational ?? false;
  late bool _active = widget.p?.active ?? true;
  late ProFlags _f = widget.p?.flags ?? const ProFlags();
  late final List<String> _blocks = [...?widget.p?.blocks];
  late final List<String> _ctas = [...?widget.p?.ctas];
  bool _busy = false, _dirty = false;

  @override
  void dispose() {
    for (final c in [_id, _label, _emoji, _spec, _docs]) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(VoidCallback f) => setState(() {
        f();
        _dirty = true;
      });

  void _touch(String _) {
    if (!_dirty) setState(() => _dirty = true);
  }

  ProFlags _flags({bool? prices, bool? reviews, bool? booking, bool? ba}) => ProFlags(
      allowPrices: prices ?? _f.allowPrices, allowReviews: reviews ?? _f.allowReviews, allowBooking: booking ?? _f.allowBooking, allowBeforeAfter: ba ?? _f.allowBeforeAfter);

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await _svc(context).adminProfessionSave(_id.text.trim(), {
        'label': _label.text.trim(),
        'emoji': _emoji.text.trim(),
        'group': _group,
        'licensed': _licensed,
        'informational': _info,
        'active': _active,
        'flags': _f.toMap(),
        'blocks': _blocks,
        'ctas': _ctas,
        'specialties': [for (final s in _spec.text.split(',')) if (s.trim().isNotEmpty) s.trim()],
        'verifyDocs': _docs.text.trim(),
      });
      if (mounted) Navigator.pop(context, 'saved');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        crewToast(context, _err(e));
      }
    }
  }

  Future<void> _delete({bool reset = false}) async {
    final ok = await crewConfirm(
      context,
      title: reset ? 'Varsayılana döndürülsün mü?' : '"${widget.p!.label}" gizlensin mi?',
      message: reset ? 'Kurucu Paneli değişiklikleri silinir, kod varsayılanı geçerli olur.' : 'Meslek seçim listesinden kalkar; mevcut profiller etkilenmez ama yeni seçilemez.',
      danger: !reset,
    );
    if (!ok || !mounted) return;
    try {
      final s = _svc(context);
      reset ? await s.adminProfessionReset(widget.p!.id) : await s.adminProfessionDelete(widget.p!.id);
      if (mounted) Navigator.pop(context, 'deleted');
    } catch (e) {
      if (mounted) crewToast(context, _err(e));
    }
  }

  @override
  Widget build(BuildContext context) => CrewPage(
        title: widget.p == null ? 'Yeni meslek' : widget.p!.label,
        subtitle: widget.p?.id,
        maxWidth: CrewWidth.form,
        actions: [
          if (widget.p != null)
            PopupMenuButton<String>(
              onSelected: (v) => _delete(reset: v == 'reset'),
              itemBuilder: (_) => const [PopupMenuItem(value: 'reset', child: Text('Varsayılana döndür')), PopupMenuItem(value: 'delete', child: Text('Gizle / sil'))],
            ),
        ],
        bottomBar: CrewSaveBar(onSave: _save, dirty: _dirty || widget.p == null, busy: _busy),
        children: [
          CrewCard(title: 'Kimlik', children: [
            CrewFormGrid(children: [
              TextField(controller: _id, enabled: widget.p == null, decoration: const InputDecoration(labelText: 'Kimlik', helperText: 'a-z, 0-9, _'), onChanged: _touch),
              TextField(controller: _label, decoration: const InputDecoration(labelText: 'Ad'), onChanged: _touch),
              TextField(controller: _emoji, decoration: const InputDecoration(labelText: 'Emoji'), onChanged: _touch),
              DropdownButtonFormField<String>(
                initialValue: widget.groups.any((g) => g['id'] == _group) ? _group : null,
                decoration: const InputDecoration(labelText: 'Grup'),
                items: [for (final g in widget.groups) DropdownMenuItem(value: '${g['id']}', child: Text('${g['emoji']} ${g['label']}'))],
                onChanged: (v) => _set(() => _group = v ?? _group),
              ),
              CrewSpan.full(TextField(controller: _spec, decoration: const InputDecoration(labelText: 'Uzmanlık önerileri', helperText: 'Virgülle ayır'), onChanged: _touch)),
            ]),
            CrewSwitchRow(title: 'Etkin', subtitle: 'Kapalıysa üyeler bu mesleği seçemez.', value: _active, onChanged: (v) => _set(() => _active = v)),
          ]),
          CrewCard(title: 'Lisans ve reklam kuralları', icon: Icons.gavel_rounded, children: [
            CrewSwitchRow(title: 'Lisanslı', subtitle: 'Rozet ve mesleğe özgü bölümler belge doğrulanınca görünür.', value: _licensed, onChanged: (v) => _set(() => _licensed = v)),
            if (_licensed) TextField(controller: _docs, decoration: const InputDecoration(labelText: 'İstenen belgeler (üyeye gösterilir)'), onChanged: _touch),
            CrewSwitchRow(
              title: 'Bilgilendirme profili',
              subtitle: 'Sağlık/hukuk reklam yasağı: fiyat, kampanya, öncesi–sonrası ve yorum kapanır; sabit uyarı satırı görünür.',
              value: _info,
              onChanged: (v) => _set(() => _info = v),
            ),
          ]),
          CrewCard(title: 'İzinler', icon: Icons.toggle_on_outlined, children: [
            CrewSwitchRow(title: 'Fiyat gösterilebilir', value: _f.allowPrices, onChanged: (v) => _set(() => _f = _flags(prices: v))),
            CrewSwitchRow(title: 'Müşteri değerlendirmesi', value: _f.allowReviews, onChanged: (v) => _set(() => _f = _flags(reviews: v))),
            CrewSwitchRow(title: 'Randevu talebi', value: _f.allowBooking, onChanged: (v) => _set(() => _f = _flags(booking: v))),
            CrewSwitchRow(title: 'Öncesi–sonrası görseli', subtitle: 'Yalnızca danışanın yazılı onayıyla.', value: _f.allowBeforeAfter, onChanged: (v) => _set(() => _f = _flags(ba: v))),
          ]),
          CrewCard(title: 'Bloklar', subtitle: 'Sıra profildeki sıradır. Çıkarmak için ×, eklemek için alttakilere dokun.', icon: Icons.view_agenda_outlined, children: [
            Wrap(spacing: CrewSpace.sm, runSpacing: CrewSpace.sm, children: [
              for (final (i, k) in _blocks.indexed) InputChip(label: Text('${i + 1}. ${widget.blocks.where((b) => b.key == k).firstOrNull?.title ?? k}'), onDeleted: () => _set(() => _blocks.remove(k))),
            ]),
            if (_blocks.isEmpty) const CrewNote('Henüz blok yok. Aşağıdan ekle.'),
            Wrap(spacing: CrewSpace.sm, runSpacing: CrewSpace.sm, children: [
              for (final b in widget.blocks.where((b) => !_blocks.contains(b.key))) ActionChip(label: Text('+ ${b.emoji} ${b.title}'), onPressed: () => _set(() => _blocks.add(b.key))),
            ]),
          ]),
          CrewCard(title: 'Başlık düğmeleri', subtitle: 'Profilde en çok 4 düğme görünür (sıra seçim sırası).', icon: Icons.smart_button_outlined, children: [
            Wrap(spacing: CrewSpace.sm, runSpacing: CrewSpace.sm, children: [
              for (final c in widget.ctas)
                FilterChip(label: Text('${c.emoji} ${c.label}'), selected: _ctas.contains(c.id), onSelected: (on) => _set(() => on ? _ctas.add(c.id) : _ctas.remove(c.id))),
            ]),
          ]),
        ],
      );
}

// ================================================================== Kurucu Paneli › Test kullanıcıları: "Profesyonel profil" seçeneği

/// Test kullanıcısı oluşturma penceresindeki seçenek. [value]: null = profesyonel profil yok, [] = Rastgele, aksi hâlde seçilen
/// meslek kimlikleri. Aynı partide her üyeye farklı meslek verilir (sunucu: proProfile › adminSeedDummies).
class ProDummyPicker extends StatelessWidget {
  const ProDummyPicker({super.key, required this.value, required this.onChanged});
  final List<String>? value;
  final ValueChanged<List<String>?> onChanged;

  @override
  Widget build(BuildContext context) {
    final cat = ProProfileService.builtinCatalog;
    final v = value;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      CrewSwitchRow(
        title: 'Profesyonel profil',
        subtitle: 'Her üyeye farklı meslek; vitrin, hizmetler, takvim, değerlendirmeler dolu gelir (test verisi).',
        value: v != null,
        onChanged: (on) => onChanged(on ? const [] : null),
      ),
      if (v != null) ...[
        const SizedBox(height: CrewSpace.sm),
        Wrap(spacing: CrewSpace.sm, runSpacing: CrewSpace.sm, children: [
          ChoiceChip(label: const Text('Rastgele'), selected: v.isEmpty, showCheckmark: false, onSelected: (_) => onChanged(const [])),
          for (final p in cat.professions)
            FilterChip(
              label: Text('${p.emoji} ${p.label}'),
              selected: v.contains(p.id),
              onSelected: (on) => onChanged(on ? [...v, p.id] : [for (final x in v) if (x != p.id) x]),
            ),
        ]),
        const SizedBox(height: CrewSpace.sm),
        const CrewNote('Lisanslı meslekler test için doğrulanmış kurulur; sağlık/hukuk profilleri bilgilendirme kurallarıyla gelir.'),
      ],
    ]);
  }
}

/// Oluşturulan test kullanıcılarına profesyonel profil ekler; sonuç metnini döner.
Future<String> proSeedDummies(BuildContext context, {required int count, required List<String> professions, List<String>? uids}) async {
  final r = await ProProfileService.of(SessionScope.read(context).services)
      .adminSeedDummies(professions: professions, count: count, uids: uids == null || uids.isEmpty ? null : uids);
  if (r.isEmpty) return '';
  return ' Profesyonel profil: ${[for (final x in r) '${x.name} (${x.profession})'].join(', ')}.';
}

/// Test kullanıcısı silinmeden önce profesyonel verilerini temizler (hata olursa silmeyi durdurmaz).
Future<void> proDummyCleanup(BuildContext context, String uid) async {
  try {
    await ProProfileService.of(SessionScope.read(context).services).adminDummyCleanup(uid);
  } catch (_) {}
}
