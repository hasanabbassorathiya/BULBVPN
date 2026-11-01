import 'package:bulbvpn/core/theme/app_theme.dart';
import 'package:bulbvpn/modules/monetization/paywall_screen.dart';
import 'package:bulbvpn/modules/settings/presentation/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  Size physicalSize = const Size(1080, 6000),
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) => ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: screen,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('settings is a hairline ledger with honest disclosures', (
    tester,
  ) async {
    await _pump(tester, const SettingsScreen());

    expect(tester.takeException(), isNull);
    expect(find.text('Tunnel'), findsOneWidget);
    expect(find.text('CONNECTION'), findsOneWidget);
    expect(find.text('Protocol'), findsOneWidget);
    expect(find.text('Automatic'), findsOneWidget);
    // Bootstrap relays are visible as community sources, with the warning.
    expect(find.text('Relay sources'), findsOneWidget);
    expect(find.textContaining('can see your traffic'), findsOneWidget);
    expect(find.text('NOT PRIVATE'), findsOneWidget);
    // Diagnostics are off the surface; the log lives behind a long press on
    // the build number. Support appears only when SUPPORT_URL is configured.
    expect(find.text('Connection logs'), findsNothing);
    expect(find.text('Copy support blob'), findsNothing);
    expect(find.text('Support'), findsNothing);
    expect(find.text('Share BULBVPN'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Terms'), findsOneWidget);
    expect(find.text('Version'), findsOneWidget);
  });

  testWidgets('settings survives 360x640 at 1.3 scale', (tester) async {
    await _pump(
      tester,
      const SettingsScreen(),
      physicalSize: const Size(1080, 1920),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Tunnel'), findsOneWidget);
  });

  testWidgets('paywall separates Free and Premium without inventing prices', (
    tester,
  ) async {
    await _pump(tester, const PremiumScreen());

    expect(tester.takeException(), isNull);
    expect(find.text('A quieter tunnel.'), findsOneWidget);
    expect(find.text('FREE'), findsOneWidget);
    // The section heading names the plan; the app bar already carries the title.
    expect(find.text('PREMIUM'), findsOneWidget);
    expect(find.text('Priority relays'), findsOneWidget);
    expect(find.text('No ads'), findsOneWidget);
    // No store keys in this build: say so instead of showing a fake price.
    expect(find.text('Store setup is not live in this build'), findsOneWidget);
    expect(find.textContaining('€'), findsNothing);
    expect(find.textContaining(r'$'), findsNothing);
  });

  testWidgets('paywall survives 360x640 at 1.3 scale', (tester) async {
    await _pump(
      tester,
      const PremiumScreen(),
      physicalSize: const Size(1080, 1920),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('A quieter tunnel.'), findsOneWidget);
  });
}
