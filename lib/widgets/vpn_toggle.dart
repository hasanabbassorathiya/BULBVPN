import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../providers/vpn_provider.dart';

class VPNToggle extends StatefulWidget {
  const VPNToggle({super.key});

  @override
  State<VPNToggle> createState() => _VPNToggleState();
}

class _VPNToggleState extends State<VPNToggle> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _scaleController;
  late AnimationController _rotateController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scaleController.dispose();
    _rotateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VPNProvider>(
      builder: (context, vpn, _) {
        final isConnected = vpn.isConnected;
        final isConnecting = vpn.isConnecting;

        if (isConnected) {
          if (!_pulseController.isAnimating) {
            _pulseController.repeat(reverse: true);
          }
        } else {
          _pulseController.stop();
          _pulseController.value = 0;
        }

        if (isConnecting) {
          if (!_rotateController.isAnimating) {
            _rotateController.repeat();
          }
        } else {
          _rotateController.stop();
          _rotateController.value = 0;
        }

        return Semantics(
          label: isConnected ? 'VPN connected' : 'VPN disconnected',
          hint: 'Tap to ${isConnected ? 'disconnect' : 'connect'} VPN',
          button: true,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _scaleController.forward(from: 0.95);
              vpn.toggleConnection();
            },
            child: AnimatedBuilder(
              animation: Listenable.merge([_pulseController, _scaleController, _rotateController]),
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleController.value,
                  child: SizedBox(
                    width: 180,
                    height: 180,
                    child: CustomPaint(
                      painter: _TogglePainter(
                        progress: _pulseController.value,
                        isConnected: isConnected,
                        isConnecting: isConnecting,
                        rotation: _rotateController.value,
                      ),
                      child: Center(
                        child: _buildIcon(isConnected, isConnecting),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildIcon(bool isConnected, bool isConnecting) {
    if (isConnecting) {
      return AnimatedBuilder(
        animation: _rotateController,
        builder: (context, child) {
          return Transform.rotate(
            angle: _rotateController.value * 2 * math.pi,
            child: const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.warning,
              ),
            ),
          );
        },
      );
    }

    if (isConnected) {
      return Icon(
        Icons.shield,
        size: 60,
        color: AppColors.connected,
        shadows: [
          Shadow(
            color: AppColors.connected.withValues(alpha: 0.6),
            blurRadius: 20,
          ),
        ],
      );
    }

    return const Icon(
      Icons.shield_outlined,
      size: 60,
      color: Color(0xFF64748B),
    );
  }
}

class _TogglePainter extends CustomPainter {
  final double progress;
  final bool isConnected;
  final bool isConnecting;
  final double rotation;

  _TogglePainter({
    required this.progress,
    required this.isConnected,
    required this.isConnecting,
    required this.rotation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;

    if (isConnected) {
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.connected.withValues(alpha: 0.15 + progress * 0.1),
            AppColors.connected.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius + 15));

      canvas.drawCircle(center, radius + 15, glowPaint);

      final ringPaint = Paint()
        ..color = AppColors.connected.withValues(alpha: 0.2 + progress * 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 + progress * 2
        ..strokeCap = StrokeCap.round;

      canvas.drawCircle(center, radius, ringPaint);
    } else if (isConnecting) {
      final arcPaint = Paint()
        ..color = AppColors.warning
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;

      final sweepAngle = 2 * math.pi * 0.3;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        rotation * 2 * math.pi - math.pi / 2,
        sweepAngle,
        false,
        arcPaint,
      );
    } else {
      final ringPaint = Paint()
        ..color = const Color(0xFF1F2D3D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;

      canvas.drawCircle(center, radius, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TogglePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isConnected != isConnected ||
        oldDelegate.isConnecting != isConnecting ||
        oldDelegate.rotation != rotation;
  }
}
