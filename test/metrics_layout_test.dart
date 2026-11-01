import 'package:bulbvpn/core/theme/app_theme.dart';
import 'package:bulbvpn/modules/speed_test/application/speed_test_provider.dart';
import 'package:bulbvpn/modules/speed_test/models/speed_test_result.dart';
import 'package:bulbvpn/modules/speed_test/presentation/widgets/speed_metrics_row.dart';
import 'package:bulbvpn/modules/speed_test/presentation/widgets/speed_test_view.dart';
import 'package:bulbvpn/modules/speed_test/presentation/widgets/speed_waveform.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size physicalSize = const Size(1080, 2400),
  double pixelRatio = 2.625,
  double textScale = 1,
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(393, 852),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) => MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true,
            ),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('completed result shows three figures without overflow', (
    tester,
  ) async {
    const result = SpeedTestResult(
      downloadSpeed: 1.9,
      uploadSpeed: 2.3,
      ping: 271,
      latency: 451,
      packetLoss: 0,
      jitter: 423,
    );
    await _pump(
      tester,
      SpeedTestView(
        state: const SpeedTestState(
          step: SpeedTestStep.ready,
          result: result,
          testCompleted: true,
        ),
        samples: const [0.4, 0.9, 1.6, 1.9],
        tunnelLive: true,
        onStart: () {},
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(SpeedWaveform), findsOneWidget);
    expect(find.byType(SpeedMetricsRow), findsOneWidget);
    Finder metric(String value) => find.descendant(
      of: find.byType(SpeedMetricsRow),
      matching: find.text(value),
    );
    expect(metric('DOWNLOAD'), findsOneWidget);
    expect(metric('1.9'), findsOneWidget);
    expect(metric('UPLOAD'), findsOneWidget);
    expect(metric('2.3'), findsOneWidget);
    expect(metric('PING'), findsOneWidget);
    expect(metric('271'), findsOneWidget);
    expect(find.text('Through the tunnel'), findsOneWidget);
    expect(find.text('Test again'), findsOneWidget);
  });

  testWidgets('unmeasured figures are dashes, not zeros', (tester) async {
    await _pump(
      tester,
      SpeedTestView(
        state: const SpeedTestState(),
        samples: const [],
        tunnelLive: false,
        onStart: () {},
      ),
    );

    expect(tester.takeException(), isNull);
    // One dash for the live figure, three for the unmeasured metrics.
    expect(find.text('—'), findsNWidgets(4));
    expect(find.text('Start test'), findsOneWidget);
    expect(find.text('Direct measurement — tunnel is off'), findsOneWidget);
  });

  testWidgets('narrow 320x568 at 1.3 text scale survives long readings', (
    tester,
  ) async {
    await _pump(
      tester,
      SpeedTestView(
        state: const SpeedTestState(
          step: SpeedTestStep.download,
          currentSpeed: 1234.6,
          result: SpeedTestResult(downloadSpeed: 1234.6, ping: 1234),
        ),
        samples: const [0.2, 2.4, 18.0, 120.0, 1234.6],
        tunnelLive: true,
        onStart: () {},
      ),
      physicalSize: const Size(640, 1136),
      pixelRatio: 2,
      textScale: 1.3,
    );

    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byType(SpeedMetricsRow),
        matching: find.text('1234.6'),
      ),
      findsOneWidget,
    );
    expect(find.text('Testing…'), findsOneWidget);
  });
}
