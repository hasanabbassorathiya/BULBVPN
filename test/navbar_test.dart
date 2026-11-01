import 'package:bulbvpn/core/theme/air_colors.dart';
import 'package:bulbvpn/core/theme/app_theme.dart';
import 'package:bulbvpn/shared/layout/navbar/defyx_navbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GoRouter _router() {
  Widget blank(BuildContext context, GoRouterState state) =>
      const SizedBox.shrink();
  return GoRouter(
    initialLocation: '/main',
    routes: [
      ShellRoute(
        builder: (context, state, child) => Scaffold(
          body: child,
          bottomNavigationBar: const DefyxNavBar(),
        ),
        routes: [
          GoRoute(path: '/main', builder: blank),
          GoRoute(path: '/speedTest', builder: blank),
          GoRoute(path: '/settings', builder: blank),
        ],
      ),
    ],
  );
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) => ProviderScope(
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: _router(),
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

Color? _labelColor(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style?.color;

void main() {
  testWidgets('three destinations and two actions, no overflow at 1.3', (
    tester,
  ) async {
    await _pump(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Servers'), findsOneWidget);
    expect(find.text('Speed'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('Share BULBVPN'), findsNothing);

    // On the connect surface, Connect is the marked destination.
    expect(_labelColor(tester, 'Connect'), AirColors.day.ink);
    expect(_labelColor(tester, 'Speed'), AirColors.day.steel);
  });

  testWidgets('tapping Speed moves the active mark and the route', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.text('Speed'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      GoRouter.of(tester.element(find.byType(DefyxNavBar))).state.uri.path,
      '/speedTest',
    );
    expect(_labelColor(tester, 'Speed'), AirColors.day.ink);
    expect(_labelColor(tester, 'Connect'), AirColors.day.steel);
  });
}
