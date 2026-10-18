import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:bulbvpn/modules/speed_test/application/speed_test_provider.dart';
import 'package:bulbvpn/modules/speed_test/models/speed_test_result.dart';
import 'package:bulbvpn/modules/speed_test/presentation/widgets/speed_test_metrics/speed_test_metrics.dart';
import 'package:bulbvpn/modules/speed_test/presentation/widgets/speed_test_progress/speed_test_progress_indicator.dart';
import 'package:bulbvpn/modules/speed_test/presentation/widgets/speed_test_start_button.dart';
import 'package:bulbvpn/shared/providers/connection_state_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class SpeedTestReadyState extends ConsumerWidget {
  final VoidCallback onRetry;

  const SpeedTestReadyState({
    super.key,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(speedTestProvider);
    final connectionState = ref.watch(connectionStateProvider);

    void handleStartTest() {
      final status = connectionState.status;

      if (status == ConnectionStatus.disconnected || status == ConnectionStatus.connected) {
        ref.read(speedTestProvider.notifier).startTest();
      } else {
        debugPrint(
            'Button clicked but connection status is $status. Will start when connection is valid.');
      }
    }

    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: 120.h),
      child: Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        SizedBox(height: 30.h),
        SpeedTestProgressIndicator(
          progress: state.testCompleted ? 1 : 0,
          color: AppColors.downloadColor,
          showButton: true,
          result: state.result,
          connectionStatus: connectionState.status,
          button: InkWell(
            onTap: state.testCompleted ? onRetry : handleStartTest,
            child: Column(
              spacing: 8.h,
              children: [
                Text(
                  state.testCompleted ? 'TEST AGAIN' : 'TAP HERE',
                  style: TextStyle(
                    color: AppColors.steel,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SpeedTestStartButton(
                  currentStep: SpeedTestStep.ready,
                  isEnabled: true,
                  onTap: state.testCompleted ? onRetry : handleStartTest,
                  previousStep: state.testCompleted ? SpeedTestStep.download : null,
                ),
              ],
            ),
          ),
        ),
        if (state.testCompleted) ...[
          SizedBox(height: 12.h),
          SpeedTestMetricsDisplay(
            downloadSpeed: state.result.downloadSpeed,
            uploadSpeed: state.result.uploadSpeed,
            ping: state.result.ping,
            latency: state.result.latency,
            packetLoss: state.result.packetLoss,
            jitter: state.result.jitter,
            showDownload: true,
            showUpload: true,
            connectionStatus: connectionState.status,
          ),
        ],
      ],
      ),
    );
  }
}
