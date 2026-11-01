import 'package:bulbvpn/core/theme/app_theme.dart';
import 'package:bulbvpn/shared/air/air_phase.dart';
import 'package:bulbvpn/shared/air/aperture_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget harness({
    required AirPhase phase,
    required VoidCallback onTap,
    bool disableAnimations = false,
    double textScale = 1.0,
  }) {
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) => MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: disableAnimations,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: ApertureControl(
              phase: phase,
              onTap: onTap,
              caption: phase.word.toLowerCase(),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('semantics label follows the phase', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      harness(
        phase: AirPhase.idle,
        onTap: () {},
        disableAnimations: true,
      ),
    );
    expect(find.bySemanticsLabel('Connect'), findsOneWidget);
    expect(find.bySemanticsLabel('Disconnect'), findsNothing);

    await tester.pumpWidget(
      harness(
        phase: AirPhase.connected,
        onTap: () {},
        disableAnimations: true,
      ),
    );
    expect(find.bySemanticsLabel('Disconnect'), findsOneWidget);
    expect(find.bySemanticsLabel('Connect'), findsNothing);
    handle.dispose();
  });

  testWidgets('a tap fires the callback exactly once', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      harness(
        phase: AirPhase.idle,
        onTap: () => taps++,
        disableAnimations: true,
      ),
    );
    await tester.tap(find.byType(ApertureControl));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('reduced motion settles for every phase', (tester) async {
    for (final phase in AirPhase.values) {
      await tester.pumpWidget(
        harness(
          phase: phase,
          onTap: () {},
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'phase $phase');
    }
  });

  testWidgets('96 px face survives text scale 1.3', (tester) async {
    await tester.pumpWidget(
      harness(
        phase: AirPhase.connected,
        onTap: () {},
        disableAnimations: true,
        textScale: 1.3,
      ),
    );
    await tester.pumpAndSettle();

    final face = find.descendant(
      of: find.byType(ApertureControl),
      matching: find.byType(CustomPaint),
    );
    expect(tester.getSize(face.first), const Size(96, 96));
    expect(tester.takeException(), isNull);
  });
}
