import 'dart:math';
import 'package:flutter/material.dart';
import '../constants/app_theme.dart';
import '../services/speed_test_service.dart';

class SpeedTestScreen extends StatefulWidget {
  const SpeedTestScreen({super.key});

  @override
  State<SpeedTestScreen> createState() => _SpeedTestScreenState();
}

class _SpeedTestScreenState extends State<SpeedTestScreen>
    with SingleTickerProviderStateMixin {
  final SpeedTestService _service = SpeedTestService();
  bool _testing = false;
  String _phase = 'idle';
  SpeedTestResult? _result;
  List<SpeedTestResult> _history = [];
  late AnimationController _needleController;
  double _needleAngle = 0.0;
  double _currentSpeed = 0.0;

  @override
  void initState() {
    super.initState();
    _needleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _loadHistory();
  }

  @override
  void dispose() {
    _needleController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final history = await _service.getHistory();
    if (mounted) {
      setState(() => _history = history);
    }
  }

  Future<void> _startTest() async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _result = null;
      _currentSpeed = 0;
      _needleAngle = 0;
    });

    try {
      final result = await _service.runTest(
        onProgress: (phase, progress) {
          if (mounted) {
            setState(() {
              _phase = phase;
              if (phase == 'download') {
                _currentSpeed = progress * 100;
                _needleAngle = progress;
              } else if (phase == 'upload') {
                _currentSpeed = progress * 100;
                _needleAngle = progress;
              } else {
                _needleAngle = 0;
                _currentSpeed = 0;
              }
            });
          }
        },
      );
      if (mounted) {
        setState(() {
          _result = result;
          _testing = false;
          _needleAngle = (result.downloadMbps / 100).clamp(0.0, 1.0);
          _currentSpeed = result.downloadMbps;
          _phase = 'done';
        });
        _loadHistory();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testing = false;
          _phase = 'error';
        });
      }
    }
  }

  Color _gaugeColor(double speed) {
    if (speed > 50) return AppColors.connected;
    if (speed > 10) return AppColors.warning;
    return AppColors.disconnected;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppSemanticColors.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPad = screenWidth > 600 ? 40.0 : 20.0;

    return Container(
      decoration: BoxDecoration(gradient: colors.bgGradient),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(horizontalPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.arrow_back_ios_new,
                        color: colors.textPrimary, size: 20),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Speed Test',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Measure your VPN connection speed',
                style: TextStyle(fontSize: 14, color: colors.textSecondary, decoration: TextDecoration.none),
              ),
              const SizedBox(height: 32),
              _buildGauge(colors),
              const SizedBox(height: 24),
              _buildStartButton(colors),
              const SizedBox(height: 32),
              if (_result != null) _buildResults(colors),
              if (_history.isNotEmpty) ...[
                const SizedBox(height: 24),
                _buildHistory(colors),
              ],
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGauge(AppSemanticColors colors) {
    return Center(
      child: SizedBox(
        width: 220,
        height: 140,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            CustomPaint(
              size: const Size(220, 140),
              painter: _GaugePainter(
                angle: _needleAngle,
                color: _gaugeColor(_currentSpeed),
                trackColor: colors.cardBorder,
              ),
            ),
            Positioned(
              bottom: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _testing
                        ? _currentSpeed.toStringAsFixed(1)
                        : _result != null
                            ? _result!.downloadMbps.toStringAsFixed(1)
                            : '—',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w800,
                      color: _result != null
                          ? _gaugeColor(_result!.downloadMbps)
                          : colors.textPrimary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  Text(
                    'Mbps',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colors.textSecondary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  if (_testing)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _phase.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartButton(AppSemanticColors colors) {
    return Center(
      child: SizedBox(
        width: 200,
        height: 52,
        child: ElevatedButton(
          onPressed: _testing ? null : _startTest,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.black,
            disabledBackgroundColor: colors.card,
            disabledForegroundColor: colors.textMuted,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          child: _testing
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: colors.textMuted,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.play_arrow_rounded, size: 24),
                    const SizedBox(width: 6),
                    Text(
                      'Start Test',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildResults(AppSemanticColors colors) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: colors.cardGradient,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.cardBorder.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.speed, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'Results',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildResultRow('Download', '${_result!.downloadMbps.toStringAsFixed(1)} Mbps',
              Icons.arrow_downward_rounded, AppColors.primary, colors),
          _buildResultRow('Upload', '${_result!.uploadMbps.toStringAsFixed(1)} Mbps',
              Icons.arrow_upward_rounded, AppColors.secondary, colors),
          _buildResultRow('Ping', '${_result!.pingMs} ms',
              Icons.sensors, _pingColor(_result!.pingMs), colors),
          _buildResultRow('Jitter', '${_result!.jitterMs} ms',
              Icons.show_chart, colors.textPrimary, colors),
          _buildResultRow('Server', _result!.serverName,
              Icons.dns, colors.textPrimary, colors),
        ],
      ),
    );
  }

  Widget _buildResultRow(
      String label, String value, IconData icon, Color color, AppSemanticColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(fontSize: 14, color: colors.textSecondary, decoration: TextDecoration.none)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: color, decoration: TextDecoration.none)),
        ],
      ),
    );
  }

  Widget _buildHistory(AppSemanticColors colors) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: colors.cardGradient,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.cardBorder.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.history, color: AppColors.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'Recent Tests',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ..._history.take(5).map((r) {
            final timeAgo = _formatTimeAgo(r.testedAt);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _gaugeColor(r.downloadMbps),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '↓ ${r.downloadMbps.toStringAsFixed(1)} Mbps  ↑ ${r.uploadMbps.toStringAsFixed(1)} Mbps',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          'Ping: ${r.pingMs} ms • $timeAgo',
                          style: TextStyle(fontSize: 11, color: colors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Color _pingColor(int ping) {
    if (ping < 30) return AppColors.connected;
    if (ping < 80) return AppColors.primary;
    if (ping < 150) return AppColors.warning;
    return AppColors.error;
  }
}

class _GaugePainter extends CustomPainter {
  final double angle;
  final Color color;
  final Color trackColor;

  _GaugePainter({
    required this.angle,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2 - 10;

    // Track arc
    final trackPaint = Paint()
      ..color = trackColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi,
      pi,
      false,
      trackPaint,
    );

    // Value arc
    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    final sweepAngle = pi * angle.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi,
      sweepAngle,
      false,
      valuePaint,
    );

    // Needle
    final needleAngle = pi + sweepAngle;
    final needleLength = radius - 20;
    final needleEnd = Offset(
      center.dx + cos(needleAngle) * needleLength,
      center.dy + sin(needleAngle) * needleLength,
    );

    final needlePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(center, needleEnd, needlePaint);

    // Center dot
    final dotPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, 5, dotPaint);
  }

  @override
  bool shouldRepaint(_GaugePainter oldDelegate) =>
      angle != oldDelegate.angle || color != oldDelegate.color;
}
