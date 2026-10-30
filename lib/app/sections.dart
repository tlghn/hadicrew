import 'package:flutter/material.dart';
import 'package:hadi/core/capabilities.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/core/view_as.dart' show ViewAs;

import '../ops/admin/ai_security_admin.dart' show AiSecurityAdminTab;
import '../ops/admin/ai_video_admin.dart' show AiVideoAdminTab;
import '../ops/admin/applications_screen.dart' show ApplicationsScreen;
import '../ops/admin/business_admin.dart' show BusinessAdminTab;
import '../ops/admin/courier_admin.dart' show CourierAdminTab;
import '../ops/admin/field_test_crew_view.dart' show FieldTestCrewScreen;
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
import 'package:hadi/features/ai_label/ai_label_admin.dart' show AiLabelReviewScreen, kAiLabelCountKey;
import 'package:hadi/features/ads/ad_appeals_admin.dart' show AdAppealsAdminScreen;
import '../ops/store/store_admin_common.dart' show canManageStore;
import '../ops/store/store_orders_admin.dart' show StoreOrdersAdminTab;
import '../ops/store/store_products_admin.dart' show StoreProductsAdminTab;
import '../ops/store/store_settings_admin.dart' show StoreSettingsAdminTab;
import '../ops/store/store_campaigns_admin.dart' show StoreCampaignsAdminTab;
import '../ops/store/store_reviews_admin.dart' show StoreReviewsAdminTab;
import '../ops/secondhand/sh_admin_common.dart' show canManageSecondhand;
import '../ops/secondhand/sh_disputes_admin.dart' show ShDisputesAdminTab;
import '../ops/secondhand/sh_orders_admin.dart' show ShOrdersAdminTab;
import '../ops/secondhand/sh_queue_admin.dart' show ShQueueAdminTab;
import '../ops/secondhand/sh_settings_admin.dart' show ShSettingsAdminTab;
import '../ops/notify_studio/ns_studio_screen.dart' show NotifyStudioScreen, canNotifySend, canNotifyApprove;
import 'package:hadi/features/books/books_admin.dart' show BooksAdminScreen;
import 'package:hadi/features/events/tanisma/tanisma_admin.dart' show TanismaAdminScreen;
import 'package:hadi/features/events/wizard/event_wizard.dart' show EventWizardScreen;
import 'package:hadi/features/events/admin/events_admin_list.dart' show EventsAdminListScreen;
import 'package:go_router/go_router.dart';
import 'package:hadi/data/event_ai_service.dart' show kEventAiService;
import 'package:hadi/core/service_switches.dart' show ServiceSwitches;
import '../ops/pro/pro_admin.dart' show ProLicenseAdminTab, canReviewPro;
import 'package:hadi/features/creator_subs/creator_subs_admin.dart' show CreatorReviewQueueTab;
import '../ops/support/support_admin.dart' show SupportTicketsScreen;
import '../ops/special_days/special_days_admin.dart' show SpecialDaysAdminScreen;
import '../panel_kit/panel_search.dart' show PanelEntry;
import 'channels_admin.dart' show ChannelsAdminScreen;
import 'crew_api.dart' show CrewDash;
import 'crew_counts.dart' show queueTotalOf, sumCounts;
import 'dashboard.dart' show DashboardScreen;
import 'events_admin.dart' show EventCreateScreen;
import 'members_tools.dart' show MemberToolsScreen;

/// Bölüm kategorileri (27 Ekim 2026; Kurucu Paneli ile aynı adlar). Kenar çubuğunda / "Tümü"de kategoriler ve içlerindeki
/// bölümler Türk alfabesine göre sıralanır (panel_kit/tr_text.dart › trCompare); enum sırasının önemi yok.
/// [genel] (Pano) kategorilerin üstünde sabit durur.
enum CrewGroup {
  genel('Genel'),
  uyelik('Üyeler ve roller'),
  moderasyon('İçerik ve moderasyon'),
  dogrulama('Doğrulama ve incelemeler'),
  guvenlik('Güvenlik ve gizlilik'),
  destek('Destek ve geri bildirim'),
  test('Test ve kalite'),
  ticaret('Mağaza ve ticaret'),
  etkinlik('Etkinlikler'),
  iletisim('İletişim ve bildirimler'),
  yz('Yapay zekâ'),
  rapor('Raporlar ve analiz');

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
    this.countKeys = const [],
    this.aliases = const [],
    this.queue = false,
    this.keys = '',
    this.pinned = false,
  });

  /// Kategorisinin en üstünde (panel_kit › PanelEntry.pinned).
  final bool pinned;

  final String id, title, subtitle;
  final IconData icon;
  final CrewGroup group;
  final bool Function(Session s) visible;
  final Widget Function() build;

  /// Bekleyen iş sayaçları (crewDash › counts). Rozet = bunların toplamı; her anahtar bölümdeki bir sekmenin / listenin
  /// öğelerini sayar (sekme rozetleri: [CountTab] aynı anahtarlarla). Boşsa rozet yok.
  final List<String> countKeys;

  /// Eski uygulama yolları (bildirim bağlantıları): `/basvurular`, `/yonetim/canli`…
  final List<String> aliases;

  /// "Kuyruklar" sekmesinde listelenir (bekleyen iş içeren bölüm).
  final bool queue;

  /// Aramada bulunması için ek sözcükler / eş anlamlılar (panel_kit › komut paleti ve YZ önerisi).
  final String keys;

  String get path => '/b/$id';
}

bool _admin(Session s) => s.isAdmin;
bool _staff(Session s) => s.isStaff;
bool _cap(Session s, String cap) => s.isFounder || s.can(cap);

/// Crew'a girebilen HER rol (kurucu, yönetici, moderatör ya da en az bir yetki veren rol: etkinlik sorumlusu, bakım ekibi,
/// sohbet operatörü, destek ekibi…). Test hesabı ve "olarak gör" önizlemesi dışarıda. Sunucu: field_test.ts › isCrewViewer.
bool anyCrewRole(Session s) =>
    !s.isDummy && (s.isStaff || (!ViewAs.instance.active && Capabilities.instance.myRoles.any((r) => r.capabilities.isNotEmpty)));

/// Bütün bölümler. Menüde sıra burada değil: kategoriler ve bölümler Türk alfabesine göre (panel_kit › groupByCategory).
final List<CrewSection> kCrewSections = [
  CrewSection(
    id: 'pano', title: 'Pano', subtitle: 'Bekleyen işler ve eğilimler', icon: Icons.space_dashboard_rounded, group: CrewGroup.genel,
    visible: (_) => true, build: () => const DashboardScreen(),
    keys: 'pano özet bekleyen işler eğilim grafik ana sayfa',
  ),
  CrewSection(
    id: 'basvurular', title: 'Başvurular', subtitle: 'Onay bekleyen üyelik başvuruları', icon: Icons.how_to_reg_rounded, group: CrewGroup.uyelik,
    visible: _admin, build: () => const ApplicationsScreen(), countKeys: const ['applications'], aliases: const ['/basvurular'], queue: true,
    keys: 'başvuru üyelik onay ret aday yeni üye kayıt bekleyen',
  ),
  CrewSection(
    id: 'salonlar', title: 'Bekleme Salonu', subtitle: 'Adaylarla ev sahibi olarak sohbet et', icon: Icons.meeting_room_rounded, group: CrewGroup.uyelik,
    visible: _staff, build: () => const HostRoomsScreen(), aliases: const ['/salonlar'],
    keys: 'bekleme salonu aday sohbet ev sahibi salon oda',
  ),
  CrewSection(
    id: 'uyeler', title: 'Üye işlemleri', subtitle: 'Rol, Premium, Elmas, moderasyon', icon: Icons.manage_accounts_rounded, group: CrewGroup.uyelik,
    visible: (s) => s.isAdmin || s.canModerate, build: () => const MemberToolsScreen(),
    keys: 'üye ara bul rol premium elmas moderasyon ceza susturma blok hesap kullanıcı profil',
  ),
  CrewSection(
    id: 'kuyruk', title: 'Moderasyon kuyruğu', subtitle: 'Şikâyet edilen içerik, itirazlar, SLA', icon: Icons.inbox_rounded, group: CrewGroup.moderasyon,
    visible: (s) => s.isStaff || s.canModerate, build: () => const ModQueueScreen(), countKeys: const ['reports'], queue: true,
    keys: 'moderasyon kuyruk şikayet rapor içerik itiraz sla gönderi yorum',
  ),
  CrewSection(
    id: 'sikayetler', title: 'Mesaj şikâyetleri', subtitle: 'Sohbet ve kanal mesajları', icon: Icons.flag_rounded, group: CrewGroup.moderasyon,
    visible: _staff, build: () => const ReportsScreen(), aliases: const ['/sikayetler'],
    keys: 'mesaj şikayet sohbet kanal dm rapor taciz',
  ),
  CrewSection(
    id: 'canli', title: 'Canlı yayın şikâyetleri', subtitle: 'Açık yayın bildirimleri', icon: Icons.live_tv_rounded, group: CrewGroup.moderasyon,
    visible: _staff, build: () => const LiveReportsScreen(), countKeys: const ['liveReports'], aliases: const ['/yonetim/canli'], queue: true,
    keys: 'canlı yayın şikayet live yayın bildirimi',
  ),
  CrewSection(
    id: 'merkez', title: 'Moderasyon merkezi', subtitle: 'Bloklar, itirazlar, kayıtlar', icon: Icons.shield_moon_rounded, group: CrewGroup.moderasyon,
    visible: (s) => s.canModerate, build: () => const ModCenterScreen(), aliases: const ['/moderasyon'],
    keys: 'moderasyon merkezi blok bloke itiraz kayıt log ceza geçmişi',
  ),
  CrewSection(
    id: 'gizlenen', title: 'Modere edilecek gönderiler', subtitle: 'İşaretlenenler, kararlar ve itirazlar', icon: Icons.visibility_off_rounded, group: CrewGroup.moderasyon,
    visible: canHideContent, build: () => const HiddenContentScreen(), countKeys: const ['modFlags'], queue: true,
    keys: 'gizli gönderi işaretle modere karar itiraz içerik kaldır',
  ),
  // "🤖 Yapay Zeka İçeriği" etiketi: tespitler, itirazlar, kaldırma onayları (dört göz). hadimobile/lib/features/ai_label.
  CrewSection(
    id: 'yz-icerigi', title: 'Yapay Zeka İçeriği', subtitle: 'Tespitler, itirazlar ve etiket kaldırma onayları', icon: Icons.smart_toy_rounded, group: CrewGroup.moderasyon,
    visible: canHideContent, build: () => const AiLabelReviewScreen(), countKeys: const [kAiLabelCountKey], aliases: const ['/yz-icerigi'], queue: true,
    keys: 'yapay zeka içeriği etiket ai tespit itiraz kaldırma onay dört göz c2pa',
  ),
  // Reklam etiketi itirazları (30 Ekim 2026; sunucu ads › adAppeals / adTagSet, yalnızca kurucu ve yönetici).
  CrewSection(
    id: 'reklam-itirazlari', title: 'Reklam etiketi itirazları', subtitle: '#reklam / #işbirliği etiketine itirazlar', icon: Icons.campaign_rounded, group: CrewGroup.moderasyon,
    visible: _admin, build: () => const AdAppealsAdminScreen(), aliases: const ['/reklam-itirazlari'],
    keys: 'reklam işbirliği etiket itiraz sponsorlu yapay zeka gönderi',
  ),
  CrewSection(
    id: 'ai-guvenligi', title: 'AI güvenliği', subtitle: 'Yapay zekâ manipülasyon girişimleri', icon: Icons.security_rounded, group: CrewGroup.guvenlik,
    visible: _staff, build: () => const AiSecurityAdminTab(embedded: false), aliases: const ['/yonetim/ai-guvenligi'],
    keys: 'yapay zeka güvenlik enjeksiyon prompt saldırı manipülasyon ai',
  ),
  CrewSection(
    id: 'destek', title: 'Destek talepleri', subtitle: 'HADİ Destek\'ten gelen talepler', icon: Icons.support_agent_rounded, group: CrewGroup.destek,
    visible: _staff, build: () => const SupportTicketsScreen(), countKeys: const ['ticketsAwaiting'], aliases: const ['/destek-talepleri'], queue: true,
    keys: 'destek talep yardım insana bağlan şikayet üye mesajı yanıtla ticket',
  ),
  // Test bulguları — SALT-OKUNUR (27 Ekim 2026, kurucu 01:51): yalnız açıklama (+ sesli not dökümü), ekran görüntüsü, ekip
  // (insan) notları ve durum; YZ / Claude yazıları, karar gerekçesi, kimlik, bağlam, derece, Akçe yok; hiçbir işlem yok.
  // Sunucu: field_test.ts › ftCrewList / ftCrewGet. Görünürlük (kurucu 03:23): Crew'a girebilen HER rol ([anyCrewRole]).
  // Tam yetki ve onay bağlantıları (/test-bulgulari/onay) yalnız kurucu tarafında.
  CrewSection(
    id: 'test-bulgulari', title: 'Test bulguları', subtitle: 'Saha testi bulguları: açıklama, ekran görüntüsü, ekip notları (salt okunur)',
    icon: Icons.bug_report_rounded, group: CrewGroup.test,
    visible: anyCrewRole, build: () => const FieldTestCrewScreen(), aliases: const ['/test-bulgulari'],
    keys: 'saha testi bulgu hata bug ekran görüntüsü test ekibi not salt okunur',
  ),
  CrewSection(
    id: 'kimlik', title: 'Kimlik doğrulama', subtitle: 'Bekleyen kimlik incelemeleri', icon: Icons.badge_rounded, group: CrewGroup.dogrulama,
    visible: (s) => _cap(s, Cap.identityReview), build: () => const IdReviewAdminTab(embedded: false), countKeys: const ['idReviews'],
    aliases: const ['/yonetim/kimlik-dogrulama'], queue: true,
    keys: 'kimlik tc doğrulama inceleme nüfus belge selfie',
  ),
  CrewSection(
    id: 'adres', title: 'Adres belgeleri', subtitle: 'İkametgâh belgesi incelemeleri', icon: Icons.home_work_rounded, group: CrewGroup.dogrulama,
    visible: (s) => _cap(s, Cap.addressReview), build: () => const AddressReviewAdminTab(embedded: false), countKeys: const ['addressReviews'],
    aliases: const ['/yonetim/adres-dogrulama'], queue: true,
    keys: 'adres ikametgah belge doğrulama inceleme',
  ),
  CrewSection(
    id: 'kahve', title: 'Kahve güvenliği', subtitle: 'Kahve Eşleşmesi güvenlik incelemeleri', icon: Icons.coffee_rounded, group: CrewGroup.guvenlik,
    visible: (s) => _cap(s, Cap.kahveSafety), build: () => const KahveSafetyAdminTab(embedded: false), countKeys: const ['kahveReviews'],
    aliases: const ['/yonetim/kahve-guvenlik'], queue: true,
    keys: 'kahve eşleşmesi buluşma güvenlik inceleme',
  ),
  // Üye abonelikleri (creator_subs.ts): yapay zekânın emin olamadığı abonelere özel içerik, kademe, itirazlar, çocuk güvenliği.
  // Bildirim bağlantısı: crewLink("/abonelik-incelemeleri"). Yetki: kurucu/yönetici ya da content.remove / moderation.system.
  CrewSection(
    id: 'abonelik-incelemeleri', title: 'Abonelik incelemeleri', subtitle: 'Abonelere özel gönderi ve kademe denetimi, itirazlar', icon: Icons.star_rounded, group: CrewGroup.dogrulama,
    visible: (s) => _admin(s) || _cap(s, 'content.remove') || _cap(s, 'moderation.system'), build: () => const CreatorReviewQueueTab(embedded: false),
    countKeys: const ['creatorReviews'], aliases: const ['/abonelik-incelemeleri'], queue: true,
    keys: 'abonelik abone yayıncı üretici creator içerik kademe itiraz çocuk güvenliği inceleme',
  ),
  // Profesyonel profil (pro_profiles.ts): lisans belgeleri (dört göz), bildirilen değerlendirmeler, profil gizleme.
  // Bildirim bağlantısı: crewLink("/pro-lisans"). Yetki: kurucu ya da pro.review.
  CrewSection(
    id: 'pro-lisans', title: 'Lisans doğrulama', subtitle: 'Profesyonel profil: meslek belgeleri, değerlendirmeler', icon: Icons.workspace_premium_rounded, group: CrewGroup.dogrulama,
    visible: canReviewPro, build: () => const ProLicenseAdminTab(embedded: false), countKeys: const ['proLicenses'],
    aliases: const ['/pro-lisans'], queue: true,
    keys: 'profesyonel profil lisans diploma meslek belge değerlendirme yorum dört göz',
  ),
  CrewSection(
    id: 'isletmeler', title: 'İşletmeler', subtitle: 'Başvurular, etkinlikler, ödeme talepleri', icon: Icons.storefront_rounded, group: CrewGroup.ticaret,
    visible: (s) => _cap(s, Cap.businessReview), build: () => const BusinessAdminTab(embedded: false), countKeys: const ['businessApps', 'businessEvents', 'businessPayouts', 'businessDisputes'],
    aliases: const ['/yonetim/isletmeler'], queue: true,
    keys: 'işletme başvuru restoran kafe etkinlik ödeme talebi iş yeri',
  ),
  CrewSection(
    id: 'kuryeler', title: 'Kuryeler', subtitle: 'Başvurular, teslimat uyuşmazlıkları, ödemeler', icon: Icons.delivery_dining_rounded, group: CrewGroup.ticaret,
    visible: (s) => _cap(s, Cap.courierReview), build: () => const CourierAdminTab(embedded: false), countKeys: const ['courierApps', 'courierCases', 'courierPayouts'],
    aliases: const ['/yonetim/kuryeler'], queue: true,
    keys: 'kurye motokurye teslimat başvuru uyuşmazlık ödeme sipariş',
  ),
  // HADİ Mağaza (kurucu ya da store.manage). Bildirim bağlantısı: crewLink("/magaza") → Mağaza siparişleri.
  CrewSection(
    id: 'magaza-siparisleri', title: 'Mağaza siparişleri', subtitle: 'Baskı, kargo, teslimat ve iadeler', icon: Icons.local_mall_rounded, group: CrewGroup.ticaret,
    visible: canManageStore, build: () => const StoreOrdersAdminTab(embedded: false), countKeys: const ['storeOrders'], aliases: const ['/magaza'], queue: true,
    keys: 'mağaza sipariş kargo baskı teslim iade iptal takip',
  ),
  CrewSection(
    id: 'magaza-urunleri', title: 'Mağaza ürünleri', subtitle: 'Ürünler, renkler, bedenler, hazır tasarımlar, fiyatlar', icon: Icons.checkroom_rounded, group: CrewGroup.ticaret,
    visible: canManageStore, build: () => const StoreProductsAdminTab(embedded: false),
    keys: 'mağaza ürün tişört kupa renk beden tasarım fiyat stok',
  ),
  CrewSection(
    id: 'magaza-kampanyalari', title: 'Mağaza kampanyaları', subtitle: 'İndirim, flaş, kupon, paket, vitrin bantları ve sonuçları', icon: Icons.local_offer_rounded, group: CrewGroup.ticaret,
    visible: canManageStore, build: () => const StoreCampaignsAdminTab(embedded: false),
    keys: 'mağaza kampanya indirim kupon flaş paket vitrin',
  ),
  CrewSection(
    id: 'magaza-yorumlari', title: 'Mağaza yorumları', subtitle: 'Değerlendirmeler, yorumlar, şikâyetler; gizle / geri aç', icon: Icons.reviews_rounded, group: CrewGroup.ticaret,
    visible: canManageStore, build: () => const StoreReviewsAdminTab(embedded: false),
    keys: 'mağaza yorum değerlendirme puan şikayet gizle',
  ),
  CrewSection(
    id: 'magaza-ayarlari', title: 'Mağaza ayarları', subtitle: 'Kargo ücreti, kargo firmaları, hediye süresi', icon: Icons.tune_rounded, group: CrewGroup.ticaret,
    visible: canManageStore, build: () => const StoreSettingsAdminTab(embedded: false),
    keys: 'mağaza ayar kargo ücreti kargo firması hediye süresi',
  ),
  // HADİ Kitap Mağazası (kurucu ya da store.manage; lib/features/books/books_admin.dart). Crew yalnızca künye/içerik, fiyat &
  // satış ve haklar (technical: false — teknik kip Crew'da ASLA açılmaz); ses/senkron/film Kurucu Paneli › Kitap Teknik'te.
  CrewSection(
    id: 'kitap-magazasi', title: 'Kitap Mağazası', subtitle: 'Künye ve bölüm metinleri, EPUB içe aktarma, fiyat ve satış raporu, haklar ve yayınevleri', icon: Icons.auto_stories_rounded, group: CrewGroup.ticaret,
    visible: canManageStore, build: () => const BooksAdminScreen(technical: false, urlBase: '/b/kitap-magazasi'), aliases: const ['/kitap-yonetimi'],
    keys: 'kitap e-kitap mağaza epub yayınevi telif fiyat satış raporu künye',
  ),
  // HADİ 2. El (kurucu ya da secondhand.manage). Bildirim bağlantıları: crewLink("/ikinci-el") → inceleme,
  // crewLink("/ikinci-el/uyusmazliklar") → uyuşmazlıklar.
  CrewSection(
    id: 'ikinci-el', title: '2. El inceleme', subtitle: 'İlanlar, itirazlar, şikâyetler, dolandırıcılık, kargo kaydı', icon: Icons.recycling_rounded, group: CrewGroup.ticaret,
    visible: canManageSecondhand, build: () => const ShQueueAdminTab(embedded: false), countKeys: const ['secondhand'], aliases: const ['/ikinci-el'], queue: true,
    keys: 'ikinci el 2. el ilan inceleme dolandırıcılık şikayet itiraz',
  ),
  CrewSection(
    id: 'ikinci-el-uyusmazliklar', title: '2. El uyuşmazlıkları', subtitle: 'Kanıtlar, satıcı yanıtı, karar ve iade', icon: Icons.report_outlined, group: CrewGroup.ticaret,
    visible: canManageSecondhand, build: () => const ShDisputesAdminTab(embedded: false), aliases: const ['/ikinci-el/uyusmazliklar'],
    keys: 'ikinci el uyuşmazlık iade kanıt satıcı alıcı',
  ),
  CrewSection(
    id: 'ikinci-el-siparisler', title: '2. El siparişleri', subtitle: 'Emanetteki ödemeler, kargo kaydı, satıcı ödemeleri', icon: Icons.receipt_long_outlined, group: CrewGroup.ticaret,
    visible: canManageSecondhand, build: () => const ShOrdersAdminTab(embedded: false),
    keys: 'ikinci el sipariş emanet ödeme kargo satıcı ödemesi',
  ),
  CrewSection(
    id: 'ikinci-el-ayarlari', title: '2. El ayarları', subtitle: 'Ücretler, kargo, öne çıkarma, Pro, süreler, sınırlar', icon: Icons.tune_rounded, group: CrewGroup.ticaret,
    visible: canManageSecondhand, build: () => const ShSettingsAdminTab(embedded: false),
    keys: 'ikinci el ayar ücret komisyon kargo öne çıkar pro sınır',
  ),
  CrewSection(
    id: 'yolculuklar', title: 'Yolculuk anlaşmazlıkları', subtitle: 'Paylaşımlı yolculuk şikâyetleri', icon: Icons.directions_car_rounded, group: CrewGroup.etkinlik,
    visible: _staff, build: () => const RideDisputesScreen(), aliases: const ['/yonetim/yolculuklar'],
    keys: 'yolculuk araç paylaşımı şikayet anlaşmazlık sürücü yolcu',
  ),
  // Crew › Etkinlikler: tüm etkinlikleri bul ve düzenle (hadi › features/events/admin/events_admin_list.dart; sunucu event_admin.ts).
  // Etkinlik grubunun en üstünde (kenar çubuğunda sıra alfabetik; "Etkinlikler" grubun ilk bölümü olur).
  CrewSection(
    id: 'etkinlikler', title: 'Etkinlikler', subtitle: 'Tüm etkinlikleri bul, düzenle, seriyi yönet, iptal et', icon: Icons.event_note_rounded,
    group: CrewGroup.etkinlik, visible: _admin, build: () => const _EventsAdminSection(), aliases: const ['/yonetim/etkinlikler'],
    keys: 'etkinlik liste düzenle ara bul seri tekrar iptal yayından kaldır katılımcı kopyala geçmiş yaklaşan taslak', pinned: true,
  ),
  // Etkinlik Ekleme Sihirbazı (hadi › features/events/wizard/event_wizard.dart; functions/src/event_ai.ts). Hizmet event_ai_assistant
  // gizliyse bölüm görünmez. Tür yetkisi sunucuda (kurucu/yönetici: kulüp + tanışma serisi).
  CrewSection(
    id: 'etkinlik-sihirbazi', title: 'Etkinlik sihirbazı', subtitle: 'Anlat; YZ türü seçsin, formu ve görselleri hazırlasın', icon: Icons.auto_awesome_rounded,
    group: CrewGroup.etkinlik, visible: (s) => s.isAdmin && !ServiceSwitches.instance.isHidden(kEventAiService),
    build: () => const EventWizardScreen(embedded: true), aliases: const ['/etkinlik-sihirbazi'],
    keys: 'etkinlik sihirbaz yapay zeka yz ai oluştur ekle taslak görsel tanışma serisi otomatik doldur prompt',
  ),
  CrewSection(
    id: 'etkinlik-ekle', title: 'Etkinlik ekle', subtitle: 'Kulüp etkinliği oluştur ve yayımla', icon: Icons.add_circle_rounded, group: CrewGroup.etkinlik,
    visible: _admin, build: () => const EventCreateScreen(), aliases: const ['/etkinlik-yeni'],
    keys: 'etkinlik ekle oluştur yayımla kulüp yeni etkinlik',
  ),
  // Toplu tanışma serileri (hadi › features/events/tanisma/tanisma_admin.dart; functions/src/tanisma.ts). Sunucu: kurucu/yönetici.
  CrewSection(
    id: 'tanisma', title: 'Tanışma serileri', subtitle: 'Dönemsel toplu tanışma buluşmaları, kimlik doğrulama seçeneği', icon: Icons.waving_hand_rounded,
    group: CrewGroup.etkinlik, visible: _admin, build: () => const TanismaAdminScreen(), aliases: const ['/tanisma'],
    keys: 'tanışma buluşma toplu seri yeni üye kimlik',
  ),
  CrewSection(
    id: 'uye-etkinlikleri', title: 'Üye etkinlikleri', subtitle: 'Onay bekleyen öneriler ve taslaklar', icon: Icons.fact_check_rounded, group: CrewGroup.etkinlik,
    visible: _admin, build: () => const MemberEventsAdminScreen(), aliases: const ['/yonetim/uye-etkinlikleri'],
    keys: 'üye etkinliği öneri taslak onay',
  ),
  // Bildirim Stüdyosu (notify.send / notify.approve / kurucu). Onay bildirimi bağlantısı: crewLink("/b/bildirim-onaylari").
  CrewSection(
    id: 'bildirim-studyosu', title: 'Bildirim stüdyosu', subtitle: 'Üyelere uygulama içi bildirim ve kart: kitle, içerik, zaman, A/B, rapor', icon: Icons.campaign_rounded, group: CrewGroup.iletisim,
    visible: canNotifySend, build: () => const NotifyStudioScreen(),
    keys: 'bildirim push anlık kampanya duyuru kitle a/b mesaj gönder',
  ),
  CrewSection(
    id: 'bildirim-onaylari', title: 'Bildirim onayları', subtitle: 'İkinci onay bekleyen gönderimler (dört göz)', icon: Icons.how_to_reg_rounded, group: CrewGroup.iletisim,
    visible: canNotifyApprove, build: () => const NotifyStudioScreen(initialTab: 1), countKeys: const ['notifyApprovals'], aliases: const ['/bildirim-onaylari'], queue: true,
    keys: 'bildirim onay dört göz ikinci onay kampanya',
  ),
  // Özel günler (29 Ekim 2026): yapay zekâ günü tasarlar, kurucu/yönetici tek tuşla uygular (ops/special_days; sunucu specialDay).
  CrewSection(
    id: 'ozel-gunler', title: 'Özel günler', subtitle: 'Bayram, anma, kutlama: yapay zekâ tasarlasın, tek tuşla uygula', icon: Icons.celebration_rounded, group: CrewGroup.iletisim,
    visible: _admin, build: () => const SpecialDaysAdminScreen(),
    keys: 'özel gün bayram kutlama tema bayrak 29 ekim anma cumhuriyet yapay zeka tasarla karşılama',
  ),
  CrewSection(
    id: 'kanallar', title: 'Kanallar', subtitle: 'Kanal ve grup kur, düzenle, duyuru gönder', icon: Icons.tag_rounded, group: CrewGroup.iletisim,
    visible: _admin, build: () => const ChannelsAdminScreen(),
    keys: 'kanal grup duyuru oluştur düzenle',
  ),
  CrewSection(
    id: 'ai-video', title: 'AI video şablonları', subtitle: 'Şablonlar ve ayarlar', icon: Icons.movie_filter_rounded, group: CrewGroup.yz,
    visible: (s) => _cap(s, 'aivideo.manage'), build: () => const AiVideoAdminTab(embedded: false), aliases: const ['/yonetim/ai-video'],
    keys: 'yapay zeka video şablon ai fal veo',
  ),
  CrewSection(
    id: 'metrikler', title: 'İstatistik', subtitle: 'Üyelik, ekonomi, içerik, etkinlik', icon: Icons.insights_rounded, group: CrewGroup.rapor,
    visible: (s) => s.isPrimary, build: () => const _Padded(title: 'İstatistik', child: MetricsAdminTab()),
    keys: 'istatistik metrik rapor üyelik ekonomi içerik etkinlik grafik',
  ),
  CrewSection(
    id: 'urun', title: 'Ürün metrikleri', subtitle: 'DAU/WAU/MAU, tutunma, huni', icon: Icons.ssid_chart_rounded, group: CrewGroup.rapor,
    visible: (s) => s.isPrimary, build: () => const ProductMetricsScreen(),
    keys: 'ürün metrik dau wau mau tutunma retention huni aktif kullanıcı',
  ),
  CrewSection(
    id: 'maliyet', title: 'Maliyet uyarıları', subtitle: 'Günlük bulut ve yapay zekâ maliyeti', icon: Icons.savings_rounded, group: CrewGroup.rapor,
    visible: (s) => s.isPrimary, build: () => const CostAlertsScreen(),
    keys: 'maliyet uyarı bulut yapay zeka gemini harcama fatura bütçe',
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

/// Bölüm rozeti: sayaçlarının toplamı (bilinmiyorsa null). Kenar menü, Tümü, Kuyruklar, Pano kutucukları HEP bunu kullanır.
int? sectionCount(CrewSection s, CrewDash? d) => sumCounts(d, s.countKeys);

/// Kuyruklar toplamı = görünen kuyruk bölümlerinin rozetlerinin toplamı (her sayaç bir kez). Alt menü / kenar menü
/// "Kuyruklar" rozeti ve Pano başlığı bunu gösterir; böylece toplam, tek tek görünen rozetlerle her zaman tutarlıdır.
int queueTotal(Iterable<CrewSection> visible, CrewDash? d) => queueTotalOf([for (final x in visible) if (x.queue) x.countKeys], d);

/// Arama/menü girdisi (panel_kit). Açıklama = alt başlık; kategori = grubun adı.
PanelEntry crewEntry(CrewSection x) =>
    PanelEntry(id: x.id, title: x.title, icon: x.icon, category: x.group.label, description: x.subtitle, keys: x.keys, pinned: x.pinned);

/// Kişinin görebildiği bölümler (arama ve YZ önerisi YALNIZCA bunlarla çalışır; rol bazlı görünürlük korunur).
List<PanelEntry> crewEntries(Session s, {bool includeGeneral = true}) =>
    [for (final x in visibleSections(s)) if (includeGeneral || x.group != CrewGroup.genel) crewEntry(x)];

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

/// Crew › Etkinlikler: onay bekleyen öneriye dokununca ilgili inceleme bölümü açılır.
class _EventsAdminSection extends StatelessWidget {
  const _EventsAdminSection();

  @override
  Widget build(BuildContext context) => EventsAdminListScreen(onOpenSection: (id) => context.go('/b/$id'));
}
