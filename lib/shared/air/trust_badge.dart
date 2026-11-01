import 'package:flutter/material.dart';

import '../../core/theme/air_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../modules/core/trust_tier.dart';

/// The visible trust contract: private relays wear the accent, public relays
/// say NOT PRIVATE in the alert color. Never optional, never small print.
class TrustBadge extends StatelessWidget {
  const TrustBadge({super.key, required this.tier, this.compact = false});

  final TrustTier tier;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final private = tier.isPrivate;
    final fg = private ? air.accentInk : air.alertInk;
    final bg = private
        ? air.accentWash
        : air.alert.withValues(alpha: 0.12);
    final text = private
        ? tier.short
        : compact
        ? 'NOT PRIVATE'
        : '${tier.short} · NOT PRIVATE';

    return Semantics(
      label: tier.disclosure,
      excludeSemantics: true,
      // widthFactor keeps the pill intrinsic inside Wrap/Column parents; a
      // bare alignment would stretch it into a full-width band.
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.label(
              color: fg,
              size: 9.5,
              tracking: 0.6,
            ),
          ),
        ),
      ),
    );
  }
}
