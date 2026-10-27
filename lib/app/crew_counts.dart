// HADİ Crew — rozet sayıları: TEK KAYNAK (27 Ekim 2026, kurucu 04:45: "rozet/bildirim sayıları anında güncellenmiyor").
//
// Kök neden (düzeltildi): sayılar yalnız Pano ekranının içindeki 60 sn'lik zamanlayıcıyla çekiliyordu. Bir bölüm açılınca
// Pano kapanır, zamanlayıcı durur; kenar menü / Kuyruklar / Son kullanılanlar rozetleri Pano yeniden açılana kadar son
// değerde DONUYORDU ve bir sayfada yapılan işlem (onay/ret/kapatma) sayıları hiç tazelemiyordu. Ayrıca bazı rozetler sayfanın
// listesiyle aynı şeyi saymıyordu (İşletmeler: başvuru + etkinlik toplamı ama sekmelerde rozet yok, Ödemeler/Anlaşmazlıklar
// hiç sayılmıyordu; Moderasyon kuyruğu ham şikâyet sayısı ↔ hedef başına satır; Destek "open" ↔ "ekip yanıtı bekleyen").
//
// Şimdi: [CrewCounts] oturum boyunca yaşar ve sayıları `crewDash › counts` ile çeker —
//   · açılışta, her bölüme girişte, pencere/sekme odağa dönünce (uygulama yaşam döngüsü "resumed"),
//   · 30 sn'de bir (pencere arka plandayken durur),
//   · başarılı HER yazma işleminden hemen sonra (HadiCallable.onSuccess; okuma op'ları sayılmaz) — bilinen karar op'larında
//     ilgili sayaç önce iyimser olarak 1 düşer ([kResolveOps]), ardından sunucudan doğrusu gelir;
//   · bir sekme listesini yüklediğinde liste tamsa (sınırın altında) sayaç listeye eşitlenir ([reconcile]).
// Kenar menü, Kuyruklar (toplam = görünen bölüm rozetlerinin toplamı), Son kullanılanlar, kategori içi rozetler, sekme
// rozetleri ([CountTab]) ve Pano hep [crewDashNotifier]'ı dinler. Firestore anlık dinleyici kullanılmaz: sayılar yetkiye göre
// sunucuda (Admin SDK, count()) hesaplanır; istemci kuralları bu koleksiyonların çoğunu okumaya izin vermez.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hadi/data/callables.dart' show HadiCallable;
import 'package:hadi/theme/hadi_colors.dart';

import 'crew_api.dart';

/// Rozetlerin ve Pano'nun dinlediği son sayılar (oturum başına; çıkışta temizlenir).
final ValueNotifier<CrewDash?> crewDashNotifier = ValueNotifier<CrewDash?>(null);

/// Karar işlemi → düşecek sayaç (iyimser güncelleme). Anahtar: `{callable}:{op}` (callable = eski fonksiyon adı).
/// Burada olmayan yazma işlemleri de sayaçları hemen yeniden çektirir; bu tablo yalnız sayının BEKLEMEDEN düşmesi içindir.
const Map<String, String> kResolveOps = {
  'business:approve': 'businessApps',
  'business:reject': 'businessApps',
  'business:eventApprove': 'businessEvents',
  'business:eventReject': 'businessEvents',
  'business:payoutPaid': 'businessPayouts',
  'business:payoutReject': 'businessPayouts',
  'business:orderResolve': 'businessDisputes',
  'courier:decide': 'courierApps',
  'courier:caseResolve': 'courierCases',
  'courier:payoutPaid': 'courierPayouts',
  'courier:payoutReject': 'courierPayouts',
};

/// Okuma op'ları (liste, ayrıntı, ayar okuma…): sayaç tazelemesi tetiklemez. Bilinmeyen op yazma sayılır.
final RegExp _readOp = RegExp(
  r'^(get|list|load|fetch|status|config|stats|search|queue|appeals|cases|mine|view|docs|thread|csat|canned|gaps|pending|presort|claim|preview|history|log|export|count|dash|panelSearch)'
  r'|(List|Get|Pending|Docs|Shots|Mine|Stats|View|Config|Disputes|Queue|Search|Preview|History|Log|Export|Count)$',
);

/// Çağrı bir okuma mı (rozet tazelemesi gerekmez)?
bool isReadCall(String name, Object? params) {
  if (name == 'crewDash') return true;
  final op = params is Map ? '${params['op'] ?? params['action'] ?? ''}' : '';
  return op.isNotEmpty && _readOp.hasMatch(op);
}

/// Sayı yükleyici (testlerde değiştirilir).
typedef CrewCountsFetch = Future<CrewDash> Function();

class CrewCounts with WidgetsBindingObserver {
  CrewCounts._();
  static final CrewCounts instance = CrewCounts._();

  static const Duration pollEvery = Duration(seconds: 30);
  static const Duration afterAction = Duration(milliseconds: 350);

  CrewCountsFetch? _fetch;
  String? _owner;
  Timer? _timer, _soon;
  bool _busy = false, _again = false, _visible = true;

  /// Yerel (iyimser) değişiklik sayacı: bir istek uçarken yerel düşüş olduysa o isteğin (eski) sonucu yazılmaz.
  int _localSeq = 0;

  bool get running => _fetch != null;

  /// Oturum için başlatır (idempotent). Kullanıcı değişirse önceki sayılar silinir.
  void ensureStarted(String? owner, CrewCountsFetch fetch) {
    if (_fetch != null && _owner == owner) return;
    if (_owner != owner) crewDashNotifier.value = null;
    _owner = owner;
    _fetch = fetch;
    if (_timer == null) {
      WidgetsBinding.instance.addObserver(this);
      HadiCallable.onSuccess = onCallSuccess;
      _timer = Timer.periodic(pollEvery, (_) {
        if (_visible) refresh();
      });
    }
    refresh();
  }

  /// Çıkış / testler: her şeyi durdurur ve sayıları siler.
  void stop() {
    _timer?.cancel();
    _soon?.cancel();
    _timer = _soon = null;
    if (_fetch != null) WidgetsBinding.instance.removeObserver(this);
    if (HadiCallable.onSuccess == onCallSuccess) HadiCallable.onSuccess = null;
    _fetch = null;
    _owner = null;
    _busy = _again = false;
    _visible = true;
    crewDashNotifier.value = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final was = _visible;
    _visible = state == AppLifecycleState.resumed;
    // Pencere / sekme odağa döndü: hemen tazele.
    if (_visible && !was) refresh();
  }

  /// Sunucudan şimdi çek (uçan istek varsa bitince bir kez daha).
  Future<void> refresh() async {
    final f = _fetch;
    if (f == null) return;
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    final seq = _localSeq;
    try {
      final d = await f();
      // İstek uçarken yerel bir karar düştüyse bu sonuç eskidir; hemen ardından gelen tazeleme doğrusunu yazar.
      if (seq == _localSeq && identical(f, _fetch)) apply(d);
    } catch (_) {
      // Rozet yalnızca bilgi; hata sessiz (bölüm kendi hatasını gösterir). Son bilinen sayılar kalır.
    } finally {
      _busy = false;
      if (_again) {
        _again = false;
        refreshSoon(Duration.zero);
      }
    }
  }

  /// Kısa gecikmeyle tazele (art arda işlemler tek isteğe toplanır).
  void refreshSoon([Duration delay = afterAction]) {
    if (_fetch == null) return;
    _soon?.cancel();
    _soon = Timer(delay, refresh);
  }

  /// Sunucu yanıtını yazar. `counts` op'u (partial) yalnız kuyrukları getirir: topluluk sayıları ve seriler korunur.
  void apply(CrewDash d) {
    final old = crewDashNotifier.value;
    if (d.partial && old != null) {
      crewDashNotifier.value = CrewDash(
        access: d.access,
        role: d.role,
        counts: {...old.counts, ...d.counts},
        series: old.series,
        at: d.at,
      );
    } else {
      crewDashNotifier.value = d;
    }
  }

  /// İyimser güncelleme: [key] sayacını [delta] kadar değiştirir (0'ın altına inmez). Sayaç bilinmiyorsa dokunmaz.
  void bump(String key, [int delta = -1]) {
    final d = crewDashNotifier.value;
    final v = d?.counts[key];
    if (d == null || v == null) return;
    _localSeq++;
    crewDashNotifier.value = d.withCount(key, (v + delta).clamp(0, 1 << 30));
  }

  /// Bir sekme listesini yükledi: liste tamsa ([complete]: sınıra ulaşmadı) rozet listeyle aynı olur.
  void reconcile(String key, int listed, {bool complete = true}) {
    final d = crewDashNotifier.value;
    if (d == null || !complete || !d.counts.containsKey(key) || d.counts[key] == listed) return;
    _localSeq++;
    crewDashNotifier.value = d.withCount(key, listed);
  }

  /// HadiCallable.onSuccess: yazma işleminden sonra sayaçları düşür ve yeniden çek.
  void onCallSuccess(String name, Object? params) {
    if (_fetch == null || isReadCall(name, params)) return;
    final op = params is Map ? '${params['op'] ?? ''}' : '';
    final key = kResolveOps['$name:$op'];
    if (key != null) bump(key);
    refreshSoon();
  }
}

/// Bölüm / sekme rozeti: [keys] sayaçlarının toplamı (hiçbiri bilinmiyorsa null).
int? sumCounts(CrewDash? d, List<String> keys) {
  if (d == null || keys.isEmpty) return null;
  int? t;
  for (final k in keys) {
    final v = d.counts[k];
    if (v != null) t = (t ?? 0) + v;
  }
  return t;
}

/// Kuyruklar toplamı: kuyruk bölümlerinin sayaç listelerinden (her sayaç bir kez). Bölüm rozetlerinin toplamıyla aynıdır.
int queueTotalOf(Iterable<List<String>> queueKeys, CrewDash? d) {
  if (d == null) return 0;
  final keys = <String>{for (final k in queueKeys) ...k};
  return sumCounts(d, keys.toList()) ?? 0;
}

/// Küçük sayı hapı (0 ya da bilinmiyorsa çizilmez).
class CountPill extends StatelessWidget {
  const CountPill(this.n, {super.key});
  final int n;

  @override
  Widget build(BuildContext context) {
    final f = HadiColors.brandFill(HadiColors.heyecan);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(color: f.bg, borderRadius: BorderRadius.circular(99)),
      child: Text(n > 99 ? '99+' : '$n', style: TextStyle(color: f.fg, fontWeight: FontWeight.w800, fontSize: 11.5)),
    );
  }
}

/// Sekme başlığı + bekleyen iş rozeti ("Başvurular 1", "Anlaşmazlıklar 1"). Sayılar [crewDashNotifier]'dan; Crew dışında
/// (sayı yoksa) yalnız başlık görünür.
class CountTab extends StatelessWidget {
  const CountTab({super.key, required this.text, this.keys = const []});
  final String text;
  final List<String> keys;

  @override
  Widget build(BuildContext context) {
    if (keys.isEmpty) return Tab(text: text);
    return Tab(
      child: ValueListenableBuilder<CrewDash?>(
        valueListenable: crewDashNotifier,
        builder: (context, d, _) {
          final n = sumCounts(d, keys) ?? 0;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            Text(text),
            if (n > 0) ...[const SizedBox(width: 6), CountPill(n, key: ValueKey('tab-count-$text'))],
          ]);
        },
      ),
    );
  }
}
