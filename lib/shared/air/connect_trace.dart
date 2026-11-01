import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/air_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'air_phase.dart';

/// The three things the connect path actually does. The trace names the work
/// instead of showing an indeterminate spinner, so a 20–40 second multi-path
/// dial reads as progress rather than as a hang.
enum ConnectStage { wake, dial, verify }

ConnectStage? connectStageFor(AirPhase phase) => switch (phase) {
  AirPhase.preparing => ConnectStage.wake,
  AirPhase.connecting => ConnectStage.dial,
  AirPhase.verifying => ConnectStage.verify,
  _ => null,
};

class ConnectTrace extends StatelessWidget {
  const ConnectTrace({super.key, required this.stage, this.witness});

  final ConnectStage stage;

  /// Live detail from the controller, e.g. `REALITY · path 2 of 3 · Germany`.
  final String? witness;

  static const _labels = ['wake', 'dial', 'verify'];
  static const _spoken = [
    'waking the engine',
    'opening the path',
    'checking the first byte',
  ];

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'Connection progress. ${_spoken[stage.index]}, '
          'step ${stage.index + 1} of 3.'
          '${witness == null || witness!.isEmpty ? '' : ' $witness.'}',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: SizedBox(
          width: double.infinity,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: stage.index.toDouble()),
              duration: reduced
                  ? Duration.zero
                  : const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (context, progress, _) => LayoutBuilder(
                builder: (context, constraints) => Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _TraceLinePainter(
                          air: air,
                          progress: progress,
                        ),
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < 3; i++)
                          Expanded(
                            child: _TraceStop(
                              label: _labels[i],
                              state: i == stage.index
                                  ? _StopState.active
                                  : (i < stage.index
                                        ? _StopState.done
                                        : _StopState.pending),
                              air: air,
                              reduced: reduced,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (witness != null && witness!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                witness!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.monoValue(color: air.steel, size: 10.5),
              ),
            ],
          ],
          ),
        ),
      ),
    );
  }
}

enum _StopState { done, active, pending }

class _TraceStop extends StatelessWidget {
  const _TraceStop({
    required this.label,
    required this.state,
    required this.air,
    required this.reduced,
  });

  final String label;
  final _StopState state;
  final AirColors air;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final (color, textColor) = switch (state) {
      _StopState.done => (air.ink, air.ink),
      _StopState.active => (air.accent, air.accentInk),
      _StopState.pending => (Colors.transparent, air.steel.withValues(alpha: 0.55)),
    };
    return Column(
      children: [
        SizedBox(
          height: 10,
          child: Center(
            child: state == _StopState.active && !reduced
                ? _PulseDot(air: air, color: color)
                : _Dot(
                    color: color,
                    borderColor: state == _StopState.pending
                        ? air.hairlineStrong
                        : Colors.transparent,
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          style: AppTextStyles.label(
            color: textColor,
            size: 9.5,
            tracking: 0.8,
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.borderColor});

  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: borderColor, width: 1),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.air, required this.color});

  final AirColors air;
  final Color color;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final wave = 0.5 + 0.5 * math.sin(_pulse.value * 2 * math.pi);
        return SizedBox(
          width: 18,
          height: 18,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 10 + wave * 8,
                height: 10 + wave * 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.16 * (1 - wave)),
                ),
              ),
              _Dot(color: widget.color, borderColor: Colors.transparent),
            ],
          ),
        );
      },
    );
  }
}

class _TraceLinePainter extends CustomPainter {
  _TraceLinePainter({required this.air, required this.progress});

  final AirColors air;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final y = 5.0;
    final start = size.width / 6;
    final end = size.width * 5 / 6;
    final base = Paint()
      ..color = air.hairlineStrong
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(start, y), Offset(end, y), base);

    final fill = (progress / 2).clamp(0.0, 1.0);
    if (fill > 0.001) {
      final sweep = Paint()
        ..color = air.accent
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(start, y),
        Offset(start + (end - start) * fill, y),
        sweep,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TraceLinePainter oldDelegate) =>
      oldDelegate.air != air || oldDelegate.progress != progress;
}
