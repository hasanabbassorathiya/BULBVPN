import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/services/firebase_analytics_service.dart';

import '../../modules/main/presentation/widgets/server_sheet.dart';
import '../../modules/main/presentation/screens/main_screen.dart';
import '../../modules/legal/legal_screen.dart';
import '../../modules/onboarding/onboarding_screen.dart';
import '../../modules/splash/presentation/splash_screen.dart';
import '../../modules/settings/presentation/screens/settings_screen.dart';
import '../../modules/speed_test/presentation/screens/speed_test_screen.dart';
import '../../shared/metered/metered_shell.dart';

enum SlideDirection { leftToRight, rightToLeft }

enum DefyxVPNRoutes {
  splash("/splash"),
  legal("/legal"),
  onboarding("/onboarding"),
  main("/main"),
  settings("/settings"),
  speedTest("/speedTest");

  final String route;
  const DefyxVPNRoutes(this.route);

  @override
  String toString() => name;
}

Widget _buildSlideTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
  SlideDirection direction,
) {
  const curve = Curves.fastOutSlowIn;

  final Offset beginOffset, endOffset;
  if (direction == SlideDirection.rightToLeft) {
    beginOffset = const Offset(1.0, 0.0);
    endOffset = const Offset(-1.0, 0.0);
  } else {
    beginOffset = const Offset(-1.0, 0.0);
    endOffset = const Offset(1.0, 0.0);
  }

  final slideAnimation = animation.drive(
    Tween(begin: beginOffset, end: Offset.zero).chain(CurveTween(curve: curve)),
  );

  final slideOutAnimation = secondaryAnimation.drive(
    Tween(begin: Offset.zero, end: endOffset).chain(CurveTween(curve: curve)),
  );

  final fadeAnimation = animation.drive(
    Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: curve)),
  );

  final fadeOutAnimation = secondaryAnimation.drive(
    Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: curve)),
  );

  return Stack(
    children: [
      Transform.translate(
        offset: slideOutAnimation.value,
        child: Opacity(
          opacity: fadeOutAnimation.value,
          child: const SizedBox.shrink(),
        ),
      ),
      Transform.translate(
        offset: slideAnimation.value,
        child: Opacity(opacity: fadeAnimation.value, child: child),
      ),
    ],
  );
}

CustomTransitionPage<void> _createPageAnimation(
  Widget child,
  LocalKey key,
  SlideDirection direction,
) {
  return CustomTransitionPage<void>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        _buildSlideTransition(
          context,
          animation,
          secondaryAnimation,
          child,
          direction,
        ),
  );
}

/// The four tabs torn along the card's foot. Their widths are the comp's: 323,
/// 214, 225 and 262 of the plate's 1024 across, so the torn tab is the widest
/// and SETTINGS earns its length rather than all four splitting evenly.
/// RELAYS is not a route — the tariff sheet is a modal over the face you are
/// already looking at — so it never holds the tear. Only a surface that prints
/// its own face can be the torn tab.
int _meteredTabFor(String path) {
  if (path == DefyxVPNRoutes.speedTest.route) return 2;
  if (path == DefyxVPNRoutes.settings.route) return 3;
  return 0;
}

String _routeForTab(int index) {
  if (index == 2) return DefyxVPNRoutes.speedTest.route;
  if (index == 3) return DefyxVPNRoutes.settings.route;
  return DefyxVPNRoutes.main.route;
}

Future<void> _onMeteredTab(BuildContext context, int index) async {
  if (index != 1) {
    context.go(_routeForTab(index));
    return;
  }
  // Leaving the sheet's owner route mid-audit is not offered: come back to the
  // connect face first, then tear it open on the next frame.
  if (GoRouterState.of(context).uri.path != DefyxVPNRoutes.main.route) {
    context.go(DefyxVPNRoutes.main.route);
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return;
  }
  await showServerSheet(context);
}

final routerProvider = Provider<GoRouter>((ref) {
  final observer = FirebaseAnalyticsService().getAnalyticsObserver();
  return GoRouter(
    initialLocation: DefyxVPNRoutes.splash.route,
    observers: [if (observer != null) observer],
    routes: [
      GoRoute(
        path: DefyxVPNRoutes.splash.route,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: DefyxVPNRoutes.legal.route,
        builder: (context, state) => const LegalScreen(),
      ),
      GoRoute(
        path: DefyxVPNRoutes.onboarding.route,
        builder: (context, state) => const OnboardingScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          final path = state.uri.path;
          return Scaffold(
            extendBody: true,
            body: MeteredShell(
              segments: meteredTabs,
              active: _meteredTabFor(path),
              onSelect: (index) => _onMeteredTab(context, index),
              child: child,
            ),
          );
        },
        routes: [
          GoRoute(
            path: DefyxVPNRoutes.main.route,
            pageBuilder: (context, state) => _createPageAnimation(
              const MainScreen(),
              state.pageKey,
              SlideDirection.leftToRight,
            ),
          ),
          GoRoute(
            path: DefyxVPNRoutes.settings.route,
            pageBuilder: (context, state) => _createPageAnimation(
              const SettingsScreen(),
              state.pageKey,
              SlideDirection.rightToLeft,
            ),
          ),
          GoRoute(
            path: DefyxVPNRoutes.speedTest.route,
            pageBuilder: (context, state) => _createPageAnimation(
              const SpeedTestScreen(),
              state.pageKey,
              SlideDirection.leftToRight,
            ),
          ),
        ],
      ),
    ],
  );
});

final routeInformationProvider =
    ChangeNotifierProvider<GoRouteInformationProvider>(
      (ref) => ref.watch(routerProvider).routeInformationProvider,
    );

final currentRouteProvider = Provider(
  (ref) => ref.watch(routeInformationProvider).value.uri.toString(),
);
