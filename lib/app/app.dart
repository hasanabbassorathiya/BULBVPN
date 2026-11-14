import 'package:bulbvpn/app/router/app_router.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/theme/simple_colors.dart';
import 'package:bulbvpn/core/theme/simple_theme.dart';
import 'package:bulbvpn/l10n/app_localizations.dart';
import 'package:bulbvpn/modules/core/vpn_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bulbvpn/shared/services/animation_service.dart';
import 'package:bulbvpn/shared/services/vibration_service.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  late final Future<bool> _startup = _initializeApp();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _startup,
      builder: (context, snapshot) {
        // A failed service init must still boot the app: without this the
        // frame would hold the wordmark forever and the VPN would never be
        // reachable.
        if (!snapshot.hasData && !snapshot.hasError) {
          return const _StartupFrame();
        }
        return _buildApp(context, ref);
      },
    );
  }

  Future<bool> _initializeApp() async {
    await VibrationService().init();
    await AnimationService().init();
    return true;
  }

  Widget _buildApp(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return _VpnInitializer(
      child: MaterialApp.router(
        title: 'BULB VPN',
        theme: SimpleTheme.dark,
        darkTheme: SimpleTheme.dark,
        themeMode: ThemeMode.dark,
        routerConfig: router,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en'),
          Locale('fa'),
        ],
        builder: _appBuilder,
        debugShowCheckedModeBanner: false,
      ),
    );
  }

  Widget _appBuilder(BuildContext context, Widget? child) {
    return child ?? const SizedBox.shrink();
  }
}

/// The frame shown while the two services start. It carries the theme and the
/// same `ground` as the native launch window and the splash, so startup is one
/// surface; the default un-themed `MaterialApp` here flashed Material's purple
/// seed and a spinner, which is the one thing DESIGN.md §9 forbids on a state.
class _StartupFrame extends StatelessWidget {
  const _StartupFrame();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: SimpleTheme.dark,
      darkTheme: SimpleTheme.dark,
      themeMode: ThemeMode.dark,
      home: Builder(
        builder: (context) {
          final simple = context.simple;
          return Scaffold(
            backgroundColor: simple.background,
            body: SafeArea(
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      'BULB',
                      style: AppTextStyles.display(
                        color: simple.ink,
                        size: 26,
                        weight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'VPN',
                      style: AppTextStyles.display(
                        color: simple.connected,
                        size: 26,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VpnInitializer extends ConsumerStatefulWidget {
  final Widget child;
  const _VpnInitializer({required this.child});

  @override
  ConsumerState<_VpnInitializer> createState() => _VpnInitializerState();
}

class _VpnInitializerState extends ConsumerState<_VpnInitializer> {
  bool _vpnInitAttempted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_vpnInitAttempted) {
      _vpnInitAttempted = true;
      _initVpn();
    }
  }

  Future<void> _initVpn() async {
    try {
      final container = ProviderScope.containerOf(context);
      final vpnController = VpnController();
      await vpnController.initialize(container);
    } catch (e, stackTrace) {
      debugPrint('[App] ERROR initializing VPN controller: $e');
      debugPrint('[App] Stack trace: $stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
