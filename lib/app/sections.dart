import 'package:flutter/material.dart';
import 'package:hadi/core/capabilities.dart';
import 'package:hadi/core/session.dart';

import '../ops/admin/ai_security_admin.dart' show AiSecurityAdminTab;
import '../ops/admin/ai_video_admin.dart' show AiVideoAdminTab;
import '../ops/admin/applications_screen.dart' show ApplicationsScreen;
import '../ops/admin/business_admin.dart' show BusinessAdminTab;
import '../ops/admin/courier_admin.dart' show CourierAdminTab;
import '../ops/admin/id_review_admin.dart' show IdReviewAdminTab;
import '../ops/admin/live_reports_screen.dart' show LiveReportsScreen;
import '../ops/admin/ops/mod_queue_screen.dart' show ModQueueScreen;
import '../ops/admin/reports_screen.dart' show ReportsScreen;
import '../ops/admin/review_queues_admin.dart' show AddressReviewAdminTab, KahveSafetyAdminTab;
import '../ops/events/member_events_admin.dart' show MemberEventsAdminScreen;
import '../ops/events/ride_disputes_admin.dart' show RideDisputesScreen;
import '../ops/lobby/host_rooms_screen.dart' show HostRoomsScreen;
import '../ops/metrics/cost_alerts_screen.dart' show CostAlertsScreen;
import '../ops/metrics/metrics_admin.dart' show MetricsAdminTab;
import '../ops/metrics/product_metrics_screen.dart' show ProductMetricsScreen;
import '../ops/moderation/content_hide_staff.dart' show HiddenContentScreen, canHideContent;
import '../ops/moderation/mod_center_screen.dart' show ModCenterScreen;
import '../ops/store/store_admin_common.dart' show canManageStore;
import '../ops/store/store_orders_admin.dart' show StoreOrdersAdminTab;
import '../ops/store/store_products_admin.dart' show StoreProductsAdminTab;
import '../ops/store/store_settings_admin.dart' show StoreSettingsAdminTab;
import '../ops/support/support_admin.dart' show SupportTicketsScreen;
import 'channels_admin.dart' show ChannelsAdminScreen;
import 'dashboard.dart' show DashboardScreen;
import 'events_admin.dart' show EventCreateScreen;
import 'members_tools.dart' show MemberToolsScreen;

/// Bölüm grupları (geniş ekranda kenar çubuğu başlıkları, telefonda "Tümü" listesi).
enum CrewGroup {
  genel('Genel'),
  uyelik('Üyelik'),
  moderasyon('Moderasyon'),
  destek('Destek'),
  inceleme('İncelemeler'),
  ticaret('Ticaret'),
  icerik('İçerik'),
  rapor('Raporlar');

  const CrewGroup(this.label);
  final String label;
}

/// Bir bölüm: kimin göreceği, panodaki sayaç anahtarı ve bildirim bağlantıları (sunucu: functions/src/crew_link.ts).
class CrewSection {
  const CrewSection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.group,
    required this.visible,
    required this.build,
    this.countKey,
    this.aliases = const [],
    this.queue = false,
  });

  final String id, title, subtitle;
  final IconData icon;
  final CrewGroup group;
  final bool Function(Session s) visible;
  final Widget Function() build;

  /// Panodaki bekleyen iş sayısı (crewDash › counts).
  final String? countKey;

  /// Eski uygulama yolları (bildirim bağlantıları): `/basvurular`, `/yonetim/canli`…
  final List<String> aliases;

  /// "Kuyruklar" sekmesinde listelenir (bekleyen iş içeren bölüm).
  final bool queue;

  String get path => '/b/$id';
}

bool _admin(Session s) => s.isAdmin;
bool _staff(Session s) => s.isStaff;
bool _cap(Session s, String cap) => s.isFounder || s.can(cap);

/// Bütün bölümler (sıra = kenar çubuğu sırası).
final List<CrewSection> kCrewSections = [
  CrewSection(
    id: 'pano', title: 'Pano', subtitle: 'Bekleyen işler ve eğilimler', icon: Icons.space_dashboard_rounded, group: CrewGroup.genel,
    visible: (_) => true, build: () => const DashboardScreen(),
  ),
  CrewSection(
    id: 'basvurular', title: 'Başvurular', subtitle: 'Onay bekleyen üyelik başvuruları', icon: Icons.how_to_reg_rounded, group: CrewGroup.uyelik,
    visible: _admin, build: () => const ApplicationsScreen(), countKey: 'applications', aliases: const ['/basvurular'], queue: true,
  ),
  CrewSection(
    id: 'salonlar', title: 'Bekleme Salonu', subtitle: 'Adaylarla ev sahibi olarak sohbet et', icon: Icons.meeting_room_rounded, group: CrewGroup.uyelik,
    visible: _staff, build: () => const HostRoomsScreen(), aliases: const ['/salonlar'],
  ),
  CrewSection(
    id: 'uyeler', title: 'Üye işlemleri', subtitle: 'Rol, Premium, Elmas, moderasyon', icon: Icons.manage_accounts_rounded, group: CrewGroup.uyelik,
    visible: (s) => s.isAdmin || s.canModerate, build: () => const MemberToolsScreen(),
  ),
  CrewSection(
    id: 'kuyruk', title: 'Moderasyon kuyruğu', subtitle: 'Şikâyet edilen içerik, itirazlar, SLA', icon: Icons.inbox_rounded, group: CrewGroup.moderasyon,
    visible: (s) => s.isStaff || s.canModerate, build: () => const ModQueueScreen(), countKey: 'reports', queue: true,
  ),
  CrewSection(
    id: 'sikayetler', title: 'Mesaj şikâyetleri', subtitle: 'Sohbet ve kanal mesajları', icon: Icons.flag_rounded, group: CrewGroup.moderasyon,
    visible: _staff, build: () => const ReportsScreen(), aliases: const ['/sikayetler'],
  ),
  CrewSection(
    id: 'canli', title: 'Canlı yayın şikâyetleri', subtitle: 'Açık yayın bildirimleri', icon: Icons.live_tv_rounded, group: CrewGroup.moderasyon,
    visible: _staff, build: () => const LiveReportsScreen(), countKey: 'liveReports', aliases: const ['/yonetim/canli'], queue: true,
  ),
  CrewSection(
    id: 'merkez', title: 'Moderasyon merkezi', subtitle: 'Bloklar, itirazlar, kayıtlar', icon: Icons.shield_moon_rounded, group: CrewGroup.moderasyon,
    visible: (s) => s.canModerate, build: () => const ModCenterScreen(), aliases: const ['/moderasyon'],
  ),
  CrewSection(
    id: 'gizlenen', title: 'Modere edilecek gönderiler', subtitle: 'İşaretlenenler, kararlar ve itirazlar', icon: Icons.visibility_off_rounded, group: CrewGroup.moderasyon,
    visible: canHideContent, build: () => const HiddenContentScreen(), countKey: 'modFlags', queue: true,
  ),
  CrewSection(
    id: 'ai-guvenligi', title: 'AI güvenliği', subtitle: 'Yapay zekâ manipülasyon girişimleri', icon: Icons.security_rounded, group: CrewGroup.moderasyon,
    visible: _staff, build: () => const AiSecurityAdminTab(embedded: false), aliases: const ['/yonetim/ai-guvenligi'],
  ),
  CrewSection(
    id: 'destek', title: 'Destek talepleri', subtitle: 'HADİ Destek\'ten gelen talepler', icon: Icons.support_agent_rounded, group: CrewGroup.destek,
    visible: _staff, build: () => const SupportTicketsScreen(), countKey: 'ticketsOpen', aliases: const ['/destek-talepleri'], queue: true,
  ),
  CrewSection(
    id: 'kimlik', title: 'Kimlik doğrulama', subtitle: 'Bekleyen kimlik incelemeleri', icon: Icons.badge_rounded, group: CrewGroup.inceleme,
    visible: (s) => _cap(s, Cap.identityReview), build: () => const IdReviewAdminTab(embedded: false), countKey: 'idReviews',
    aliases: const ['/yonetim/kimlik-dogrulama'], queue: true,
  ),
  CrewSection(
    id: 'adres', title: 'Adres belgeleri', subtitle: 'İkametgâh belgesi incelemeleri', icon: Icons.home_work_rounded, group: CrewGroup.inceleme,
    visible: (s) => _cap(s, Cap.addressReview), build: () => const AddressReviewAdminTab(embedded: false), countKey: 'addressReviews',
    aliases: const ['/yonetim/adres-dogrulama'], queue: true,
  ),
  CrewSection(
    id: 'kahve', title: 'Kahve güvenliği', subtitle: 'Kahve Eşleşmesi güvenlik incelemeleri', icon: Icons.coffee_rounded, group: CrewGroup.inceleme,
    visible: (s) => _cap(s, Cap.kahveSafety), build: () => const KahveSafetyAdminTab(embedded: false), countKey: 'kahveReviews',
    aliases: const ['/yonetim/kahve-guvenlik'], queue: true,
  ),
  CrewSection(
    id: 'isletmeler', title: 'İşletmeler', subtitle: 'Başvurular, etkinlikler, ödeme talepleri', icon: Icons.storefront_rounded, group: CrewGroup.ticaret,
    visible: (s) => _cap(s, Cap.businessReview), build: () => const BusinessAdminTab(embedded: false), countKey: 'businessApps',
    aliases: const ['/yonetim/isletmeler'], queue: true,
  ),
  CrewSection(
    id: 'kuryeler', title: 'Kuryeler', subtitle: 'Başvurular, teslimat uyuşmazlıkları, ödemeler', icon: Icons.delivery_dining_rounded, group: CrewGroup.ticaret,
    visible: (s) => _cap(s, Cap.courierReview), build: () => const CourierAdminTab(embedded: false), countKey: 'courierApps',
    aliases: const ['/yonetim/kuryeler'], queue: true,
  ),
  // HADİ Mağaza (kurucu ya da store.manage). Bildirim bağlantısı: crewLink("/magaza") → Mağaza siparişleri.
  CrewSection(
    id: 'magaza-siparisleri', title: 'Mağaza siparişleri', subtitle: 'Baskı, kargo, teslimat ve iadeler', icon: Icons.local_mall_rounded, group: CrewGroup.ticaret,
    visible: canManageStore, build: () => const StoreOrdersAdminTab(embedded: false), countKey: 'storeOrders', aliases: const ['/magaza'], queue: true,
  ),
  CrewSection(
    id: 'magaza-urunleri', title: 'Mağaza ürünleri', subtitle: 'Ürünler, renkler, bedenler, hazır tasarımlar, fiyatlar', icon: Icons.checkroom_rounded, group: CrewGroup.ticaret,
    visible: canManageStore, build: () => const StoreProductsAdminTab(embedded: false),
  ),
  CrewSection(
    id: 'magaza-ayarlari', title: 'Mağaza ayarları', subtitle: 'Kargo ücreti, kargo firmaları, hediye süresi', icon: Icons.tune_rounded, group: CrewGroup.ticaret,
    visible: canManageStore, build: () => const StoreSettingsAdminTab(embedded: false),
  ),
  CrewSection(
    id: 'yolculuklar', title: 'Yolculuk anlaşmazlıkları', subtitle: 'Paylaşımlı yolculuk şikâyetleri', icon: Icons.directions_car_rounded, group: CrewGroup.ticaret,
    visible: _staff, build: () => const RideDisputesScreen(), aliases: const ['/yonetim/yolculuklar'],
  ),
  CrewSection(
    id: 'etkinlik-ekle', title: 'Etkinlik ekle', subtitle: 'Kulüp etkinliği oluştur ve yayımla', icon: Icons.add_circle_rounded, group: CrewGroup.icerik,
    visible: _admin, build: () => const EventCreateScreen(), aliases: const ['/etkinlik-yeni'],
  ),
  CrewSection(
    id: 'uye-etkinlikleri', title: 'Üye etkinlikleri', subtitle: 'Onay bekleyen öneriler ve taslaklar', icon: Icons.fact_check_rounded, group: CrewGroup.icerik,
    visible: _admin, build: () => const MemberEventsAdminScreen(), aliases: const ['/yonetim/uye-etkinlikleri'],
  ),
  CrewSection(
    id: 'kanallar', title: 'Kanallar', subtitle: 'Kanal ve grup kur, düzenle, duyuru gönder', icon: Icons.tag_rounded, group: CrewGroup.icerik,
    visible: _admin, build: () => const ChannelsAdminScreen(),
  ),
  CrewSection(
    id: 'ai-video', title: 'AI video şablonları', subtitle: 'Şablonlar ve ayarlar', icon: Icons.movie_filter_rounded, group: CrewGroup.icerik,
    visible: (s) => _cap(s, 'aivideo.manage'), build: () => const AiVideoAdminTab(embedded: false), aliases: const ['/yonetim/ai-video'],
  ),
  CrewSection(
    id: 'metrikler', title: 'İstatistik', subtitle: 'Üyelik, ekonomi, içerik, etkinlik', icon: Icons.insights_rounded, group: CrewGroup.rapor,
    visible: (s) => s.isPrimary, build: () => const _Padded(title: 'İstatistik', child: MetricsAdminTab()),
  ),
  CrewSection(
    id: 'urun', title: 'Ürün metrikleri', subtitle: 'DAU/WAU/MAU, tutunma, huni', icon: Icons.ssid_chart_rounded, group: CrewGroup.rapor,
    visible: (s) => s.isPrimary, build: () => const ProductMetricsScreen(),
  ),
  CrewSection(
    id: 'maliyet', title: 'Maliyet uyarıları', subtitle: 'Günlük bulut ve yapay zekâ maliyeti', icon: Icons.savings_rounded, group: CrewGroup.rapor,
    visible: (s) => s.isPrimary, build: () => const CostAlertsScreen(),
  ),
];

CrewSection? sectionById(String id) {
  for (final s in kCrewSections) {
    if (s.id == id) return s;
  }
  return null;
}

/// Bildirim bağlantısı → bölüm (`/basvurular` → başvurular).
CrewSection? sectionForAlias(String path) {
  for (final s in kCrewSections) {
    if (s.aliases.contains(path)) return s;
  }
  return null;
}

List<CrewSection> visibleSections(Session s) => [for (final x in kCrewSections) if (x.visible(s)) x];

/// Ekibe açık mı: pano dışında görebildiği en az bir bölüm.
bool hasCrewAccess(Session s) => visibleSections(s).length > 1;

/// Sekme gövdesi olarak tasarlanmış (Scaffold'suz) bölümler için iskelet.
class _Padded extends StatelessWidget {
  const _Padded({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title)), body: child);
}
