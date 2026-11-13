import 'package:flutter/material.dart';

import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/theme/metered_colors.dart';
import 'package:bulbvpn/shared/metered/metered_layout.dart';
import 'package:bulbvpn/shared/metered/pressable.dart';
import 'package:bulbvpn/shared/metered/slip_list.dart';

/// The head a Metered face prints above its own list.
///
/// The card has no nav bar, so the face that was pushed to has to say how to
/// leave it: the plate rivets a key to the corner rather than trusting a
/// gesture nobody printed. The iOS swipe-back still works underneath — the key
/// is the visible half of the affordance, not a replacement for it.
class FaceHeader extends StatelessWidget {
  const FaceHeader({
    super.key,
    required this.type,
    required this.title,
    this.note,
    this.onBack,
    this.trailing,
  });

  final MeteredType type;
  final String title;

  /// One line of fact under the name: what the face currently holds, not what
  /// it will do. A heading that promises is a heading the plate cannot keep.
  final String? note;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: m.ruleStrong, width: type.px(2)),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          type.px(26),
          type.px(24),
          type.px(24),
          type.px(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (onBack != null) ...[
              CardKey(label: 'Back', type: type, onTap: onBack),
              SizedBox(width: type.px(18)),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedLine(
                    title,
                    AppTextStyles.title(
                      color: m.ink,
                      size: type.navLabelAttached,
                      weight: FontWeight.w700,
                      tracking: 0,
                    ),
                  ),
                  if (note != null && note!.isNotEmpty) ...[
                    SizedBox(height: type.claim * 0.34),
                    FittedLine(
                      note!,
                      AppTextStyles.monoValue(
                        color: m.inkSoft,
                        size: type.claim,
                        height: 1.0,
                        tracking: type.claimLeft,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[SizedBox(width: type.px(18)), trailing!],
          ],
        ),
      ),
    );
  }
}

/// One line of the card's terms: what the setting is, what it currently does,
/// and the part on the right that changes it or shows more of it.
///
/// Deliberately not a `SlipRow`. A settings line carries no figure and no
/// verdict, and giving it the tariff sheet's four columns would print two dashes
/// in every row — measurements the card never took — to hold a grid this face
/// does not use. What it keeps from the slip is the rule under the line and the
/// two measures of print, so the terms read as the same plate.
class TermRow extends StatelessWidget {
  const TermRow({
    super.key,
    required this.type,
    required this.title,
    this.sub,
    this.value,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.failed = false,
    this.selected = false,
    this.semanticsLabel,
  });

  final MeteredType type;
  final String title;

  /// What the setting does on this phone right now, in the card's small measure.
  final String? sub;

  /// Where the line leads, printed as print rather than as a button: a
  /// destination is read, not pressed. Use [trailing] for a real key.
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// The plate hides one affordance per part instead of printing a second key,
  /// so a support gesture lives here.
  final VoidCallback? onLongPress;

  /// The line reports a finding that did not deliver, so its name prints in the
  /// card's refusal red — the same law the slip and the meter follow.
  final bool failed;

  /// The one line on this face that the phone is actually running. It takes the
  /// same paper register mark the tariff sheet gives the live relay, because a
  /// choice is not a reading worth the accent: the card rules it, it does not
  /// colour it.
  final bool selected;

  /// What an announcement device reads when the line's own print is a label
  /// rather than a sentence.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: semanticsLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: m.rule, width: type.px(2)),
          ),
        ),
        child: Pressable.flat(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  type.px(26),
                  type.px(20),
                  type.px(24),
                  type.px(20),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedLine(
                            title,
                            AppTextStyles.label(
                              color: failed ? m.blockedLift : m.ink,
                              size: type.tableRowMixed,
                              tracking: 0.0,
                            ).copyWith(
                              height: 1.06,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (sub != null && sub!.isNotEmpty) ...[
                            SizedBox(height: type.claim * 0.2),
                            FittedLine(
                              sub!,
                              AppTextStyles.monoValue(
                                color: m.inkFaint,
                                size: type.claim,
                                height: 1.0,
                                tracking: 0,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (value != null && value!.isNotEmpty) ...[
                      SizedBox(width: type.px(20)),
                      TermValue(type: type, text: value!),
                    ],
                    if (trailing != null) ...[
                      SizedBox(width: type.px(20)),
                      trailing!,
                    ],
                  ],
                ),
              ),
              if (selected)
                Positioned(
                  left: 0,
                  top: type.px(12),
                  bottom: type.px(12),
                  width: type.px(7),
                  child: ColoredBox(color: m.paper),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The right-hand print of a [TermRow]: a figure or a destination, never a
/// sentence. Anything longer is a `SlipNote` under the line it belongs to.
class TermValue extends StatelessWidget {
  const TermValue({
    super.key,
    required this.type,
    required this.text,
    this.muted = false,
  });

  final MeteredType type;
  final String text;

  /// A value the card cannot answer for — a version it did not build, a state
  /// it did not measure — prints one tier down.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    return FittedLine(
      text,
      AppTextStyles.monoValue(
        color: muted ? m.inkFaint : m.inkSoft,
        size: type.tableRow,
        weight: FontWeight.w500,
        height: 1.0,
        tracking: 0,
      ),
    );
  }
}
