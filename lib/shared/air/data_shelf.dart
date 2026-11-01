import 'package:flutter/material.dart';

import '../../core/theme/air_colors.dart';
import '../../core/theme/app_text_styles.dart';

class ShelfMetric {
  const ShelfMetric({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;
}

/// Three figures on a single hairline: ping, down, up. No cards, no dividers.
class DataShelf extends StatelessWidget {
  const DataShelf({
    super.key,
    required this.metrics,
    required this.meta,
  });

  final List<ShelfMetric> metrics;
  final Widget meta;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    return Container(
      padding: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: air.hairline, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < metrics.length; i++) ...[
                if (i > 0) const SizedBox(width: 20),
                Expanded(child: _Figure(metric: metrics[i])),
              ],
            ],
          ),
          const SizedBox(height: 12),
          meta,
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.metric});

  final ShelfMetric metric;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final unknown =
        metric.value.trim().isEmpty || metric.value.trim() == '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          metric.label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.label(color: air.steel, size: 10.5),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            metric.value,
            maxLines: 1,
            style: AppTextStyles.metric(
              color: unknown ? air.steel : metric.color,
            ),
          ),
        ),
        if (metric.unit.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            metric.unit,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.label(color: air.steel, size: 10),
          ),
        ],
      ],
    );
  }
}
