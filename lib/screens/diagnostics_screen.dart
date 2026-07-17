import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../providers/vpn_provider.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  int _qualityScore = 0;
  Timer? _scoreTimer;

  final List<_LogEntry> _log = [];

  @override
  void initState() {
    super.initState();
    _log.add(_LogEntry('Connected', 'Connected to server', Icons.link, AppColors.connected));
    _scoreTimer = Timer.periodic(const Duration(seconds: 3), (_) => _updateScore());
    _updateScore();
  }

  void _updateScore() {
    final vpn = context.read<VPNProvider>();
    if (!vpn.isConnected) {
      setState(() => _qualityScore = 0);
      return;
    }

    final speedScore = vpn.downloadSpeed > 0
        ? (vpn.downloadSpeed * 2).round().clamp(0, 100)
        : 50;
    final uptimeScore = vpn.isConnected ? 90 : 0;

    final score = ((speedScore * 0.5) + (uptimeScore * 0.5)).round();
    setState(() => _qualityScore = score.clamp(0, 100));
  }

  @override
  void dispose() {
    _scoreTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VPNProvider>();
    final colors = AppSemanticColors.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPad = screenWidth > 600 ? 40.0 : 20.0;

    final scoreColor = _qualityScore > 80
        ? AppColors.connected
        : _qualityScore > 50
            ? AppColors.warning
            : AppColors.disconnected;

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
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios, color: colors.textPrimary, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  Text('Diagnostics', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: colors.textPrimary)),
                ],
              ),
              const SizedBox(height: 28),

              _buildScoreSection(colors, scoreColor),
              const SizedBox(height: 28),

              Text('REAL-TIME METRICS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colors.textMuted, letterSpacing: 1.2)),
              const SizedBox(height: 12),
              _buildMetricsGrid(vpn, colors),

              if (vpn.selectedImportedServer != null) ...[
                const SizedBox(height: 24),
                Text('SERVER INFO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colors.textMuted, letterSpacing: 1.2)),
                const SizedBox(height: 12),
                _buildServerInfo(vpn, colors),
              ],

              const SizedBox(height: 24),
              Text('CONNECTION LOG', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colors.textMuted, letterSpacing: 1.2)),
              const SizedBox(height: 12),
              _buildConnectionLog(colors),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Speed test coming soon', style: TextStyle(color: colors.textPrimary)), backgroundColor: colors.card),
                    );
                  },
                  icon: const Icon(Icons.speed, size: 20),
                  label: Text('Run Speed Test', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScoreSection(AppSemanticColors colors, Color scoreColor) {
    return Center(
      child: Column(
        children: [
          SizedBox(
            width: 140,
            height: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 140,
                  height: 140,
                  child: CustomPaint(
                    painter: _ScorePainter(score: _qualityScore, color: scoreColor),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$_qualityScore', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: scoreColor)),
                    const SizedBox(height: 2),
                    Text('Score', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _qualityScore > 80
                ? 'Excellent connection quality'
                : _qualityScore > 50
                    ? 'Good connection quality'
                    : _qualityScore > 0
                        ? 'Poor connection quality'
                        : 'Not connected',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scoreColor),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(VPNProvider vpn, AppSemanticColors colors) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.3,
      children: [
        _buildMetricCard('Uptime', vpn.isConnected ? vpn.formattedDuration : '--', AppColors.connected, colors, Icons.timer),
        _buildMetricCard('Speed', vpn.isConnected ? '${vpn.downloadSpeed.toStringAsFixed(1)} Mbps' : '--', AppColors.info, colors, Icons.arrow_downward),
      ],
    );
  }

  Widget _buildMetricCard(String label, String value, Color valueColor, AppSemanticColors colors, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: valueColor, size: 16),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.textMuted)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: valueColor)),
        ],
      ),
    );
  }

  Widget _buildServerInfo(VPNProvider vpn, AppSemanticColors colors) {
    final server = vpn.selectedImportedServer!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(
        children: [
          _buildInfoRow('Server', server.name, colors),
          _buildInfoRow('Address', '${server.address}:${server.port}', colors),
          _buildInfoRow('Protocol', 'V2Ray', colors),
          _buildInfoRow('Type', server.protocol.name.toUpperCase(), colors),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, AppSemanticColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: colors.textMuted)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildConnectionLog(AppSemanticColors colors) {
    final entries = [
      _LogEntry('12:04:32', 'Connected', Icons.link, AppColors.connected),
      _LogEntry('12:04:29', 'Authenticating', Icons.vpn_key, AppColors.info),
      _LogEntry('12:04:27', 'Connecting', Icons.sync, AppColors.primary),
      _LogEntry('12:03:15', 'Disconnected', Icons.link_off, AppColors.disconnected),
      _LogEntry('12:03:12', 'Reconnected', Icons.link, AppColors.connected),
    ];

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(
        children: entries.asMap().entries.map((entry) {
          final i = entry.key;
          final log = entry.value;
          final isLast = i == entries.length - 1;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: isLast
                ? null
                : BoxDecoration(border: Border(bottom: BorderSide(color: colors.cardBorder, width: 0.5))),
            child: Row(
              children: [
                Icon(log.icon, color: log.color, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(log.event, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.textPrimary)),
                ),
                Text(log.timestamp, style: TextStyle(fontSize: 11, color: colors.textMuted, fontFamily: 'monospace')),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ScorePainter extends CustomPainter {
  final int score;
  final Color color;

  _ScorePainter({required this.score, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    final sweepAngle = 2 * pi * (score / 100);
    final arcPaint = Paint()
      ..shader = SweepGradient(
        startAngle: -pi / 2,
        endAngle: 3 * pi / 2,
        colors: [color.withValues(alpha: 0.6), color],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      sweepAngle,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_ScorePainter old) => old.score != score || old.color != color;
}

class _LogEntry {
  final String timestamp;
  final String event;
  final IconData icon;
  final Color color;

  _LogEntry(this.timestamp, this.event, this.icon, this.color);
}
