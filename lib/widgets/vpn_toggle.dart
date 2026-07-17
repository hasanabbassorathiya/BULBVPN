import 'package:flutter/material.dart';
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
      lowerBound: 0.9,
      upperBound: 1.0,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);

    return Consumer<VPNProvider>(
      builder: (context, vpn, _) {
        final isConnected = vpn.isConnected;
        final isConnecting = vpn.isConnecting;

        if (isConnected) {
          _pulseController.repeat(reverse: true);
        } else {
          _pulseController.stop();
          _pulseController.value = 0;
        }

        return Semantics(
          label: isConnected ? 'VPN connected' : 'VPN disconnected',
          hint: 'Tap to ${isConnected ? 'disconnect' : 'connect'} VPN',
          button: true,
          child: GestureDetector(
            onTap: () {
              _scaleController.forward(from: 0.9);
              vpn.toggleConnection();
            },
            child: AnimatedBuilder(
              animation: Listenable.merge([_pulseController, _scaleController]),
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleController.value,
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        if (isConnected)
                          BoxShadow(
                            color: AppColors.connected.withValues(alpha: 0.3 * _pulseController.value),
                            blurRadius: 40,
                            spreadRadius: 10,
                          ),
                      ],
                    ),
                    child: CustomPaint(
                      painter: _TogglePainter(
                        progress: _pulseController.value,
                        isConnected: isConnected,
                        isConnecting: isConnecting,
                        cardColor: colors.card,
                      ),
                      child: Center(
                        child: _buildIcon(isConnected, isConnecting, colors),
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

  Widget _buildIcon(bool isConnected, bool isConnecting, AppSemanticColors colors) {
    if (isConnecting) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: AppColors.warning,
        ),
      );
    }

    return Icon(
      Icons.power_settings_new,
      size: 60,
      color: isConnected ? AppColors.connected : colors.textMuted,
    );
  }
}

class _TogglePainter extends CustomPainter {
  final double progress;
  final bool isConnected;
  final bool isConnecting;
  final Color cardColor;

  _TogglePainter({
    required this.progress,
    required this.isConnected,
    required this.isConnecting,
    required this.cardColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;

    final bgPaint = Paint()
      ..color = cardColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;

    canvas.drawCircle(center, radius, bgPaint);

    if (isConnected) {
      final glowPaint = Paint()
        ..color = AppColors.connected.withValues(alpha: 0.2 + progress * 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;

      canvas.drawCircle(center, radius, glowPaint);
    } else if (isConnecting) {
      final arcPaint = Paint()
        ..color = AppColors.warning
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round;

      final sweepAngle = 2 * 3.14159 * 0.3;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -3.14159 / 2,
        sweepAngle,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TogglePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isConnected != isConnected ||
        oldDelegate.isConnecting != isConnecting ||
        oldDelegate.cardColor != cardColor;
  }
}
