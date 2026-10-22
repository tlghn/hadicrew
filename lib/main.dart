import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsBinding;
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:hadi/core/host_hooks.dart';
import 'package:hadi/core/session.dart';
import 'package:hadi/core/theme_presets.dart' show ThemeController;
import 'package:hadi/core/web_url.dart';
import 'package:hadi/data/demo_services.dart' show DemoApplicationService;
import 'package:hadi/data/services.dart';

import 'app/crew_app.dart';
import 'app/web_options.dart';
import 'ops/admin/applications_screen.dart' show decideApplicationFlow, openApplicationReview;

/// Yalnızca yerel deneme: `--dart-define=PANEL_DEMO=true` ile Firebase'siz, uygulamanın demo verisiyle açılır.
const _demo = bool.fromEnvironment('PANEL_DEMO');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  WebUrl.install(); // gezinince adres çubuğu değişir; adres kopyalanıp paylaşılabilir (hadi › core/web_url.dart)
  // Ekip araçları (rol tabanlı yönetim yetkileri) yalnızca Crew ve Kurucu Paneli'nde açıktır; üye uygulamasında kapalı.
  Session.staffTools = true;
  // Bekleme Salonu'ndaki kişi kartı: başvuruyu incele / karar ver (uygulamada bu kancalar boştur).
  HostHooks.openApplicationReview = openApplicationReview;
  HostHooks.decideApplication = decideApplicationFlow;
  if (_demo) {
    SemanticsBinding.instance.ensureSemantics(); // otomatik deneme (erişilebilirlik ağacıyla tıklama)
    await ThemeController.instance.load();
    final services = Services.demo();
    (services.applications as DemoApplicationService).approve(); // demo hesabı onaylı üye (kurucu) olsun
    runApp(CrewApp(services: services));
    return;
  }
  if (!CrewWebOptions.configured) {
    runApp(const CrewConfigMissing());
    return;
  }
  await Firebase.initializeApp(options: CrewWebOptions.web);
  await ThemeController.instance.load();
  runApp(CrewApp(services: Services.firebase()));
}
