import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bulbvpn/shared/air/air_layout.dart';
import 'package:bulbvpn/shared/air/air_phase.dart';
import 'package:bulbvpn/shared/air/horizon_field.dart';
import 'package:bulbvpn/shared/providers/connection_state_provider.dart' as conn;

import '../widgets/speed_test_header.dart';
import '../widgets/speed_test_toast_message.dart';
import '../widgets/speed_test_view.dart';
import '../../application/speed_test_provider.dart';
import '../../models/speed_test_result.dart';

class SpeedTestScreen extends ConsumerStatefulWidget {
  const SpeedTestScreen({super.key});

  @override
  ConsumerState<SpeedTestScreen> createState() => _SpeedTestScreenState();
}

class _SpeedTestScreenState extends ConsumerState<SpeedTestScreen> {
  /// Real measured samples for the current run, oldest first.
  final List<double> _samples = <double>[];
  static const int _maxSamples = 120;

  void _record(SpeedTestState? previous, SpeedTestState next) {
    // A run begins at loading; until the next run starts, the finished trace
    // stays on screen so the last reading keeps its shape.
    if (next.step == SpeedTestStep.loading) {
      _samples.clear();
    }
    if ((next.step == SpeedTestStep.download ||
            next.step == SpeedTestStep.upload) &&
        next.currentSpeed > 0) {
      if (_samples.isEmpty ||
          (_samples.last - next.currentSpeed).abs() > 0.01) {
        _samples.add(next.currentSpeed);
        if (_samples.length > _maxSamples) {
          _samples.removeRange(0, _samples.length - _maxSamples);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(speedTestProvider);
    final connectionState = ref.watch(conn.connectionStateProvider);
    ref.listen<SpeedTestState>(speedTestProvider, _record);

    final tunnelLive =
        connectionState.status == conn.ConnectionStatus.connected;
    final failed = state.errorMessage != null && state.step == SpeedTestStep.ready;

    return HorizonField(
      phase: AirPhase.idle,
      showHorizon: false,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AirLayout.rail),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AirLayout.gutter,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 28),
                      SpeedTestHeader(
                        step: state.step,
                        hasResult: state.testCompleted,
                      ),
                      Expanded(
                        child: SpeedTestView(
                          state: state,
                          samples: _samples,
                          tunnelLive: tunnelLive,
                          onStart: () => ref
                              .read(speedTestProvider.notifier)
                              .startTest(),
                        ),
                      ),
                    ],
                  ),
                  if (failed)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 110,
                      child: SpeedTestToastMessage(
                        message: state.errorMessage!,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
