import 'dart:math' as math;

import 'package:bulbvpn/core/theme/air_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/utils/format_number.dart';
import 'package:flutter/material.dart';

enum WaveState { idle, running, done, error }

/// The speed surface's instrument: a 96 px band where measured throughput
/// draws left to right on a log scale. Five ticks carry the scale; the live
/// figure sits above it in mono. No gauge, no arc, no shimmer.
class SpeedWaveform extends StatelessWidget {
  const SpeedWaveform({
    super.key,
    required this.samples,
    required this.state,
    required this.liveValue,
    this.note,
  });

  /// Measured Mbps, oldest first. Real samples only.
  final List<double> samples;
  final WaveState state;
  final double liveValue;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final color = switch (state) {
      WaveState.idle => air.steel,
      WaveState.running => air.accent,
      WaveState.done => air.connectedInk,
      WaveState.error => air.alertInk,
    };
    final note = this.note;
    final value = liveValue > 0 ? doubleFormatNumber(liveValue) : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  value,
                  maxLines: 1,
                  style: AppTextStyles.metric(color: air.ink, size: 44),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Mbps',
              style: AppTextStyles.label(color: air.steel, size: 11),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 96,
          width: double.infinity,
          child: ExcludeSemantics(
            child: CustomPaint(
              painter: _WaveformPainter(
                samples: samples,
                color: color,
                baseline: air.hairlineStrong,
                grid: air.hairline,
                tick: air.steel,
              ),
            ),
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 10),
          Text(
            note,
            style: AppTextStyles.monoValue(color: air.steel, size: 11),
          ),
        ],
      ],
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.samples,
    required this.color,
    required this.baseline,
    required this.grid,
    required this.tick,
  });

  static const int capacity = 120;
  static const double _labelBand = 20;
  static const List<String> _ticks = ['0', '1', '10', '100', '1000'];
  static const double _logMax = 1000;

  final List<double> samples;
  final Color color;
  final Color baseline;
  final Color grid;
  final Color tick;

  static double _scale(double mbps) {
    final clamped = mbps.clamp(0.0, _logMax);
    return math.log(clamped + 1) / math.log(_logMax + 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plotHeight = math.max(1.0, size.height - _labelBand);
    final plotBottom = plotHeight;
    final plotWidth = size.width;

    // Scale grid: a hairline at each decade above zero, plus the baseline.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (final value in const [1.0, 10.0, 100.0]) {
      final y = plotBottom - _scale(value) * (plotBottom - 4);
      canvas.drawLine(Offset(0, y), Offset(plotWidth, y), gridPaint);
    }
    final basePaint = Paint()
      ..color = baseline
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, plotBottom),
      Offset(plotWidth, plotBottom),
      basePaint,
    );

    // Five ticks and their labels, evenly spaced decades along the baseline.
    final tickPaint = Paint()
      ..color = tick
      ..strokeWidth = 1;
    for (var i = 0; i < _ticks.length; i++) {
      final x = plotWidth * i / (_ticks.length - 1);
      canvas.drawLine(
        Offset(x, plotBottom),
        Offset(x, plotBottom - 4),
        tickPaint,
      );
      final label = _ticks[i];
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontFamily: AppTextStyles.mono,
            fontSize: 9,
            color: tick,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final left = (x - painter.width / 2)
          .clamp(0.0, math.max(0.0, plotWidth - painter.width))
          .toDouble();
      painter.paint(canvas, Offset(left, plotBottom + 4));
    }

    if (samples.isEmpty) return;

    // The trace: one sample per column of a fixed 120-sample window, so it
    // grows left to right instead of stretching on every reading.
    final step = plotWidth / (capacity - 1);
    final path = Path();
    var started = false;
    final count = math.min(samples.length, capacity);
    for (var i = 0; i < count; i++) {
      final sample = samples[samples.length - count + i];
      final x = i * step;
      final y = plotBottom - _scale(sample) * (plotBottom - 4);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.color != color ||
      old.baseline != baseline ||
      old.grid != grid ||
      old.tick != tick ||
      old.samples.length != samples.length ||
      (samples.isNotEmpty &&
          old.samples.isNotEmpty &&
          old.samples.last != samples.last);
}
