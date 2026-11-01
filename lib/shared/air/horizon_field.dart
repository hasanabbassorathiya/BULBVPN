import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/air_colors.dart';
import 'air_phase.dart';

/// Full-bleed Clear Air ground: sky above the horizon, warm ground below, a
/// sun that appears only when the path is proven, and haze that clears from
/// the aperture outward.
class HorizonField extends StatefulWidget {
  const HorizonField({
    super.key,
    required this.phase,
    required this.child,
    this.horizonFraction = 0.38,
    this.showHorizon = true,
  });

  final AirPhase phase;
  final Widget child;
  final double horizonFraction;

  /// List surfaces keep the gradient but drop the hairline; a line that
  /// crosses rows reads as a rendering fault, not as weather.
  final bool showHorizon;

  @override
  State<HorizonField> createState() => _HorizonFieldState();
}

class _HorizonFieldState extends State<HorizonField>
    with TickerProviderStateMixin {
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );
  late final AnimationController _clear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
    value: widget.phase == AirPhase.connected ? 1 : 0,
  );

  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced) _clear.value = 0;
    _syncAmbient();
  }

  @override
  void didUpdateWidget(covariant HorizonField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phase == oldWidget.phase) return;

    if (_reduced) {
      _clear.value = 0;
    } else if (widget.phase == AirPhase.connected) {
      _clear.animateTo(
        1,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
      );
    } else if (oldWidget.phase == AirPhase.connected) {
      _clear.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
    _syncAmbient();
  }

  void _syncAmbient() {
    final run =
        !_reduced &&
        (widget.phase.isBusy || widget.phase == AirPhase.connected);
    if (run) {
      if (!_ambient.isAnimating) _ambient.repeat();
    } else {
      _ambient.stop();
      _ambient.value = 0;
    }
  }

  @override
  void dispose() {
    _ambient.dispose();
    _clear.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final horizon = widget.horizonFraction;
    final overlay = air.brightness == Brightness.light
        ? SystemUiOverlayStyle.dark
        : SystemUiOverlayStyle.light;

    final atmosphere = _reduced
        ? TweenAnimationBuilder<double>(
            tween: Tween(end: widget.phase == AirPhase.connected ? 0.0 : 1.0),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            builder: (context, hazeFade, _) => RepaintBoundary(
              child: CustomPaint(
                painter: _AtmospherePainter(
                  air: air,
                  horizonFraction: horizon,
                  phase: widget.phase,
                  clear: 0,
                  drift: 0,
                  breath: 1,
                  hazeFade: hazeFade,
                  staticSun: true,
                ),
              ),
            ),
          )
        : AnimatedBuilder(
            animation: Listenable.merge([_ambient, _clear]),
            builder: (context, _) => RepaintBoundary(
              child: CustomPaint(
                painter: _AtmospherePainter(
                  air: air,
                  horizonFraction: horizon,
                  phase: widget.phase,
                  clear: _clear.value,
                  drift: widget.phase.isBusy ? _ambient.value * 6 : 0,
                  breath:
                      0.88 +
                      0.12 *
                          (0.5 + 0.5 * math.sin(_ambient.value * 6 * math.pi)),
                  hazeFade: 1,
                  staticSun: false,
                ),
              ),
            ),
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        extendBody: true,
        backgroundColor: air.ground,
        body: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                painter: _BasePainter(
                  air: air,
                  horizonFraction: horizon,
                  showHorizon: widget.showHorizon,
                ),
              ),
            ),
            atmosphere,
            widget.child,
          ],
        ),
      ),
    );
  }
}

class _BasePainter extends CustomPainter {
  _BasePainter({
    required this.air,
    required this.horizonFraction,
    required this.showHorizon,
  });

  final AirColors air;
  final double horizonFraction;
  final bool showHorizon;

  @override
  void paint(Canvas canvas, Size size) {
    final horizonY = size.height * horizonFraction;

    final sky = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [air.skyTop, air.skyHorizon],
      ).createShader(Rect.fromLTRB(0, 0, size.width, horizonY));
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, horizonY), sky);

    final ground = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [air.groundHorizon, air.groundBottom],
      ).createShader(Rect.fromLTRB(0, horizonY, size.width, size.height));
    canvas.drawRect(
      Rect.fromLTRB(0, horizonY, size.width, size.height),
      ground,
    );

    if (showHorizon) {
      final line = Paint()
        ..color = air.brightness == Brightness.light
            ? air.ink.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.10)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(0, horizonY), Offset(size.width, horizonY), line);
    }
  }

  @override
  bool shouldRepaint(covariant _BasePainter oldDelegate) =>
      oldDelegate.air != air ||
      oldDelegate.horizonFraction != horizonFraction ||
      oldDelegate.showHorizon != showHorizon;
}

class _AtmospherePainter extends CustomPainter {
  _AtmospherePainter({
    required this.air,
    required this.horizonFraction,
    required this.phase,
    required this.clear,
    required this.drift,
    required this.breath,
    required this.hazeFade,
    required this.staticSun,
  });

  final AirColors air;
  final double horizonFraction;
  final AirPhase phase;
  final double clear;
  final double drift;
  final double breath;
  final double hazeFade;
  final bool staticSun;

  static const _bands = [
    (center: 0.12, height: 0.06, alpha: 0.05),
    (center: 0.19, height: 0.07, alpha: 0.08),
    (center: 0.26, height: 0.06, alpha: 0.06),
    (center: 0.33, height: 0.07, alpha: 0.07),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final horizonY = size.height * horizonFraction;
    final full = Offset.zero & size;

    if (hazeFade > 0.001) {
      Path clip = Path()..addRect(full);
      if (clear > 0.001) {
        final radius = clear * size.longestSide * 1.2;
        final hole = Path()
          ..addOval(
            Rect.fromCircle(
              center: Offset(size.width * 0.30, horizonY),
              radius: radius,
            ),
          );
        clip = Path.combine(PathOperation.difference, clip, hole);
      }

      canvas.save();
      canvas.clipPath(clip);
      for (final band in _bands) {
        final centerY = size.height * band.center;
        final height = size.height * band.height;
        final alpha = band.alpha * hazeFade;
        final bandRect = Rect.fromLTWH(
          drift - 12,
          centerY - height / 2,
          size.width + 24,
          height,
        );
        final paint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              air.haze.withValues(alpha: 0),
              air.haze.withValues(alpha: alpha),
              air.haze.withValues(alpha: 0),
            ],
          ).createShader(bandRect);
        canvas.drawRect(bandRect, paint);
      }
      canvas.restore();
    }

    if (phase == AirPhase.connected) {
      final rise = staticSun ? 1.0 : clear;
      canvas.drawCircle(
        Offset(size.width * 0.72, horizonY - 28 - 8 * rise),
        22,
        Paint()..color = air.sun.withValues(alpha: breath),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AtmospherePainter oldDelegate) =>
      oldDelegate.air != air ||
      oldDelegate.horizonFraction != horizonFraction ||
      oldDelegate.phase != phase ||
      oldDelegate.clear != clear ||
      oldDelegate.drift != drift ||
      oldDelegate.breath != breath ||
      oldDelegate.hazeFade != hazeFade ||
      oldDelegate.staticSun != staticSun;
}
