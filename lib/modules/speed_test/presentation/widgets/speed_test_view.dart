import 'package:bulbvpn/core/theme/air_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/modules/speed_test/application/speed_test_provider.dart';
import 'package:bulbvpn/modules/speed_test/models/speed_test_result.dart';
import 'package:bulbvpn/modules/speed_test/presentation/widgets/speed_metrics_row.dart';
import 'package:bulbvpn/modules/speed_test/presentation/widgets/speed_waveform.dart';
import 'package:bulbvpn/shared/air/air_buttons.dart';
import 'package:flutter/material.dart';

/// The whole measurement surface: one waveform, three figures, one control.
class SpeedTestView extends StatelessWidget {
  const SpeedTestView({
    super.key,
    required this.state,
    required this.samples,
    required this.tunnelLive,
    required this.onStart,
  });

  final SpeedTestState state;
  final List<double> samples;
  final bool tunnelLive;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final step = state.step;
    final running =
        step == SpeedTestStep.download || step == SpeedTestStep.upload;
    final waiting = step == SpeedTestStep.loading;

    final download = step == SpeedTestStep.download && state.currentSpeed > 0
        ? state.currentSpeed
        : state.result.downloadSpeed;
    final upload = step == SpeedTestStep.upload && state.currentSpeed > 0
        ? state.currentSpeed
        : state.result.uploadSpeed;
    final liveValue = running
        ? state.currentSpeed
        : (state.testCompleted ? state.result.downloadSpeed : 0.0);

    final waveState = switch (step) {
      SpeedTestStep.download || SpeedTestStep.upload => WaveState.running,
      SpeedTestStep.loading => WaveState.idle,
      SpeedTestStep.ready =>
        state.errorMessage != null || state.hadError
            ? WaveState.error
            : state.testCompleted
            ? WaveState.done
            : WaveState.idle,
    };

    final label = running
        ? 'Testing…'
        : state.testCompleted
        ? 'Test again'
        : 'Start test';

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 24, bottom: 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpeedWaveform(
            samples: samples,
            state: waveState,
            liveValue: liveValue,
            note: tunnelLive
                ? 'Through the tunnel'
                : 'Direct measurement — tunnel is off',
          ),
          const SizedBox(height: 28),
          SpeedMetricsRow(
            download: download,
            upload: upload,
            ping: state.result.ping,
          ),
          const SizedBox(height: 28),
          AirButton.primary(
            label: label,
            height: 52,
            onPressed: running || waiting ? null : onStart,
          ),
          if (waiting) ...[
            const SizedBox(height: 12),
            Text(
              'Waiting for a usable network before measuring.',
              textAlign: TextAlign.center,
              style: AppTextStyles.monoValue(color: air.steel, size: 11),
            ),
          ],
        ],
      ),
    );
  }
}
