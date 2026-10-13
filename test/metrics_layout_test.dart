import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bulbvpn/modules/speed_test/models/speed_test_result.dart';
import 'package:bulbvpn/modules/speed_test/presentation/widgets/speed_test_metrics/speed_test_metrics.dart';
import 'package:bulbvpn/modules/speed_test/presentation/widgets/speed_test_progress/speed_test_progress_indicator.dart';
import 'package:bulbvpn/shared/providers/connection_state_provider.dart';

void main() {
  testWidgets('completed-ready metrics layout has no overflow', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    const result = SpeedTestResult(
      downloadSpeed: 1.9,
      uploadSpeed: 2.3,
      ping: 271,
      latency: 451,
      packetLoss: 0,
      jitter: 423,
    );

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(393, 852),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SpeedTestProgressIndicator(
                progress: 0.0,
                color: Colors.green,
                showButton: true,
                result: result,
                connectionStatus: ConnectionStatus.disconnected,
                button: const SizedBox(width: 60, height: 60),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final metrics = find.byType(SpeedTestMetricsDisplay);
    expect(metrics, findsOneWidget);
    final rect = tester.getRect(metrics);
    debugPrint('METRICS RECT: $rect');

    final cols = find.descendant(of: metrics, matching: find.byType(Expanded));
    expect(cols, findsNWidgets(2));
    final leftRect = tester.getRect(cols.first);
    debugPrint('LEFT COLUMN RECT: $leftRect');

    final labels = find.text('DOWNLOAD');
    if (labels.evaluate().isNotEmpty) {
      final labelRect = tester.getRect(labels);
      debugPrint('DOWNLOAD label rect: $labelRect');
      expect(labelRect.width, lessThanOrEqualTo(leftRect.width + 0.5));
    }
    final labelsUp = find.text('UPLOAD');
    if (labelsUp.evaluate().isNotEmpty) {
      debugPrint('UPLOAD label rect: ${tester.getRect(labelsUp)}');
    }

    final exception = tester.takeException();
    debugPrint('EXCEPTION: $exception');
    expect(exception, isNull);
  });
}
