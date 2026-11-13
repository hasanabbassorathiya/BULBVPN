import 'package:flutter/material.dart';

import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/theme/metered_colors.dart';
import 'package:bulbvpn/shared/metered/metered_layout.dart';
import 'package:bulbvpn/shared/metered/pressable.dart';

/// The punched slot: the only control on the card. A slot is not a button that
/// promises something, it is the hole the card is used through — so it names
/// the action it performs and never a status it hopes for.
///
/// The plate shows a dark housing riveted to the card, an aperture cut through
/// the housing, and the action printed on the housing below the hole. The
/// housing is not the card: it is a separate part, and the light along its rim
/// is what says so.
class PunchedSlot extends StatelessWidget {
  const PunchedSlot({
    super.key,
    required this.label,
    required this.onTap,
    required this.type,
    this.enabled = true,
    this.busy = false,
  });

  final String label;
  final VoidCallback onTap;

  /// The card's print sizes: the words under the hole are the same plate print
  /// as everything else on the card.
  final MeteredType type;

  final bool enabled;
  final bool busy;

  /// Measured off the plate: the housing is 682x186, and the hole punched
  /// through it is a full pill 550 wide and 47 tall, set 65 in from each side
  /// and 51 down from the top. The hole is much smaller than it feels in the
  /// photo, and most of the housing below it is print.
  static const double _housingRadius = 0.17;
  static const double _holeInsetX = 0.096;
  static const double _holeTop = 0.274;
  static const double _holeHeight = 0.253;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    final live = enabled && !busy;
    return Pressable(
      onTap: live ? onTap : null,
      child: LayoutBuilder(
        builder: (context, c) {
          final h = c.maxHeight;
          final holeH = h * _holeHeight;
          final hairline = type.px(2);
          return Container(
            decoration: BoxDecoration(
              color: m.housing,
              borderRadius: BorderRadius.circular(h * _housingRadius),
              border: Border.all(color: m.housingRim, width: hairline),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: h * 0.16,
                  offset: Offset(0, h * 0.05),
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: c.maxWidth * _holeInsetX,
                  right: c.maxWidth * _holeInsetX,
                  top: h * _holeTop,
                  height: holeH,
                  child: _Aperture(height: holeH, hairline: hairline),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: h * (_holeTop + _holeHeight),
                  bottom: 0,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: c.maxWidth * 0.03,
                        ),
                        child: Text(
                          label,
                          maxLines: 1,
                          style: AppTextStyles.monoValue(
                            color: live ? m.ink : m.inkFaint,
                            size: type.slotLabel,
                            weight: FontWeight.w600,
                            height: 1.0,
                            tracking: 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The hole. Black all the way through — the plate's own aperture measures one
/// luminance from edge to edge, and a glint across the middle of it is a dark
/// rectangle painted on, not an opening. What makes it a hole is the light the
/// far side of the card catches along the lower lip, and the shadow the housing
/// takes just under it.
class _Aperture extends StatelessWidget {
  const _Aperture({required this.height, required this.hairline});

  final double height;

  /// The plate's own pencil weight, in this card's logical points.
  final double hairline;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    final radius = BorderRadius.circular(height * 0.5);
    return Container(
      decoration: BoxDecoration(
        color: m.slotHole,
        borderRadius: radius,
        border: Border(
          bottom: BorderSide(color: m.housingRim, width: hairline),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: height * 0.22,
            offset: Offset(0, height * 0.16),
          ),
        ],
      ),
    );
  }
}
