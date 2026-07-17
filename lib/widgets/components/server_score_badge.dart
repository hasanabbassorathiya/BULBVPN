import 'package:flutter/material.dart';

class ServerScoreBadge extends StatelessWidget {
  final double score;
  final bool compact;

  const ServerScoreBadge({super.key, required this.score, this.compact = false});

  Color get _color {
    if (score > 80) return const Color(0xFF22C55E);
    if (score >= 50) return const Color(0xFFFBBF24);
    return const Color(0xFFEF4444);
  }

  String get _label {
    if (score > 80) return 'Excellent';
    if (score >= 65) return 'Good';
    if (score >= 50) return 'Fair';
    return 'Poor';
  }

  @override
  Widget build(BuildContext context) {
    final display = '${score.round()}';
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Text(
        compact ? display : '$display $_label',
        style: TextStyle(
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w700,
          color: _color,
        ),
      ),
    );
  }
}
