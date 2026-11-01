import 'package:bulbvpn/core/theme/air_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/utils/format_number.dart';
import 'package:flutter/material.dart';

/// Three baseline figures: no cards, no icons, dashes until measured.
class SpeedMetricsRow extends StatelessWidget {
  const SpeedMetricsRow({
    super.key,
    required this.download,
    required this.upload,
    required this.ping,
  });

  final double download;
  final double upload;
  final int ping;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _Metric(
            label: 'DOWNLOAD',
            value: download > 0 ? doubleFormatNumber(download) : '—',
            unit: 'Mbps',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _Metric(
            label: 'UPLOAD',
            value: upload > 0 ? doubleFormatNumber(upload) : '—',
            unit: 'Mbps',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _Metric(
            label: 'PING',
            value: ping > 0 ? '$ping' : '—',
            unit: 'ms',
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final dashed = value == '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.label(color: air.steel, size: 10),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  value,
                  maxLines: 1,
                  style: AppTextStyles.metric(
                    color: dashed ? air.mute : air.ink,
                    size: 22,
                  ),
                ),
              ),
            ),
            if (!dashed) ...[
              const SizedBox(width: 4),
              Text(
                unit,
                maxLines: 1,
                style: AppTextStyles.monoValue(color: air.steel, size: 10),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
