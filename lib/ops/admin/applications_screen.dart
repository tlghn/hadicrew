import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:hadi/core/session.dart';
import 'package:hadi/data/candidate_models.dart';
import 'package:hadi/data/member_models.dart';
import 'package:hadi/data/models.dart';
import 'package:hadi/data/services.dart';
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/widgets/common.dart';
import 'package:hadi/features/fun/_placeholders.dart';
import 'package:hadi/features/candidate/candidate_profile.dart' show CandProfileReview;
import 'package:hadi/data/privacy_hub_service.dart' show PrivacyHubApi;
import 'package:hadi/core/ui_gate.dart';

/// Kurucu ve adminler için bekleyen başvurular (üye adayları) ve
/// değerlendirme paneli. Sözleşme: docs/aday_sozlesme.md (§6 Ajan E).
class ApplicationsScreen extends StatefulWidget {
  const ApplicationsScreen({super.key});

  @override
  State<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

enum _Filter { pending, flagged, referenced }

class _ApplicationsScreenState extends State<ApplicationsScreen> {
  Stream<List<_Cand>>? _stream;
  _Filter _filter = _Filter.pending;
  String? _selected;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= _watchCandidates(SessionScope.read(context).services);
  }

  List<_Cand> _apply(List<_Cand> all) => switch (_filter) {
        _Filter.pending => all,
        _Filter.flagged => all.where((c) => c.flags > 0).toList(),
        _Filter.referenced => all.where((c) => c.referenced).toList(),
      };

  void _open(_Cand c, bool wide) {
    if (wide) {
      setState(() => _selected = c.uid);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _ReviewPage(cand: c)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Üye adayları', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/salonlar'),
            icon: const Icon(Icons.forum_outlined, size: 20),
            label: const Text('Bekleme salonları'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: StreamBuilder<List<_Cand>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Başvurular yüklenemedi. Yetkin olduğundan emin ol.')));
          }
          if (!snap.hasData) return const RowsSkeleton();
          final all = snap.data!;
          if (all.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Image.asset('assets/logo/duo.webp', height: 90),
                const SizedBox(height: 16),
                Text('Bekleyen başvuru yok', style: Theme.of(context).textTheme.titleLarge),
              ]),
            );
          }
          final list = _apply(all);
          return LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 900;
            final listView = _buildList(context, all, list, wide);
            if (!wide) return listView;
            _Cand? sel;
            for (final c in all) {
              if (c.uid == _selected) sel = c;
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 360, child: listView),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 16, 16),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: sel == null
                        ? Center(
                            child: Text('Değerlendirmek için soldan bir aday seç.',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          )
                        : _ReviewPane(
                            key: ValueKey(sel.uid),
                            cand: sel,
                            embedded: true,
                            onDone: () => setState(() => _selected = null),
                          ),
                  ),
                ),
              ),
            ]);
          });
        },
      ),
    );
  }

  Widget _buildList(BuildContext context, List<_Cand> all, List<_Cand> list, bool wide) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final flagged = all.where((c) => c.flags > 0).length;
    final referenced = all.where((c) => c.referenced).length;
    Widget chip(_Filter f, String label) => ChoiceChip(
          label: Text(label),
          selected: _filter == f,
          showCheckmark: false,
          onSelected: (_) => setState(() => _filter = f),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Wrap(spacing: 8, runSpacing: 6, children: [
          chip(_Filter.pending, 'Bekleyen ${all.length}'),
          chip(_Filter.flagged, 'Notlu $flagged'),
          chip(_Filter.referenced, 'Referanslı $referenced'),
        ]),
        const SizedBox(height: 12),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('Bu filtrede başvuru yok.', style: text.bodyMedium?.copyWith(color: muted))),
          ),
        for (final c in list)
          Padding(
            key: identical(c, list.first) ? const ValueKey('t.apps.first') : null,
            padding: const EdgeInsets.only(bottom: 10),
            child: _CandRow(cand: c, selected: wide && c.uid == _selected, onTap: () => _open(c, wide)),
          ),
        const SizedBox(height: 4),
        Text('3 günü geçen başvurular kırmızı; yöneticilere günde bir hatırlatma gider.', style: text.bodySmall?.copyWith(color: muted)),
      ],
    );
  }
}

// ---------------------------------------------------------------- veri

/// Başvuru belgesi + aday akışının ek alanları (flags, vouch, intro…).
/// Ortak modele dokunmamak için ham belgeden burada okunur.
class _Cand {
  _Cand(this.app, {this.flags = 0, this.vouchStatus = '', this.vouchName = '', this.intro = '', this.quizPassed = false, this.announce = true});

  final PendingApplication app;
  final int flags;

  /// asked | yes | no | '' (yok)
  final String vouchStatus;
  final String vouchName;
  final String intro;
  final bool quizPassed;
  final bool announce;

  String get uid => app.uid;
  String get name => '${app.firstName} ${app.lastName}'.trim();
  bool get referenced => vouchStatus == 'yes' || app.hasReferral;

  static _Cand fromDoc(String id, Map<String, dynamic> m) {
    final vouch = _m(m['vouch']);
    final quiz = _m(m['rulesQuiz']);
    return _Cand(
      PendingApplication.fromMap(id, m),
      flags: _i(m['flags']),
      vouchStatus: _s(vouch['status']),
      vouchName: _s(vouch['name']),
      intro: _s(m['intro']),
      quizPassed: quiz['passed'] == true,
      announce: m['announce'] != false,
    );
  }
}

Stream<List<_Cand>> _watchCandidates(Services s) {
  if (s.isDemo) {
    return s.members.watchPendingApplications().map((l) => [for (final a in l) _Cand(a)]);
  }
  return FirebaseFirestore.instance.collection('applications').where('status', isEqualTo: 'pending').snapshots().map((snap) {
    final list = [for (final d in snap.docs) _Cand.fromDoc(d.id, d.data())];
    // Referanslılar üstte, sonra en eskiden yeniye.
    list.sort((a, b) {
      if (a.referenced != b.referenced) return a.referenced ? -1 : 1;
      return (a.app.createdAt ?? DateTime(2100)).compareTo(b.app.createdAt ?? DateTime(2100));
    });
    return list;
  });
}

Map<String, Object?> _m(Object? v) => v is Map ? v.map((k, x) => MapEntry('$k', x)) : <String, Object?>{};
List<Object?> _l(Object? v) => v is List ? v : const [];
int _i(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? 0 : 0);
String _s(Object? v) => v is String ? v : (v == null ? '' : '$v');

const _mon = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
String _two(int n) => n.toString().padLeft(2, '0');
String _shortDate(DateTime d) => '${d.day} ${_mon[d.month - 1]}';
String _shortDateTime(DateTime d) => '${_shortDate(d)} ${_two(d.hour)}:${_two(d.minute)}';

String _waitLabel(DateTime? c) {
  if (c == null) return '';
  final d = DateTime.now().difference(c);
  if (d.inHours < 1) return '${d.inMinutes < 1 ? 1 : d.inMinutes} dk';
  if (d.inHours < 24) return '${d.inHours} sa';
  return '${d.inDays} gün';
}

bool _isLate(DateTime? c) => c != null && DateTime.now().difference(c) > const Duration(days: 3);

// ---------------------------------------------------------------- liste satırı

class _CandRow extends StatelessWidget {
  const _CandRow({required this.cand, required this.selected, required this.onTap});
  final _Cand cand;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final a = cand.app;
    final overdue = _isLate(a.createdAt);
    final sub = [
      a.province,
      if (cand.referenced) 'referanslı',
      if (cand.flags > 0) '${cand.flags} not',
    ].where((x) => x.isNotEmpty).join(' · ');
    return Card(
      shape: selected
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: HadiColors.gold, width: 1.5))
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            _AppPhoto(photoPath: a.photoPath, size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(cand.name, style: text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (a.username.isNotEmpty)
                  Text('@${a.username}',
                      style: text.bodySmall?.copyWith(fontWeight: FontWeight.w800, color: HadiColors.text(HadiColors.gold)), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(sub, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(width: 8),
            Text(
              _waitLabel(a.createdAt),
              style: text.bodySmall?.copyWith(fontWeight: FontWeight.w800, color: overdue ? HadiColors.error : scheme.onSurfaceVariant),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(99)),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: HadiColors.readableOn(color, Color.alphaBlend(color.withValues(alpha: .14), HadiColors.card)))),
      );
}

class _AppPhoto extends StatefulWidget {
  const _AppPhoto({super.key, required this.photoPath, required this.size, this.url});
  final String photoPath;
  final double size;

  /// Hazır adres (ör. guests/{uid}.photoUrl) varsa Storage'a sorulmaz.
  final String? url;

  @override
  State<_AppPhoto> createState() => _AppPhotoState();
}

class _AppPhotoState extends State<_AppPhoto> {
  Future<String?>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final url = widget.url;
    _future ??= url != null && url.isNotEmpty
        ? Future<String?>.value(url)
        : SessionScope.read(context).services.members.applicationPhotoUrl(widget.photoPath);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return FutureBuilder<String?>(
      future: _future,
      builder: (context, snap) {
        final url = snap.data;
        return ClipRRect(
          borderRadius: BorderRadius.circular(size / 2),
          child: Container(
            width: size,
            height: size,
            color: HadiColors.mist,
            child: url == null
                ? Icon(Icons.person_rounded, color: HadiColors.ink3)
                : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => Icon(Icons.person_rounded, color: HadiColors.ink3)),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- değerlendirme

class _ReviewPage extends StatelessWidget {
  const _ReviewPage({required this.cand});
  final _Cand cand;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(cand.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
        body: SafeArea(child: _ReviewPane(cand: cand, embedded: false)),
      );
}

/// Onay diyaloğu: onaylanırsa yönetim notu ('' olabilir), vazgeçilirse null.
Future<String?> _askApproveNote(BuildContext context, String firstName) async {
  final noteCtrl = TextEditingController();
  final ok = await uiOnce(context, () => showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(scrollable: true, 
      title: const Text('Başvuruyu onayla'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${firstName.isEmpty ? 'Aday' : firstName} kulübe katılacak ve hemen bildirim alacak.'),
        const SizedBox(height: 12),
        TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Yönetim notu (isteğe bağlı)')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text('Onayla', style: TextStyle(color: HadiColors.text(HadiColors.dostluk))),
        ),
      ],
    ),
  ));
  final note = noteCtrl.text.trim();
  // Diyalog kapanış animasyonu bitene kadar TextField denetleyiciyi kullanır.
  Future<void>.delayed(const Duration(milliseconds: 500), noteCtrl.dispose);
  return ok == true ? note : null;
}

/// Ret diyaloğu: gerekçe ya da vazgeçilirse null.
Future<String?> _askRejectNote(BuildContext context, String firstName) =>
    uiOnce(context, () => showDialog<String>(context: context, builder: (_) => _RejectDialog(name: firstName.isEmpty ? 'Aday' : firstName)));

/// Başka ekranlardan (ör. salondaki "Aday özeti") başvurunun değerlendirme sayfasını açar.
Future<void> openApplicationReview(BuildContext context, String uid) async {
  final s = SessionScope.read(context).services;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final nav = Navigator.of(context);
  _Cand? cand;
  try {
    if (s.isDemo) {
      final list = await s.members.watchPendingApplications().first;
      for (final a in list) {
        if (a.uid == uid) cand = _Cand(a);
      }
    } else {
      final d = await FirebaseFirestore.instance.collection('applications').doc(uid).get();
      final data = d.data();
      if (data != null) cand = _Cand.fromDoc(d.id, data);
    }
  } catch (_) {
    cand = null;
  }
  if (cand == null) {
    messenger?.showSnackBar(const SnackBar(content: Text('Başvuru açılamadı.')));
    return;
  }
  final c = cand;
  await nav.push(MaterialPageRoute<void>(builder: (_) => _ReviewPage(cand: c)));
}

/// Onayla / Reddet kısayolu (değerlendirme sayfasıyla aynı diyaloglar ve `decideApplication`).
/// Karar verildiyse true. Yetki: kurucu ve adminler (sunucu da denetler).
Future<bool> decideApplicationFlow(BuildContext context, {required String uid, required String firstName, required bool approve}) async {
  final note = approve ? await _askApproveNote(context, firstName) : await _askRejectNote(context, firstName);
  if (note == null || !context.mounted) return false;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await SessionScope.read(context).services.members.decideApplication(uid, approve: approve, note: note);
    HapticFeedback.mediumImpact();
    messenger?.showSnackBar(SnackBar(content: Text(approve ? 'Başvuru onaylandı.' : 'Başvuru reddedildi.')));
    return true;
  } on AppFailure catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
}

class _ReviewPane extends StatefulWidget {
  const _ReviewPane({super.key, required this.cand, required this.embedded, this.onDone});
  final _Cand cand;

  /// Geniş ekranda sağ panel (true) ya da tam ekran sayfa (false).
  final bool embedded;
  final VoidCallback? onDone;

  @override
  State<_ReviewPane> createState() => _ReviewPaneState();
}

class _ReviewPaneState extends State<_ReviewPane> {
  Future<Map<String, Object?>>? _future;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_future == null) unawaited(PrivacyHubApi.instance.caseOpen('application', widget.cand.uid)); // Verime erişim günlüğü (açılış)
    _future ??= _load();
  }

  Future<Map<String, Object?>> _load() => SessionScope.read(context).services.candidates.review(widget.cand.uid);

  void _retry() => setState(() { _future = _load(); });

  Future<void> _approve() async {
    final note = await _askApproveNote(context, widget.cand.app.firstName);
    if (note == null || !mounted) return;
    await _decide(true, note);
  }

  Future<void> _reject() async {
    final note = await _askRejectNote(context, widget.cand.app.firstName);
    if (note == null || !mounted) return;
    await _decide(false, note);
  }

  Future<void> _decide(bool approve, String note) async {
    setState(() => _busy = true);
    try {
      await SessionScope.read(context).services.members.decideApplication(widget.cand.uid, approve: approve, note: note);
      HapticFeedback.mediumImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(approve ? 'Başvuru onaylandı.' : 'Başvuru reddedildi.')));
        if (widget.embedded) {
          widget.onDone?.call();
        } else {
          Navigator.pop(context);
        }
      }
    } on AppFailure catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, Object?>>(
      future: _future,
      builder: (context, snap) {
        final r = snap.data;
        final announce = r == null ? widget.cand.announce : _m(r['app'])['announce'] != false;
        return Column(children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _Header(cand: widget.cand, review: r),
                  const SizedBox(height: 16),
                  if (snap.hasError)
                    _LoadError(onRetry: _retry)
                  else if (r == null)
                    const RowsSkeleton(count: 4, shrink: true)
                  else
                    _ReviewBody(cand: widget.cand, review: r, width: box.maxWidth - 40),
                ],
              ),
            ),
          ),
          _ActionBar(busy: _busy, announce: announce, onApprove: _approve, onReject: _reject),
        ]);
      },
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const InfoNote(
          icon: Icons.error_outline_rounded,
          color: HadiColors.error,
          text: 'Değerlendirme dosyası yüklenemedi. Başvuruyu yine de onaylayabilir ya da reddedebilirsin.',
        ),
        const SizedBox(height: 8),
        TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Tekrar dene')),
      ]);
}

class _Header extends StatelessWidget {
  const _Header({required this.cand, required this.review});
  final _Cand cand;
  final Map<String, Object?>? review;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final a = cand.app;
    final ra = _m(review?['app']);
    final guest = _m(review?['guest']);
    final birthYear = a.birthYear > 0 ? a.birthYear : _i(ra['birthYear']);
    final interests = a.interests.isNotEmpty ? a.interests : [for (final x in _l(ra['interests'])) _s(x)];
    final province = a.province.isNotEmpty ? a.province : (_s(ra['province']).isNotEmpty ? _s(ra['province']) : _s(guest['province']));
    final created = a.createdAt ?? candDate(ra['createdAt']);
    final intro = cand.intro.isNotEmpty ? cand.intro : _s(ra['intro']);
    final name = cand.name.isNotEmpty ? cand.name : _s(guest['name']);
    final handle = (a.username.isNotEmpty ? a.username : _s(ra['username'])).replaceFirst('@', '');
    final photoUrl = _s(guest['photoUrl']);
    final meta = [
      if (birthYear > 0) '${DateTime.now().year - birthYear}',
      province,
      interests.join(', '),
      if (created != null) 'Başvuru ${_shortDate(created)}',
    ].where((x) => x.isNotEmpty).join(' · ');

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _AppPhoto(
          key: ValueKey(photoUrl.isEmpty ? a.photoPath : photoUrl),
          photoPath: a.photoPath,
          url: photoUrl.isEmpty ? null : photoUrl,
          size: 68,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: text.titleLarge),
            if (handle.isNotEmpty) ...[
              const SizedBox(height: 4),
              // Seçilen kullanıcı adı: başvuru süresince ayrılmış; onayda kesinleşir, retle serbest kalır.
              Semantics(
                label: 'Seçilen kullanıcı adı $handle, ayrıldı',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: HadiColors.gold.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: HadiColors.gold.withValues(alpha: .5)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                      child: Text('@$handle',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w900, color: HadiColors.text(HadiColors.gold))),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.lock_outline_rounded, size: 14, color: HadiColors.readableOn(HadiColors.gold, Color.alphaBlend(HadiColors.gold.withValues(alpha: .14), HadiColors.card), 3)),
                    const SizedBox(width: 2),
                    Text('ayrıldı', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: HadiColors.text(HadiColors.gold))),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 4),
            if (meta.isNotEmpty) Text(meta, style: text.bodySmall?.copyWith(color: muted)),
            if (intro.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('"$intro"', style: text.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (a.hasReferral) _Tag('Referans: ${a.referral}', HadiColors.dostluk),
              if (!a.identityVerified) const _Tag('Kimlik doğrulanmadı', HadiColors.heyecan),
            ]),
          ]),
        ),
      ]),
      if (!a.identityVerified) ...[
        const SizedBox(height: 12),
        const InfoNote(
          icon: Icons.warning_amber_rounded,
          color: HadiColors.heyecan,
          text: 'Kimlik nüfus kaydıyla otomatik doğrulanamadı (servis erişilemedi). Onaylamadan önce kişiyi tanıdığından emin ol.',
        ),
      ],
    ]);
  }
}

class _ReviewBody extends StatelessWidget {
  const _ReviewBody({required this.cand, required this.review, required this.width});
  final _Cand cand;
  final Map<String, Object?> review;
  final double width;

  @override
  Widget build(BuildContext context) {
    final a = cand.app;
    final ra = _m(review['app']);
    final guest = _m(review['guest']);
    final stats = _m(review['stats'] ?? ra['stats']);
    final progress = _m(review['progress']);
    final vouch = _m(review['vouch'] ?? ra['vouch']);
    final flags = [for (final f in _l(review['flags'])) CandFlag.fromMap(_m(f))];
    final botNotes = [for (final n in _l(review['botNotes'])) CandBotNote.fromMap(_m(n))];
    final suggestions = [for (final s in _l(review['suggestions'])) _m(s)];
    final summary = _s(review['summary']).trim();

    // Profil görevleri: fotoğraf, ilgi alanları, tanıtım, kural testi, referans.
    final photo = a.photoPath.isNotEmpty || _s(guest['photoUrl']).isNotEmpty || _s(ra['photoPath']).isNotEmpty;
    final interests = a.interests.isNotEmpty || _l(ra['interests']).isNotEmpty;
    final intro = cand.intro.isNotEmpty || _s(ra['intro']).isNotEmpty;
    final quiz = cand.quizPassed || _m(ra['rulesQuiz'])['passed'] == true;
    final vouchStatus = _s(vouch['status']).isNotEmpty ? _s(vouch['status']) : cand.vouchStatus;
    final tasksDone = [photo, interests, intro, quiz, vouchStatus == 'yes'].where((x) => x).length;

    final games = progress.containsKey('games') ? _i(progress['games']) : _i(stats['games']);
    final suggestionCount = suggestions.isNotEmpty ? suggestions.length : _i(stats['suggestions']);

    final tiles = [
      _StatTile(value: '$tasksDone/5', label: 'Profil görevleri'),
      _StatTile(value: quiz ? '3/3' : '—', label: 'Kural testi'),
      _StatTile(value: '${_i(stats['msgs'])}', label: 'Salon mesajı'),
      _StatTile(value: '$games', label: 'Oyun · ${_i(stats['leaves'])} masa terk'),
      _StatTile(value: '$suggestionCount', label: 'Etkinlik önerisi'),
    ];
    final cols = width >= 640 ? 5 : 3;
    final tileW = (width - (cols - 1) * 8) / cols;

    final left = <Widget>[
      _FlagsSection(flags: flags),
      const SizedBox(height: 20),
      _SummarySection(summary: summary, msgs: _i(stats['msgs'])),
      const SizedBox(height: 20),
      _BotNotesSection(notes: botNotes),
    ];
    final right = <Widget>[
      _VouchSection(vouch: vouch, cand: cand, reports: _i(stats['reports'])),
      const SizedBox(height: 20),
      _SuggestionsSection(items: suggestions),
    ];
    final twoCols = width >= 700;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [for (final t in tiles) SizedBox(width: tileW, child: t)]),
      const SizedBox(height: 20),
      // Adayın "Profilim"de eklediği fotoğraflar ve sertifikalar (candProfile get).
      CandProfileReview(key: ValueKey('candProfile-${cand.uid}'), uid: cand.uid),
      const SizedBox(height: 20),
      if (twoCols)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: left)),
          const SizedBox(width: 20),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: right)),
        ])
      else ...[
        ...left,
        const SizedBox(height: 20),
        ...right,
      ],
    ]);
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class _Box extends StatelessWidget {
  const _Box({required this.child, this.color});
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color ?? Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );
}

/// "Uyarı" notları için kehribar ton.
const _amber = HadiColors.gold;

class _FlagsSection extends StatelessWidget {
  const _FlagsSection({required this.flags});
  final List<CandFlag> flags;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionTitle('Yapay zekâ notları (${flags.length})'),
      if (flags.isEmpty) _Box(child: Text('Not yok.', style: text.bodyMedium)),
      for (final f in flags)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _Box(
            color: (f.sev == 'blocked' ? HadiColors.error : _amber).withValues(alpha: .12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _Tag(f.sev == 'blocked' ? 'Engellendi' : 'Uyarı', f.sev == 'blocked' ? HadiColors.error : _amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(f.kindLabel,
                      style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: f.sev == 'blocked' ? HadiColors.error : _amber)),
                ),
                if (f.at != null) Text(_shortDateTime(f.at!), style: text.bodySmall),
              ]),
              const SizedBox(height: 6),
              Text(f.text, style: text.bodyMedium?.copyWith(fontFamily: 'monospace')),
              if (f.detail.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(f.detail, style: text.bodySmall?.copyWith(color: muted)),
              ],
            ]),
          ),
        ),
      const _Caption('Notlar bilgi amaçlı; kararı sen verirsin. Aday aynı notları kendi ekranında görür.'),
    ]);
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.summary, required this.msgs});
  final String summary;
  final int msgs;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final empty = msgs > 0 ? 'Özet hazırlanıyor…' : 'Özet yok: aday salonda henüz yazmadı.';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionTitle('Salon özeti'),
      _Box(child: Text(summary.isNotEmpty ? summary : empty, style: text.bodyMedium?.copyWith(height: 1.4))),
      const _Caption('Yapay zekâ özeti · bilgi amaçlı'),
    ]);
  }
}

/// HADİ Rehber botunun sohbetten çıkardığı notlar (`review` → `botNotes`).
class _BotNotesSection extends StatelessWidget {
  const _BotNotesSection({required this.notes});
  final List<CandBotNote> notes;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionTitle("HADİ Rehber'in notları (${notes.length})"),
      if (notes.isEmpty) _Box(child: Text('Not yok.', style: text.bodyMedium)),
      for (final n in notes)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _Box(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _Tag(n.topicLabel, HadiColors.aktivite),
                const Spacer(),
                if (n.at != null) Text(_shortDateTime(n.at!), style: text.bodySmall),
              ]),
              if (n.text.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(n.text, style: text.bodyMedium?.copyWith(height: 1.4)),
              ],
            ]),
          ),
        ),
      const _Caption('🤖 Yapay zekâ botu sohbetten çıkardı · bilgi amaçlı. Aday bu notları kendi ekranında görür.'),
    ]);
  }
}

class _VouchSection extends StatelessWidget {
  const _VouchSection({required this.vouch, required this.cand, required this.reports});
  final Map<String, Object?> vouch;
  final _Cand cand;
  final int reports;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final name = _s(vouch['name']).isNotEmpty ? _s(vouch['name']) : cand.vouchName;
    final status = _s(vouch['status']).isNotEmpty ? _s(vouch['status']) : cand.vouchStatus;
    final statusText = switch (status) {
      'yes' => '"Tanıyorum" dedi',
      'no' => '"Tanımıyorum" dedi',
      'asked' => 'cevap bekleniyor',
      _ => '',
    };
    final Color? color = switch (status) {
      'yes' => HadiColors.dostluk,
      'no' => HadiColors.error,
      _ => null,
    };
    final Widget vouchBox;
    if (name.isNotEmpty) {
      vouchBox = _Box(
        color: color?.withValues(alpha: .12),
        child: Row(children: [
          Icon(status == 'yes' ? Icons.verified_rounded : Icons.person_search_rounded, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w800)),
                if (statusText.isNotEmpty) TextSpan(text: ' $statusText'),
              ]),
              style: text.bodyMedium,
            ),
          ),
        ]),
      );
    } else if (cand.app.hasReferral) {
      vouchBox = _Box(child: Text('Başvuruda referans: ${cand.app.referral}', style: text.bodyMedium));
    } else {
      vouchBox = _Box(child: Text('Referans yok.', style: text.bodyMedium));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionTitle('Referans ve şikayet'),
      vouchBox,
      const SizedBox(height: 8),
      _Box(
        color: reports > 0 ? HadiColors.error.withValues(alpha: .12) : null,
        child: Text(reports > 0 ? '$reports şikayet' : 'Şikayet yok', style: text.bodyMedium),
      ),
    ]);
  }
}

class _SuggestionsSection extends StatelessWidget {
  const _SuggestionsSection({required this.items});
  final List<Map<String, Object?>> items;

  static String _sub(Map<String, Object?> m) {
    for (final k in const ['desc', 'description', 'detail', 'note', 'text']) {
      final v = _s(m[k]).trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionTitle('Etkinlik önerisi'),
      if (items.isEmpty) _Box(child: Text('Öneri yok.', style: text.bodyMedium)),
      for (final s in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _Box(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_s(s['title']).isEmpty ? 'Adsız öneri' : _s(s['title']), style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              if (_sub(s).isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(_sub(s), style: text.bodySmall?.copyWith(color: muted), maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 6),
              const _Tag('Üye Adayı Önerisi', HadiColors.aktivite),
            ]),
          ),
        ),
    ]);
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.busy, required this.announce, required this.onApprove, required this.onReject});
  final bool busy;
  final bool announce;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          'Ret gerekçesi adaya gösterilmez; kayıtta kalır. Adayın tercihi: salonda duyurulmak ${announce ? '✓' : '✗'}',
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: busy ? null : onReject, child: const Text('Reddet…'))),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: HadiColors.fillForWhite(HadiColors.dostluk), foregroundColor: Colors.white),
              onPressed: busy ? null : onApprove,
              child: busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('Onayla'),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------- ret

class _RejectDialog extends StatefulWidget {
  const _RejectDialog({required this.name});
  final String name;

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  static const _reasons = [
    'Kimlik doğrulanamadı',
    'Topluluk kurallarına uymayan davranış',
    'Profil eksik',
    'Diğer',
  ];
  String? _reason;
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _valid => _reason != null && (_reason != 'Diğer' || _ctrl.text.trim().isNotEmpty);

  String get _note {
    final extra = _ctrl.text.trim();
    final reason = _reason ?? '';
    if (reason == 'Diğer') return 'Diğer: $extra';
    return extra.isEmpty ? reason : '$reason: $extra';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(scrollable: true, 
      title: const Text('Başvuruyu reddet'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${widget.name} için ret gerekçesi seç.', style: text.bodyMedium),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final r in _reasons)
              ChoiceChip(
                label: Text(r),
                selected: _reason == r,
                showCheckmark: false,
                onSelected: (_) => setState(() => _reason = r),
              ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            maxLines: 3,
            minLines: 1,
            maxLength: 300,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: _reason == 'Diğer' ? 'Gerekçe' : 'Ek not (isteğe bağlı)'),
          ),
          Text(
            'Ret gerekçesi adaya gösterilmez; kayıtta kalır. Aday 30 gün sonra yeniden başvurabilir.',
            style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        TextButton(
          onPressed: _valid ? () => Navigator.pop(context, _note) : null,
          child: Text('Reddet', style: TextStyle(color: _valid ? HadiColors.error : null)),
        ),
      ],
    );
  }
}
