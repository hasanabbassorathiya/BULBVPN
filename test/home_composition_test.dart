import 'package:bulbvpn/core/theme/app_theme.dart';
import 'package:bulbvpn/modules/core/trust_tier.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/home_composition.dart';
import 'package:bulbvpn/shared/air/air_phase.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  HomeViewState state({
    AirPhase phase = AirPhase.idle,
    String title = 'Standby',
    String detail = 'path closed · Auto',
    String relay = 'Auto',
    bool live = false,
    TrustTier? tier = TrustTier.bootstrap,
    String exitIp = '',
    String exitLocation = '',
  }) {
    return HomeViewState(
      phase: phase,
      statusTitle: title,
      statusDetail: detail,
      networkLabel: 'Wi-Fi · HomeNet',
      clockLabel: live ? '00:04:12' : '12:00',
      pingLabel: '42',
      downLabel: live ? '1.2 Mbps' : '—',
      upLabel: live ? '240 Kbps' : '—',
      protocolLabel: live ? 'SoftEther' : 'Automatic',
      relayLabel: relay,
      exitIp: exitIp,
      exitLocation: exitLocation,
      flagCode: 'jp',
      trustTier: tier,
      live: live,
    );
  }

  Widget harness({
    required HomeViewState view,
    required Size size,
    bool rtl = false,
    double textScale = 1.3,
  }) {
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) => MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: HomeComposition(
            state: view,
            onConnect: () {},
            onOpenServers: () {},
            onRefreshIps: () {},
            onCopyIp: () {},
          ),
        ),
      ),
    );
  }

  Future<void> pumpAt(WidgetTester tester, Size size, Widget widget) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
  }

  for (final size in const [Size(390, 844), Size(360, 640)]) {
    testWidgets('idle home shows Standby and the connect aperture at $size', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpAt(tester, size, harness(view: state(), size: size));

      expect(find.text('Standby'), findsOneWidget);
      expect(find.bySemanticsLabel('Connect'), findsOneWidget);
      // A closed tunnel has no exit to measure and nothing to refresh.
      expect(find.text('Exit · closed'), findsOneWidget);
      expect(find.text('Exit · measuring'), findsNothing);
      expect(find.byTooltip('Refresh exit IP'), findsNothing);
      expect(tester.takeException(), isNull);
      handle.dispose();
    });

    testWidgets('live home states the proof and the trust tier at $size', (
      tester,
    ) async {
      await pumpAt(
        tester,
        size,
        harness(
          view: state(
            phase: AirPhase.connected,
            title: 'Connected',
            detail: 'traffic confirmed · Japan',
            relay: 'Japan',
            live: true,
            exitIp: '203.0.113.7',
            exitLocation: 'Tokyo · Example ISP',
          ),
          size: size,
        ),
      );

      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('traffic confirmed · Japan'), findsOneWidget);
      expect(find.text('203.0.113.7'), findsOneWidget);
      expect(find.byTooltip('Refresh exit IP'), findsOneWidget);
      // Public bootstrap relays must never appear private, in the shelf and in
      // the destination row.
      expect(find.textContaining('NOT PRIVATE'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('RTL keeps the status block anchored to the right edge', (
    tester,
  ) async {
    const size = Size(390, 844);
    await pumpAt(tester, size, harness(view: state(), size: size, rtl: true));

    final title = find.text('Standby');
    expect(title, findsOneWidget);
    final right = tester.getTopRight(title).dx;
    expect(
      right,
      greaterThan(size.width / 2),
      reason: 'status title must start from the right side in RTL',
    );
    expect(right, lessThanOrEqualTo(size.width - 22));
    expect(tester.takeException(), isNull);
  });
}
