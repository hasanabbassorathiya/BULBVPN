import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bulbvpn/core/theme/app_colors.dart';
import 'package:bulbvpn/shared/providers/connection_state_provider.dart';

/// Screen background: state aura gradient (graphite → amber → emerald → red)
/// with a perpetual radar sweep motif at ~6% opacity (DESIGN.md §1, §6).
class MainScreenBackground extends StatefulWidget {
  final Widget child;
  final ConnectionStatus connectionStatus;

  const MainScreenBackground({
    super.key,
    required this.child,
    required this.connectionStatus,
  });

  @override
  State<MainScreenBackground> createState() => _MainScreenBackgroundState();
}

class _MainScreenBackgroundState extends State<MainScreenBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep =
      AnimationController(vsync: this, duration: const Duration(seconds: 60))
        ..repeat();

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: AppColors.canvas,
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: _gradientFor(widget.connectionStatus),
        ),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _sweep,
                  builder: (context, _) => CustomPaint(
                    painter: _RadarPainter(_sweep.value),
                  ),
                ),
              ),
              widget.child,
            ],
          ),
        ),
      ),
    );
  }

  LinearGradient _gradientFor(ConnectionStatus status) {
    const stops = [0.0, 0.55, 1.0];
    switch (status) {
      case ConnectionStatus.connected:
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.topGradient,
            AppColors.middleGradientConnected,
            AppColors.bottomGradientConnected,
          ],
          stops: stops,
        );
      case ConnectionStatus.noInternet:
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.topGradient,
            AppColors.middleGradientNoInternet,
            AppColors.bottomGradientNoInternet,
          ],
          stops: stops,
        );
      case ConnectionStatus.error:
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.topGradient,
            AppColors.middleGradientFailedToConnect,
            AppColors.bottomGradientFailedToConnect,
          ],
          stops: stops,
        );
      case ConnectionStatus.loading:
      case ConnectionStatus.analyzing:
      case ConnectionStatus.connecting:
      case ConnectionStatus.disconnecting:
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.topGradientConnecting,
            AppColors.middleGradientConnecting,
            AppColors.bottomGradientConnecting,
          ],
          stops: stops,
        );
      case ConnectionStatus.disconnected:
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.topGradientReadyToConnect,
            AppColors.middleGradient,
            AppColors.bottomGradient,
          ],
          stops: stops,
        );
    }
  }
}

/// Concentric location rings + crosshair + slow comet sweep. Pure transform
/// motion, repainted behind an opaque content stack at very low alpha.
class _RadarPainter extends CustomPainter {
  _RadarPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.42);
    final radius = math.max(size.width, size.height) * 0.62;

    final line = Paint()
      ..color = const Color(0x0FFFFFFF) // white @ 6%
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final f in const [0.34, 0.67, 1.0]) {
      canvas.drawCircle(center, radius * f, line);
    }

    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      line,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      line,
    );

    // Comet sweep: trailing rays behind the leading angle.
    const rays = 14;
    const span = 0.5; // radians of trail
    final base = progress * 2 * math.pi;
    for (var i = 0; i < rays; i++) {
      final t = i / rays;
      final angle = base - span * t;
      final fade = (1.0 - t);
      final ray = Paint()
        ..color = const Color(0xFFFFFFFF)
            .withValues(alpha: 0.05 * fade * fade)
        ..strokeWidth = 1;
      canvas.drawLine(
        center,
        center + Offset(math.cos(angle), math.sin(angle)) * radius,
        ray,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
