import 'dart:io';

import 'package:bulbvpn/app/router/app_router.dart';
import 'package:bulbvpn/core/theme/app_theme.dart';
import 'package:bulbvpn/modules/core/vpn_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:bulbvpn/shared/services/animation_service.dart';
import 'package:bulbvpn/shared/services/vibration_service.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<bool>(
      future: _initializeApp(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const MaterialApp(
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }
        
        _handleAdConfiguration(snapshot);
        return _buildApp(context, ref);
      },
    );
  }

  Future<bool> _initializeApp() async {
    await VibrationService().init();
    await AnimationService().init();
    return true;
  }

  void _handleAdConfiguration(AsyncSnapshot<bool> snapshot) {
    if (!snapshot.hasData) return;

    final shouldUseInternalAds = snapshot.data!;
    if (shouldUseInternalAds) {
      debugPrint('Using internal ads');
    } else {
      _initializeMobileAds();
    }
  }

  Future<void> _initializeMobileAds() async {
    try {
      if (!Platform.isMacOS) {
        await MobileAds.instance.initialize();
      }
    } catch (error) {
      debugPrint('Error initializing Google AdMob: $error');
    }
  }

  Widget _buildApp(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    final designSize = _getDesignSize(context);

    return ScreenUtilInit(
      designSize: designSize,
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) {
        return _VpnInitializer(
          child: MaterialApp.router(
            title: 'BULB VPN',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.dark,
            routerConfig: router,
            builder: _appBuilder,
            debugShowCheckedModeBanner: false,
          ),
        );
      },
    );
  }

  Size _getDesignSize(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width > 600;
    final isLargeTablet = size.width > 900;
    final isDesktop = size.width > 1200;

    if (isDesktop) return const Size(1440, 900);
    if (isLargeTablet) return const Size(1024, 768);
    if (isTablet) return const Size(768, 1024);
    return const Size(393, 852);
  }

  Widget _appBuilder(BuildContext context, Widget? child) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.0)),
      child: child ?? const SizedBox.shrink(),
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