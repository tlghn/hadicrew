import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:hadi/core/capabilities.dart' show Capabilities;
import 'package:hadi/core/push.dart' show rootMessengerKey;
import 'package:hadi/core/session.dart';
import 'package:hadi/core/theme_presets.dart' show ThemeController;
import 'package:hadi/data/services.dart';
import 'package:hadi/features/candidate/candidate_lobby.dart' show LobbyScreen;
import 'package:hadi/features/security/second_factor_gate.dart' show SecondFactorGate;
import 'package:hadi/theme/hadi_colors.dart';
import 'package:hadi/theme/hadi_palette.dart' show PaletteScope;
import 'package:hadi/theme/hadi_theme.dart';
import 'package:hadi/widgets/hadi_notice.dart';

import 'events_admin.dart' show EventCreatedPage;
import 'login_screen.dart';
import 'sections.dart';
import 'shell.dart';

/// HADİ Crew kökü: oturum (uygulamayla aynı Session; ekip araçları açık), tema, giriş, ekip kapısı ve yönlendirme.
class CrewApp extends StatefulWidget {
  const CrewApp({super.key, required this.services});
  final Services services;

  @override
  State<CrewApp> createState() => _CrewAppState();
}

class _CrewAppState extends State<CrewApp> {
  late final Session _session = Session(widget.services);

  late final GoRouter _router = GoRouter(
    refreshListenable: _session,
    redirect: (context, state) {
      // Bildirim bağlantıları (functions/src/crew_link.ts): eski uygulama yolları bölüme çevrilir.
      final alias = sectionForAlias(state.uri.path);
      return alias?.path;
    },
    // Düz yollar: geniş ekranda kenar çubuğu `go` ile gezer (geri oku yok); telefonda bölümler `push` ile açılır.
    routes: [
      GoRoute(path: '/', builder: (_, _) => const _Gate(tab: 'pano')),
      GoRoute(path: '/kuyruklar', builder: (_, _) => const _Gate(tab: 'kuyruklar')),
      GoRoute(path: '/tumu', builder: (_, _) => const _Gate(tab: 'tumu')),
      GoRoute(path: '/b/:id', builder: (_, state) => _Gate(tab: state.pathParameters['id']!)),
      // Bekleme Salonu: ev sahibi olarak (host_rooms_screen.dart › Routes.lobby).
      GoRoute(path: '/salon/:room', builder: (_, state) => _Gated(child: LobbyScreen(room: state.pathParameters['room']!, asHost: true))),
      // Etkinlik ekle → kaydedince uygulama yolu (/etkinlik/{id}) yerine özet.
      GoRoute(
        path: '/etkinlik/:id',
        builder: (_, state) => _Gated(child: EventCreatedPage(id: state.pathParameters['id']!, fromMember: state.uri.queryParameters['kaynak'] == 'uye')),
      ),
    ],
    errorBuilder: (context, state) => const _AppOnlyPage(),
  );

  @override
  void dispose() {
    _router.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      session: _session,
      child: ListenableBuilder(
        listenable: ThemeController.instance,
        builder: (context, _) => MaterialApp.router(
          title: 'HADİ Crew',
          debugShowCheckedModeBanner: false,
          theme: HadiTheme.forPreset(ThemeController.instance.preset, Brightness.light),
          darkTheme: HadiTheme.forPreset(ThemeController.instance.preset, Brightness.dark),
          themeMode: ThemeController.instance.themeMode,
          locale: const Locale('tr', 'TR'),
          supportedLocales: const [Locale('tr', 'TR')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          routerConfig: _router,
          builder: (context, child) => HadiScaffoldMessenger(
            key: rootMessengerKey,
            child: PaletteScope(
              child: SecondFactorGate(child: HadiNoticeHost(child: child ?? const SizedBox.shrink())),
            ),
          ),
        ),
      ),
    );
  }
}

/// Oturum durumuna göre: giriş · bekle · erişim yok · içerik.
class _Gated extends StatelessWidget {
  const _Gated({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    switch (s.kind) {
      case SessionKind.loading:
        return const _Wait();
      case SessionKind.signedOut:
        return const CrewLoginScreen();
      case SessionKind.approved:
        if (s.error != null) return _Message(text: s.error!, onRetry: s.retry);
        // Rol (kimlik talebi) ve atanmış operasyon rolleri (users/{uid}.roleIds) okunana kadar bekle.
        if (!s.rolesReady) return const _Wait();
        return ListenableBuilder(
          listenable: Capabilities.instance,
          builder: (context, _) {
            if (hasCrewAccess(s)) return child;
            if (!Capabilities.instance.ready) return const _Wait();
            return const _Message(text: 'HADİ Crew yalnızca ekibe açık. Yetkin olduğunu düşünüyorsan bir kurucuya yaz.');
          },
        );
      case SessionKind.needsApplication:
      case SessionKind.pending:
      case SessionKind.rejected:
        return const _Message(text: 'HADİ Crew yalnızca ekibe açık.');
    }
  }
}

class _Gate extends StatelessWidget {
  const _Gate({required this.tab});
  final String tab;

  @override
  Widget build(BuildContext context) {
    final section = (tab == 'pano' || tab == 'kuyruklar' || tab == 'tumu') ? null : sectionById(tab);
    if (section == null && tab != 'pano' && tab != 'kuyruklar' && tab != 'tumu') return const _Gated(child: _AppOnlyPage());
    return _Gated(child: _Visible(section: section, tab: tab));
  }
}

class _Visible extends StatelessWidget {
  const _Visible({required this.section, required this.tab});
  final CrewSection? section;
  final String tab;

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.of(context);
    if (section != null && !section!.visible(s)) {
      return const _Message(text: 'Bu bölüm için yetkin yok.', home: true);
    }
    return CrewShell(tab: section == null ? tab : section!.id, section: section);
  }
}

class _Wait extends StatelessWidget {
  const _Wait();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.onRetry, this.home = false});
  final String text;
  final VoidCallback? onRetry;
  final bool home;

  @override
  Widget build(BuildContext context) {
    final s = SessionScope.read(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_outline_rounded, size: 40, color: HadiColors.ink3),
              const SizedBox(height: 14),
              Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 20),
              Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
                if (onRetry != null) FilledButton(onPressed: onRetry, child: const Text('Tekrar dene')),
                if (home) FilledButton(onPressed: () => context.go('/'), child: const Text('Panoya dön')),
                OutlinedButton(onPressed: () => s.signOut(), child: const Text('Çıkış yap')),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _AppOnlyPage extends StatelessWidget {
  const _AppOnlyPage();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.phone_iphone_rounded, size: 40, color: HadiColors.ink3),
              const SizedBox(height: 14),
              const Text('Bu sayfa HADİ uygulamasında açılır.', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => context.go('/'), child: const Text('Panoya dön')),
            ]),
          ),
        ),
      );
}

/// Derleme Firebase web ayarları olmadan yapıldıysa (README › Kurulum › 0).
class CrewConfigMissing extends StatelessWidget {
  const CrewConfigMissing({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Firebase web ayarları eksik. Derlemeyi web_config.json ile yapın (README › Kurulum › 0).', textAlign: TextAlign.center),
            ),
          ),
        ),
      );
}
