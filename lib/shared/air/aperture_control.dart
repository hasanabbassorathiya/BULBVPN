import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/air_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'air_phase.dart';

/// The single large control: a 96 px instrument aperture that opens as the
/// tunnel comes up. No rings, no glow, no rotation.
const int _kMotionMs = 4906; // one 2π sweep of the busy arc

class ApertureControl extends StatefulWidget {
  const ApertureControl({
    super.key,
    required this.phase,
    required this.onTap,
    this.size = 96,
    this.caption,
  });

  final AirPhase phase;
  final VoidCallback onTap;
  final double size;
  final String? caption;

  @override
  State<ApertureControl> createState() => _ApertureControlState();
}

class _ApertureControlState extends State<ApertureControl>
    with TickerProviderStateMixin {
  static const double _minHit = 120;
  static const double _rate = 4; // opening units per second

  late final AnimationController _opening;
  late final AnimationController _motion;
  late final AnimationController _press;
  late final AnimationController _breath;

  static double _targetFor(AirPhase phase) => switch (phase) {
    AirPhase.idle => 0.30,
    AirPhase.preparing => 0.38,
    AirPhase.connecting => 0.56,
    AirPhase.verifying => 0.76,
    AirPhase.connected => 1.0,
    AirPhase.closing => 0.20,
    AirPhase.failed => 0.14,
    AirPhase.offline => 0.14,
  };

  @override
  void initState() {
    super.initState();
    _opening = AnimationController(
      vsync: this,
      value: _targetFor(widget.phase),
    );
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _kMotionMs),
    );
    _press = AnimationController(
      vsync: this,
      lowerBound: 0.9,
      upperBound: 1.04,
      value: 1,
    );
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduced) {
      _opening.value = _targetFor(widget.phase);
    }
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant ApertureControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) {
      _moveTo(widget.phase);
      _syncMotion();
    }
  }

  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  void _moveTo(AirPhase phase) {
    final target = _targetFor(phase);
    if (_reduced) {
      _opening.value = target;
      return;
    }
    final delta = (target - _opening.value).abs();
    if (delta < 0.001) return;
    _opening.animateTo(
      target,
      duration: Duration(milliseconds: (delta / _rate * 1000).round()),
      curve: Curves.easeOutCubic,
    );
  }

  void _syncMotion() {
    final run = !_reduced &&
        (widget.phase.isBusy || widget.phase == AirPhase.connected);
    if (run) {
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      _motion.stop();
      _motion.value = 0;
    }
    // A resting aperture still breathes, slowly enough to read as "ready"
    // rather than as another progress indicator.
    if (!_reduced && widget.phase == AirPhase.idle) {
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
    } else {
      _breath.stop();
      _breath.value = 0;
    }
  }

  void _onTapDown(TapDownDetails _) {
    HapticFeedback.lightImpact();
    _press.animateTo(
      0.97,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
    );
  }

  void _release() {
    _press.animateTo(
      1.0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
    );
  }

  @override
  void dispose() {
    _opening.dispose();
    _motion.dispose();
    _press.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final hit = math.max(widget.size, _minHit);
    final label = widget.phase == AirPhase.connected ? 'Disconnect' : 'Connect';
    final caption = widget.caption;

    return Semantics(
      button: true,
      label: label,
      value: widget.phase.word,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: _onTapDown,
            onTapUp: (_) => _release(),
            onTapCancel: _release,
            onTap: widget.onTap,
            child: RepaintBoundary(
              child: SizedBox(
                width: hit,
                height: hit,
                child: Center(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _opening,
                      _motion,
                      _press,
                      _breath,
                    ]),
                    builder: (context, _) => Transform.scale(
                      scale: _press.value,
                      child: SizedBox(
                        width: widget.size,
                        height: widget.size,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: air.surface,
                            border: Border.all(
                              color: air.hairlineStrong,
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: air.shadow,
                                offset: const Offset(0, 6),
                                blurRadius: 18,
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: CustomPaint(
                              painter: _AperturePainter(
                                air: air,
                                phase: widget.phase,
                                opening: _opening.value,
                                motion: _motion.value,
                                breath: _breath.value,
                                animate: !reduced,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (caption != null)
            Transform.translate(
              offset: const Offset(0, -2),
              child: Text(
                caption,
                textAlign: TextAlign.center,
                style: AppTextStyles.label(color: air.steel, size: 10.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _AperturePainter extends CustomPainter {
  _AperturePainter({
    required this.air,
    required this.phase,
    required this.opening,
    required this.motion,
    required this.breath,
    required this.animate,
  });

  final AirColors air;
  final AirPhase phase;
  final double opening;
  final double motion;
  final double breath;
  final bool animate;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final swell = 1 + 0.014 * math.sin(breath * math.pi);
    final openR = r * 0.72 * opening * swell;
    final connected = phase == AirPhase.connected;

    final fill = Paint()..style = PaintingStyle.fill;
    if (connected) {
      fill.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [air.skyTop, air.accentWash],
      ).createShader(Rect.fromCircle(center: center, radius: openR));
    } else {
      fill.color = air.sunken;
    }
    canvas.drawCircle(center, openR, fill);

    final blade = Paint()
      ..color = air.ink.withValues(alpha: 0.12)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final angle = -math.pi / 2 + i * math.pi / 3;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final inner = openR + 5;
      final outer = r - 2;
      if (outer <= inner) continue;
      canvas.drawLine(center + direction * inner, center + direction * outer, blade);
    }

    if (connected) {
      canvas.drawCircle(center + const Offset(0, -8), 6, Paint()..color = air.sun);

      if (animate && openR > 6) {
        final drift = (motion * _kMotionMs / 1000 * 6) % 24;
        final flow = Paint()
          ..color = air.accentInk.withValues(alpha: 0.18)
          ..strokeWidth = 1;
        canvas.save();
        canvas.clipPath(
          Path()..addOval(Rect.fromCircle(center: center, radius: openR)),
        );
        for (var i = 0; i < 3; i++) {
          final y = center.dy + (i - 1) * 7.0;
          for (var x = -openR - 24; x < openR + 24; x += 24) {
            final start = Offset(center.dx + x + drift, y);
            canvas.drawLine(start, start + const Offset(18, 0), flow);
          }
        }
        canvas.restore();
      }
    }

    if (phase.isBusy && animate) {
      final start = motion * 2 * math.pi - math.pi / 2;
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = air.accent;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r - 3),
        start,
        1.6,
        false,
        arc,
      );
    }

    if (phase.isFault) {
      final rim = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = air.alertInk;
      canvas.drawCircle(center, r - 3, rim);
      final bar = Paint()
        ..color = air.alertInk
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        center - const Offset(7, 0),
        center + const Offset(7, 0),
        bar,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AperturePainter oldDelegate) =>
      oldDelegate.air != air ||
      oldDelegate.phase != phase ||
      oldDelegate.opening != opening ||
      oldDelegate.motion != motion ||
      oldDelegate.breath != breath ||
      oldDelegate.animate != animate;
}
