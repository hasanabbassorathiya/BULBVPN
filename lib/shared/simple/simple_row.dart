import 'package:flutter/material.dart';

import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/theme/simple_colors.dart';
import 'package:bulbvpn/modules/core/relay_verdict.dart';

/// One row on the card: a code, a title, a sub-line, a reading, and a verdict.
///
/// When `on` and `onChanged` are both provided, the row renders a toggle
/// instead of a tap target. `trailingKey` and `onTrailing` add a secondary
/// key at the trailing edge (e.g. 'REMOVE').
class SimpleRow extends StatelessWidget {
  const SimpleRow({
    super.key,
    required this.code,
    required this.title,
    this.sub,
    this.subTail,
    this.reading,
    this.qualifier,
    this.verdict = RelayVerdict.untried,
    this.selected = false,
    this.onTap,
    this.trailingKey,
    this.onTrailing,
    this.disclosure,
    this.disclosureSemantics,
    this.on,
    this.onChanged,
    this.toggleKey,
  });

  final String code;
  final String title;
  final String? sub;
  final String? subTail;
  final String? reading;
  final String? qualifier;
  final RelayVerdict verdict;
  final bool selected;
  final VoidCallback? onTap;
  final String? trailingKey;
  final VoidCallback? onTrailing;
  final String? disclosure;
  final String? disclosureSemantics;

  /// When set with onChanged, renders a switch instead of a tap target.
  final bool? on;
  final ValueChanged<bool>? onChanged;
  final Key? toggleKey;

  @override
  Widget build(BuildContext context) {
    final s = context.simple;
    final failed = verdict == RelayVerdict.blocked;
    final rowColor = failed ? s.error : s.ink;
    final subColor = s.inkSoft;

    if (on != null && onChanged != null) {
      return _SwitchRow(
        code: code,
        title: title,
        sub: sub ?? '',
        on: on!,
        onChanged: onChanged!,
        toggleKey: toggleKey,
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? s.surfaceVariant : s.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Text(
              code,
              style: AppTextStyles.monoValue(
                color: s.inkFaint,
                size: 12,
                weight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: AppTextStyles.body(
                            color: rowColor,
                            size: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (subTail != null && subTail!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            subTail!,
                            style: AppTextStyles.monoValue(
                              color: subColor,
                              size: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (sub != null && sub!.isNotEmpty)
                    Text(
                      sub!,
                      style: AppTextStyles.monoValue(
                        color: subColor,
                        size: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (reading != null || qualifier != null) ...[
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (reading != null)
                    Text(
                      reading!,
                      style: AppTextStyles.monoValue(
                        color: failed ? s.error : s.ink,
                        size: 13,
                      ),
                    ),
                  if (qualifier != null && qualifier!.isNotEmpty)
                    Text(
                      qualifier!,
                      style: AppTextStyles.monoValue(
                        color: subColor,
                        size: 11,
                      ),
                    ),
                ],
              ),
            ],
            if (disclosure != null && disclosure!.isNotEmpty) ...[
              const SizedBox(width: 12),
              Text(
                disclosure!,
                style: AppTextStyles.label(
                  color: verdict == RelayVerdict.carried ? s.connected : s.error,
                  size: 10,
                ),
                semanticsLabel: disclosureSemantics,
              ),
            ],
            if (trailingKey != null && trailingKey!.isNotEmpty) ...[
              const SizedBox(width: 12),
              InkWell(
                onTap: onTrailing,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    trailingKey!,
                    style: AppTextStyles.label(
                      color: s.connected,
                      size: 10,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.code,
    required this.title,
    required this.sub,
    required this.on,
    required this.onChanged,
    this.toggleKey,
  });

  final String code;
  final String title;
  final String sub;
  final bool on;
  final ValueChanged<bool> onChanged;
  final Key? toggleKey;

  @override
  Widget build(BuildContext context) {
    final s = context.simple;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: s.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Text(
              code,
              style: AppTextStyles.monoValue(
                color: s.inkFaint,
                size: 12,
                weight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.body(
                      color: s.ink,
                      size: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: AppTextStyles.monoValue(
                      color: s.inkSoft,
                      size: 12,
                    ),
                  ),
                ],
              ),
            ),
            Transform.scale(
              scale: 0.85,
              child: Switch(
                key: toggleKey,
                value: on,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
