import 'package:bulbvpn/core/theme/app_theme.dart';
import 'package:bulbvpn/modules/legal/legal_screen.dart';
import 'package:bulbvpn/modules/onboarding/onboarding_screen.dart';
import 'package:bulbvpn/shared/air/air_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  String path = '/onboarding',
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: path,
    routes: [
      GoRoute(path: path, builder: (_, __) => screen),
      GoRoute(
        path: '/main',
        builder: (_, __) => const Scaffold(body: Text('MAIN')),
      ),
    ],
  );

  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) => ProviderScope(
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
              disableAnimations: true,
            ),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

VoidCallback? _agreeCallback(WidgetTester tester) => tester
    .widget<InkWell>(
      find.descendant(of: find.byType(AirButton), matching: find.byType(InkWell)),
    )
    .onTap;

void main() {
  testWidgets('onboarding walks the three frames at 1.3 text scale', (
    tester,
  ) async {
    await _pump(tester, const OnboardingScreen());

    expect(tester.takeException(), isNull);
    expect(find.text('Your path, prepared.'), findsOneWidget);
    expect(
      find.textContaining('Bootstrap relays are not private'),
      findsOneWidget,
    );

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Every network is different.'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('One permission.'), findsOneWidget);
    expect(find.text('Allow VPN'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('MAIN'), findsOneWidget);
  });

  testWidgets('onboarding survives a 360x640 screen', (tester) async {
    await _pump(
      tester,
      const OnboardingScreen(),
      size: const Size(360, 640),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Your path, prepared.'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('legal reads as a paper sheet and gates acceptance', (
    tester,
  ) async {
    await _pump(tester, const LegalScreen(), path: '/legal');

    expect(tester.takeException(), isNull);
    expect(find.text('Ground rules'), findsOneWidget);
    expect(find.text('1. How the tunnel works'), findsOneWidget);

    // Agree is inert until the acknowledgement is checked.
    expect(_agreeCallback(tester), isNull);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(_agreeCallback(tester), isNotNull);
  });
}
