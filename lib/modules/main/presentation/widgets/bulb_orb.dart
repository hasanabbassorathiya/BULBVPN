import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:bulbvpn/shared/widgets/staggered_in.dart';

enum BulbPhase { idle, connecting, connected, failed }

/// The signature component (DESIGN.md §4): filament bulb inside
/// counter-rotating tunnel rings. One ticker drives every continuous motion.
class BulbOrb extends StatefulWidget {
  const BulbOrb({
    super.key,
    required this.phase,
    required this.onTap,
    this.size = 210,
  });

  final BulbPhase phase;
  final VoidCallback onTap;
  final double size;

  @override
  State<BulbOrb> createState() => _BulbOrbState();
}

class _BulbOrbState extends State<BulbOrb> with TickerProviderStateMixin {
  late final AnimationController _ticker = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  late final AnimationController _press = AnimationController(
    vsync: this,
    value: 1.0,
    duration: const Duration(milliseconds: 140),
  );

  double _aOuter = 0;
  double _aInner = 0;
  double _aPackets = 0;
  double _speed = 1;
  double _lit = 0;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker.addListener(_tick);
  }

  double get _speedTarget => switch (widget.phase) {
        BulbPhase.connecting => 3.0,
        BulbPhase.connected => 1.5,
        BulbPhase.failed => 0.4,
        BulbPhase.idle => 1.0,
      };

  double get _litTarget => switch (widget.phase) {
        BulbPhase.connecting => 1.0,
        BulbPhase.connected => 1.0,
        BulbPhase.failed => 0.35,
        BulbPhase.idle => 0.5,
      };

  void _tick() {
    final now = _ticker.lastElapsedDuration ?? Duration.zero;
    final dt = now > _last ? (now - _last).inMicroseconds / 1e6 : 0.0;
    _last = now;

    _speed = smoothTowards(_speed, _speedTarget, dt, 4.0);
    _lit = smoothTowards(_lit, _litTarget, dt, 3.0);

    // Tunnel rings: outer clockwise, inner counter-clockwise (transform-only).
    _aOuter = (_aOuter + dt * (2 * math.pi / 18) * _speed) % (2 * math.pi);
    _aInner =
        (_aInner - dt * (2 * math.pi / 26) * _speed) % (2 * math.pi);
    if (widget.phase == BulbPhase.connected) {
      _aPackets = (_aPackets + dt * (2 * math.pi / 9)) % (2 * math.pi);
    }

    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    _press.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    HapticFeedback.lightImpact();
    _press.animateTo(0.94, curve: Curves.easeOut);
  }

  void _onTapUp(TapUpDetails _) {
    _press.animateTo(1.0, duration: const Duration(milliseconds: 400), curve: kSpring);
    widget.onTap();
  }

  void _onTapCancel() {
    _press.animateTo(1.0, duration: const Duration(milliseconds: 400), curve: kSpring);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: true,
      label: 'Connect toggle',
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: AnimatedBuilder(
          animation: Listenable.merge([_press]),
          builder: (context, _) {
            return Transform.scale(
              scale: _press.value,
              child: CustomPaint(
                size: Size.square(widget.size),
                painter: _BulbPainter(
                  phase: widget.phase,
                  aOuter: _aOuter,
                  aInner: _aInner,
                  aPackets: _aPackets,
                  lit: _lit,
                  elapsedSec:
                      (_ticker.lastElapsedDuration ?? Duration.zero).inMicroseconds /
                          1e6,
                  reduceMotion: reduce,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BulbPainter extends CustomPainter {
  _BulbPainter({
    required this.phase,
    required this.aOuter,
    required this.aInner,
    required this.aPackets,
    required this.lit,
    required this.elapsedSec,
    required this.reduceMotion,
  });

  final BulbPhase phase;
  final double aOuter;
  final double aInner;
  final double aPackets;
  final double lit;
  final double elapsedSec;
  final bool reduceMotion;

  Color get _ringColor => switch (phase) {
        BulbPhase.idle => AppColors.graphite,
        BulbPhase.connecting => AppColors.amber,
        BulbPhase.connected => AppColors.amber,
        BulbPhase.failed => AppColors.red,
      };

  Color get _filamentColor => switch (phase) {
        BulbPhase.idle => AppColors.graphite,
        BulbPhase.connecting => AppColors.amber,
        BulbPhase.connected => AppColors.amber,
        BulbPhase.failed => AppColors.red,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final unit = size.shortestSide / 210.0; // design canvas is 210x210
    canvas.translate(c.dx, c.dy);
    canvas.scale(unit);

    final dim = reduceMotion;

    // --- State aura (radial, opacity ≤ 0.18) --------------------------
    final auraStrength = ((lit - 0.3) / 0.7).clamp(0.0, 1.0);
    if (auraStrength > 0) {
      final auraColor = phase == BulbPhase.failed ? AppColors.red : AppColors.amber;
      final aura = Paint()
        ..shader = RadialGradient(
          colors: [
            auraColor.withValues(alpha: 0.10 * auraStrength),
            auraColor.withValues(alpha: 0.14 * auraStrength),
            auraColor.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: 105));
      canvas.drawCircle(Offset.zero, 105, aura);
    }

    // --- Tunnel rings --------------------------------------------------
    final ringAlpha = switch (phase) {
      BulbPhase.idle => 0.55,
      BulbPhase.connecting => 0.75,
      BulbPhase.connected => 0.9,
      BulbPhase.failed => 0.7,
    };
    final ringPaint = Paint()
      ..color = _ringColor.withValues(alpha: ringAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    _drawDashedRing(canvas, 94, aOuter, 44, 0.5, ringPaint);
    _drawDashedRing(canvas, 84, aInner, 36, 0.55, ringPaint);

    // --- Orbiting packets (connected only) -----------------------------
    if (phase == BulbPhase.connected && !dim) {
      final packetPaint = Paint()..color = AppColors.emerald;
      for (var i = 0; i < 4; i++) {
        final ang = aPackets + i * math.pi / 2;
        final pos = Offset(math.cos(ang), math.sin(ang)) * 94;
        canvas.drawCircle(pos, 2.6, packetPaint);
        final tailAng = ang - 0.18;
        final tail = Offset(math.cos(tailAng), math.sin(tailAng)) * 94;
        canvas.drawCircle(tail, 1.6, packetPaint..color = AppColors.emerald.withValues(alpha: 0.35));
      }
    }

    // --- Bulb glass -----------------------------------------------------
    final glassPath = _bulbPath();

    final glassPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1B2130), Color(0xFF0F131C)],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: 50));
    canvas.drawPath(glassPath, glassPaint);

    // Lit interior wash.
    if (lit > 0.05) {
      final tint = phase == BulbPhase.failed ? AppColors.red : AppColors.amber;
      final inner = Paint()
        ..shader = RadialGradient(
          colors: [
            tint.withValues(alpha: 0.16 * lit),
            tint.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: const Offset(0, -8), radius: 44));
      canvas.drawPath(glassPath, inner);
    }

    // Glass outline (hairline).
    canvas.drawPath(
      glassPath,
      Paint()
        ..color = const Color(0x14FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    // --- Filament -------------------------------------------------------
    final filamentPath = _filamentPath();
    // Handshake flicker while connecting.
    var flicker = 1.0;
    if (phase == BulbPhase.connecting && !dim) {
      flicker = 0.55 +
          0.45 *
              (0.5 +
                  0.5 *
                      math.sin(elapsedSec * 31.0) *
                      math.sin(elapsedSec * 11.7));
    } else if (phase == BulbPhase.connected && !dim) {
      flicker = 0.92 + 0.08 * math.sin(elapsedSec * 2.1); // slow breath
    }

    final filColor = _filamentColor;
    final filAlpha = (lit * flicker).clamp(0.0, 1.0);

    if (filAlpha > 0.05) {
      // Soft halo inside the bulb (MaskFilter, not an outer glow).
      canvas.drawPath(
        filamentPath,
        Paint()
          ..color = filColor.withValues(alpha: 0.25 * filAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      // Crisp filament on top.
      canvas.drawPath(
        filamentPath,
        Paint()
          ..color = filColor.withValues(alpha: filAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // --- Base ------------------------------------------------------------
    final basePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF242B3A), Color(0xFF141822)],
      ).createShader(Rect.fromLTWH(-14, 36, 28, 22));
    final baseRRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-13, 38, 26, 17),
      const Radius.circular(4),
    );
    canvas.drawRRect(baseRRect, basePaint);
    canvas.drawRRect(
      baseRRect,
      Paint()
        ..color = const Color(0x14FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    // Screw stripes.
    final stripe = Paint()
      ..color = const Color(0x1FFFFFFF)
      ..strokeWidth = 1.2;
    canvas.drawLine(const Offset(-11, 43), const Offset(11, 43), stripe);
    canvas.drawLine(const Offset(-11, 49), const Offset(11, 49), stripe);
    // Tip contact.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-6, 55, 12, 4),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF2C3446),
    );
  }

  /// Bulb silhouette: glass circle + shoulder + neck (local coords).
  Path _bulbPath() {
    final p = Path();
    // Glass ball.
    p.addOval(Rect.fromCircle(center: const Offset(0, -8), radius: 44));
    // Shoulders into neck.
    final neck = Path()
      ..moveTo(-21, 26)
      ..quadraticBezierTo(-17, 36, -13, 40)
      ..lineTo(13, 40)
      ..quadraticBezierTo(17, 36, 21, 26);
    final combined = Path.combine(PathOperation.union, p, neck);
    return combined;
  }

  /// Leads from base + sine-wave coil inside the glass.
  Path _filamentPath() {
    final p = Path();
    p.moveTo(-8, 38);
    p.lineTo(-13, 14);
    final startX = -13.0;
    const span = 26.0;
    const humps = 5.0;
    const baseline = 14.0;
    const amp = 11.0;
    p.moveTo(startX, baseline);
    for (var x = startX; x <= startX + span; x += 1.0) {
      final phase = (x - startX) / span * humps * math.pi;
      final y = baseline - amp * (1 - math.cos(phase));
      p.lineTo(x, y);
    }
    p.lineTo(13, 14);
    p.lineTo(8, 38);
    return p;
  }

  void _drawDashedRing(
    Canvas canvas,
    double radius,
    double rotation,
    int dashes,
    double fillRatio,
    Paint paint,
  ) {
    canvas.save();
    canvas.rotate(rotation);
    final step = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      final start = i * step;
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: radius),
        start,
        step * fillRatio,
        false,
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BulbPainter old) =>
      old.phase != phase ||
      old.aOuter != aOuter ||
      old.aInner != aInner ||
      old.aPackets != aPackets ||
      old.lit != lit;
}
