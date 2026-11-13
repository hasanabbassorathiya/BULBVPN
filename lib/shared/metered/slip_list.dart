import 'package:flutter/material.dart';

import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/theme/metered_colors.dart';
import 'package:bulbvpn/modules/core/relay_verdict.dart';
import 'package:bulbvpn/shared/metered/metered_layout.dart';
import 'package:bulbvpn/shared/metered/pressable.dart';

/// The print a Metered sheet lists long records on: the connect card's tariff
/// sheet, unrolled.
///
/// It keeps the plate's column register — the same four widths, the same print
/// sizes, the same verdict words — because a relay cannot be `CARRIED` on the
/// card and `OK` on the sheet. What it drops is the vertical strokes: the
/// card's table is a fixed block and one grid painter can align them, while a
/// scrolling list recycles its rows and cannot share a grid with its
/// neighbours. Horizontal hairlines carry the rows and the four columns carry
/// the reading, which is how a long tariff sheet is ruled in the first place.
class SlipRow extends StatelessWidget {
  const SlipRow({
    super.key,
    required this.type,
    required this.code,
    required this.title,
    this.sub,
    this.subTail,
    this.reading,
    this.qualifier,
    this.verdict,
    this.disclosure,
    this.disclosureSemantics,
    this.selected = false,
    this.trailingKey,
    this.onTrailing,
    this.onTap,
    this.semanticsLabel,
  });

  final MeteredType type;

  /// The RELAY column: a country code, `AUTO`, or the owner of the address.
  final String code;
  final String title;

  /// What the tunnel dials, printed under the name in the plate's small measure.
  final String? sub;

  /// The address that sub dials, on a line of its own under it.
  ///
  /// One line of the card's mono print reaches about twenty glyphs inside the
  /// DESTINATION column, and a transport summary with an `host:port` joined to
  /// it is thirty-three. Joined, the plate would have to shrink the line below
  /// the size it was measured at to keep the words; split, both lines print at
  /// full measure and the address stays the line a user can actually read off.
  final String? subTail;

  /// The figure, and the instrument that produced it.
  final String? reading;
  final String? qualifier;

  /// What the measurement proves. Nothing is printed in this column when the
  /// relay has not been measured at all, which is the plate's own `—`.
  final RelayVerdict? verdict;

  /// The trust disclosure, printed as a mark riveted to the row rather than as
  /// a colour borrowed from a failure.
  final String? disclosure;

  /// The sentence an announcement device reads for [disclosure].
  final String? disclosureSemantics;

  final bool selected;

  /// A row action, printed as a key under the address rather than in a column
  /// of its own: the plate's four columns are its reading surface, and a fifth
  /// slot narrow enough to hold `REMOVE` would cost the DESTINATION column the
  /// width it needs for a host name.
  final String? trailingKey;
  final VoidCallback? onTrailing;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  static const List<int> _columns = MeteredLayout.tableColumns;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    final v = verdict ?? RelayVerdict.untried;
    final row = Padding(
      padding: EdgeInsets.fromLTRB(
        type.px(26),
        type.px(18),
        type.px(24),
        type.px(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: _columns[0],
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                code.toUpperCase(),
                maxLines: 1,
                textAlign: TextAlign.center,
                style: AppTextStyles.monoValue(
                  color: selected ? m.ink : m.inkSoft,
                  size: type.tableRow,
                  weight: selected ? FontWeight.w700 : FontWeight.w500,
                  height: 1.0,
                  tracking: 0,
                ),
              ),
            ),
          ),
          Expanded(
            flex: _columns[1],
            child: Padding(
              padding: EdgeInsets.only(left: type.px(20)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedLine(
                    title,
                    AppTextStyles.label(
                      color: m.ink,
                      size: type.tableRowMixed,
                      tracking: 0.0,
                    ).copyWith(height: 1.06, fontWeight: FontWeight.w600),
                  ),
                  if (sub != null && sub!.isNotEmpty)
                    SizedBox(height: type.claim * 0.2),
                  if (sub != null && sub!.isNotEmpty)
                    FittedLine(
                      sub!,
                      AppTextStyles.monoValue(
                        color: m.inkFaint,
                        size: type.claim,
                        height: 1.0,
                        tracking: 0,
                      ),
                    ),
                  if (subTail != null && subTail!.isNotEmpty)
                    SizedBox(height: type.claim * 0.18),
                  if (subTail != null && subTail!.isNotEmpty)
                    FittedLine(
                      subTail!,
                      // The address one tier up from the transport's caption:
                      // it is the line a user checks when they doubt the row,
                      // so it prints as data rather than as a note about data.
                      AppTextStyles.monoValue(
                        color: m.inkSoft,
                        size: type.claim,
                        height: 1.0,
                        tracking: 0,
                      ),
                    ),
                  if (trailingKey != null) ...[
                    SizedBox(height: type.claim * 0.3),
                    CardKey(label: trailingKey!, type: type, onTap: onTrailing),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            flex: _columns[2],
            child: Padding(
              padding: EdgeInsets.only(left: type.px(12)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FittedLine(
                    reading ?? '—',
                    AppTextStyles.monoValue(
                      color: _figureColor(m, v),
                      size: type.tableRow,
                      weight: FontWeight.w500,
                      height: 1.0,
                      tracking: 0,
                    ),
                  ),
                  SizedBox(height: type.claim * 0.2),
                  FittedLine(
                    qualifier ?? '',
                    AppTextStyles.monoValue(
                      color: m.inkFaint,
                      size: type.claim,
                      height: 1.0,
                      tracking: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: _columns[3],
            child: Padding(
              padding: EdgeInsets.only(left: type.px(16)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedLine(
                    v.word,
                    AppTextStyles.label(
                      color: _verdictColor(m, v),
                      size: type.tableHead,
                      tracking: 0.0,
                    ).copyWith(height: 1.0, fontWeight: FontWeight.w600),
                  ),
                  if (disclosure != null && disclosure!.isNotEmpty) ...[
                    SizedBox(height: type.claim * 0.24),
                    TrustMark(
                      label: disclosure!,
                      type: type,
                      semantic: disclosureSemantics,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
          child: Stack(
            children: [
              row,
              // The live line gets a register mark, not a colour: the accent is
              // reserved for readings that are worth something and the card's
              // paper is what the plate uses to rule a column. Absolute, so a
              // selected row does not shift its print by a pixel.
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

  static Color _figureColor(MeteredColors m, RelayVerdict v) => switch (v) {
    RelayVerdict.untried => m.inkFaint,
    RelayVerdict.unproven => m.inkSoft,
    _ => m.ink,
  };

  static Color _verdictColor(MeteredColors m, RelayVerdict v) => switch (v) {
    RelayVerdict.blocked => m.blockedLift,
    RelayVerdict.carried => m.proven,
    RelayVerdict.probed => m.ink,
    RelayVerdict.unproven => m.inkSoft,
    RelayVerdict.untried => m.inkFaint,
  };
}

/// A band that names the block under it, ruled above and below so it reads as a
/// divider rather than as a row of relays that happens to have no figures.
class SlipSection extends StatelessWidget {
  const SlipSection({
    super.key,
    required this.title,
    required this.type,
    this.leading,
    this.note,
    this.disclosure,
    this.disclosureSemantics,
    this.proven = false,
  });

  final String title;
  final MeteredType type;

  /// A flag, an emblem — anything the row of print hangs off.
  final Widget? leading;

  /// The block's own measurement, printed at the foot of the band.
  final String? note;
  final String? disclosure;
  final String? disclosureSemantics;

  /// Bytes crossed somewhere in this block on this device.
  final bool proven;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: m.ruleStrong, width: type.px(2)),
          bottom: BorderSide(color: m.rule, width: type.px(2)),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          type.px(26),
          type.px(22),
          type.px(24),
          type.px(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (leading != null) ...[leading!, SizedBox(width: type.px(16))],
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  style: AppTextStyles.label(
                    color: proven ? m.proven : m.inkSoft,
                    size: type.tableHead,
                    tracking: type.px(6),
                  ).copyWith(height: 1.0, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            SizedBox(width: type.px(16)),
            if (note != null && note!.isNotEmpty)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  note!,
                  maxLines: 1,
                  style: AppTextStyles.monoValue(
                    color: proven ? m.proven : m.inkFaint,
                    size: type.claim,
                    height: 1.0,
                    tracking: 0,
                  ),
                ),
              ),
            if (disclosure != null && disclosure!.isNotEmpty) ...[
              SizedBox(width: type.px(18)),
              TrustMark(
                label: disclosure!,
                type: type,
                semantic: disclosureSemantics,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A consent switch cut into the card. Off is the default for anything whose
/// relays are run by strangers: the plate does not let a control promise on
/// someone's behalf.
class SlipSwitch extends StatelessWidget {
  const SlipSwitch({
    super.key,
    required this.on,
    required this.onChanged,
    required this.type,
    this.enabled = true,
    this.label,
  });

  final bool on;
  final ValueChanged<bool> onChanged;
  final MeteredType type;
  final bool enabled;

  /// What an announcement device reads, since the housing carries no text.
  final String? label;

  /// Measured off the slot's own proportions: the plate punches a hole about a
  /// quarter of the housing's height through the middle of a part, and the
  /// block that travels is a flip card cut to the hole.
  static const double _radius = 0.30;
  static const double _holeInset = 0.10;
  static const double _holeHeight = 0.52;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    return Semantics(
      container: true,
      checked: on,
      enabled: enabled,
      label: label,
      child: Pressable(
        onTap: enabled ? () => onChanged(!on) : null,
        child: LayoutBuilder(
          builder: (context, c) {
            final h = c.maxHeight;
            final holeH = h * _holeHeight;
            final block = holeH * 0.62;
            return Container(
              decoration: BoxDecoration(
                color: m.housing,
                borderRadius: BorderRadius.circular(h * _radius),
                border: Border.all(color: m.housingRim, width: type.px(2)),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: c.maxWidth * _holeInset,
                  vertical: (h - holeH) / 2,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: m.slotHole,
                    borderRadius: BorderRadius.circular(holeH * 0.5),
                  ),
                  child: SizedBox(
                    height: holeH,
                    width: c.maxWidth * (1 - 2 * _holeInset),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOut,
                      alignment: on
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        width: block,
                        height: block,
                        margin: EdgeInsets.symmetric(horizontal: block * 0.18),
                        decoration: BoxDecoration(
                          color: on ? m.value : m.foil,
                          borderRadius: BorderRadius.circular(block * 0.28),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.6),
                            width: type.px(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A consent row: the plate's print on the left and the switch cut for it on
/// the right, ruled like every other row so a control and a reading sit on the
/// same grid rather than floating above it.
///
/// It is not a `SlipRow` with the STATE column swapped out. A toggle has no
/// verdict and no figure, and inventing one to fill a column would print a
/// measurement the card never took.
class SlipToggleRow extends StatelessWidget {
  const SlipToggleRow({
    super.key,
    required this.type,
    required this.code,
    required this.title,
    required this.sub,
    required this.on,
    required this.onChanged,
    required this.toggleKey,
    this.enabled = true,
  });

  final MeteredType type;
  final String code;
  final String title;
  final String sub;
  final bool on;
  final ValueChanged<bool> onChanged;

  /// The address a test or an assistive device aims at, since the housing the
  /// switch is cut from carries no text of its own.
  final Key toggleKey;
  final bool enabled;

  static const List<int> _columns = MeteredLayout.tableColumns;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: m.rule, width: type.px(2)),
        ),
      ),
      child: Pressable.flat(
        onTap: enabled ? () => onChanged(!on) : null,
        child: Padding(
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
                flex: _columns[0],
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    code.toUpperCase(),
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.monoValue(
                      color: m.inkSoft,
                      size: type.tableRow,
                      height: 1.0,
                      tracking: 0,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: _columns[1] + _columns[2],
                child: Padding(
                  padding: EdgeInsets.only(left: type.px(20)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedLine(
                        title,
                        AppTextStyles.label(
                          color: m.ink,
                          size: type.tableRowMixed,
                          tracking: 0.0,
                        ).copyWith(height: 1.06, fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: type.claim * 0.24),
                      Text(
                        sub,
                        style: AppTextStyles.body(
                          color: m.inkSoft,
                          size: type.exitPlace,
                          height: 1.32,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: type.px(20)),
              SizedBox(
                width: type.px(MeteredLayout.switchSlot.width),
                height: type.px(MeteredLayout.switchSlot.height),
                child: SlipSwitch(
                  key: toggleKey,
                  on: on,
                  enabled: enabled,
                  onChanged: onChanged,
                  type: type,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A sentence the card owes the reader, ruled off from the print above and
/// below so it reads as a standing disclosure rather than as a row they could
/// tap past.
///
/// The plate puts these under the block they describe and never in a dialog: a
/// warning that can be dismissed is a warning that has been dismissed.
class SlipNote extends StatelessWidget {
  const SlipNote({
    super.key,
    required this.type,
    required this.text,
    this.mark,
    this.markSemantic,
    this.failed = false,
  });

  final MeteredType type;
  final String text;

  /// The trust mark riveted to the band. A note without one is an explanation
  /// the card did not have to give.
  final String? mark;
  final String? markSemantic;

  /// The band reports something that did not deliver, so it prints in the
  /// card's refusal red. That red is reserved for this finding and for a
  /// blocked relay: a privacy disclosure never borrows it, or a user who reads
  /// the red as "broken" stops reading the disclosure at all.
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: m.rule, width: type.px(2)),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          type.px(26),
          type.px(20),
          type.px(24),
          type.px(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mark != null && mark!.isNotEmpty) ...[
              TrustMark(
                label: mark!,
                type: type,
                semantic: markSemantic ?? mark,
              ),
              SizedBox(width: type.px(18)),
            ],
            Expanded(
              child: Text(
                text,
                style: AppTextStyles.body(
                  color: failed ? m.blockedLift : m.inkSoft,
                  size: type.exitPlace,
                  height: 1.34,
                  weight: failed ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one row on a slip that is not a reading: it names something the card can
/// do and prints the key that does it. It keeps the row's rules so an action
/// cannot look like a relay with a missing figure.
class SlipAction extends StatelessWidget {
  const SlipAction({
    super.key,
    required this.type,
    required this.title,
    required this.text,
    required this.keyLabel,
    this.onTap,
  });

  final MeteredType type;
  final String title;
  final String text;
  final String keyLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: m.rule, width: type.px(2)),
        ),
      ),
      child: Padding(
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
                      color: m.ink,
                      size: type.tableRowMixed,
                      tracking: 0.0,
                    ).copyWith(height: 1.06, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: type.claim * 0.24),
                  Text(
                    text,
                    style: AppTextStyles.body(
                      color: m.inkSoft,
                      size: type.exitPlace,
                      height: 1.34,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: type.px(20)),
            CardKey(label: keyLabel, type: type, onTap: onTap),
          ],
        ),
      ),
    );
  }
}

/// A printed key: the card's own answer to a button. It is a separate part
/// riveted to the face, like the slot's housing, and it names the action it
/// performs instead of a status.
class CardKey extends StatelessWidget {
  const CardKey({
    super.key,
    required this.label,
    required this.type,
    this.onTap,
    this.busy = false,
    this.emphasis = false,
  });

  final String label;
  final MeteredType type;
  final VoidCallback? onTap;
  final bool busy;

  /// The key that matters most on the face prints in the card's own ivory; the
  /// rest of them recede to the plate's secondary print.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    final live = onTap != null && !busy;
    return Semantics(
      button: live,
      label: label,
      child: Pressable(
        onTap: live ? onTap : null,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: type.px(26),
              vertical: type.px(14),
            ),
            decoration: BoxDecoration(
              color: m.housing,
              borderRadius: BorderRadius.circular(type.px(14)),
              border: Border.all(color: m.housingRim, width: type.px(2)),
            ),
            child: Text(
              busy ? '……' : label.toUpperCase(),
              maxLines: 1,
              style: AppTextStyles.monoValue(
                color: !live
                    ? m.inkFaint
                    : emphasis
                    ? m.ink
                    : m.inkSoft,
                size: type.tableHead,
                weight: FontWeight.w600,
                height: 1.0,
                tracking: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A hole cut for typing into. The plate's wells take their light off the far
/// lip, which is what makes one a recess instead of a dark rectangle painted on
/// the card.
///
/// Beyond one line the same housing becomes a paste area: a subscription body
/// and a country name are both text pushed through the same hole, so the
/// second gets the well rather than a different widget.
class SlottedField extends StatelessWidget {
  const SlottedField({
    super.key,
    required this.controller,
    required this.type,
    required this.hint,
    this.onChanged,
    this.textInputAction,
    this.enabled = true,
    this.minLines,
    this.maxLines = 1,
    this.expands = false,
    this.keyboardType,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.textCapitalization = TextCapitalization.sentences,
  });

  final TextEditingController controller;
  final MeteredType type;
  final String hint;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final bool enabled;
  final int? minLines;
  final int maxLines;

  /// Take the whole box the card hands the hole instead of the height the text
  /// happens to have.
  ///
  /// A paste area that shrinks to its contents leaves the plate's own ground
  /// showing where the card cut a well, which reads as a different part. With
  /// this on, the recess is the room and the print fills it from the top.
  final bool expands;
  final TextInputType? keyboardType;
  final bool autocorrect;
  final bool enableSuggestions;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    return Opacity(
      // A hole the card will not take input through is printed dead, so the
      // recess itself says "wait" instead of a spinner living somewhere else.
      opacity: enabled ? 1.0 : 0.55,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(type.px(14)),
          border: Border.all(color: m.housingRim, width: type.px(2)),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: m.well,
            borderRadius: BorderRadius.circular(type.px(12)),
          ),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: textInputAction,
            enabled: enabled,
            minLines: expands ? null : minLines,
            maxLines: expands ? null : maxLines,
            expands: expands,
            textAlignVertical: expands ? TextAlignVertical.top : null,
            keyboardType: keyboardType,
            autocorrect: autocorrect,
            enableSuggestions: enableSuggestions,
            textCapitalization: textCapitalization,
            cursorColor: m.value,
            cursorRadius: const Radius.circular(2),
            style: AppTextStyles.monoValue(
              color: m.ink,
              size: type.tableRow,
              height: 1.0,
              tracking: 0,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppTextStyles.monoValue(
                color: m.inkFaint,
                size: type.tableRow,
                height: 1.0,
                tracking: 0,
              ),
              isDense: true,
              filled: false,
              contentPadding: EdgeInsets.symmetric(
                horizontal: type.px(26),
                vertical: type.px(22),
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
      ),
    );
  }
}

/// The trust contract, printed as a part riveted to the row rather than as a
/// wash of colour behind it.
///
/// Nothing on this card may say "not private" in the same red it uses for a
/// relay that failed to deliver: the two findings are different, and a user who
/// learns to read the red as "broken" will stop reading the disclosure. So the
/// mark carries its own ground — the plate's housing, its rim lit — and the
/// print on it is the card's ivory, which is the highest contrast the card
/// owns.
class TrustMark extends StatelessWidget {
  const TrustMark({
    super.key,
    required this.label,
    required this.type,
    this.semantic,
  });

  final String label;
  final String? semantic;

  /// The owning card's scale. A mark that measured itself off the window would
  /// print at one size on the card and another on a sheet that shares the plate.
  final MeteredType type;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    return Semantics(
      label: semantic ?? label,
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: type.px(14),
          vertical: type.px(6),
        ),
        decoration: BoxDecoration(
          color: m.housing,
          borderRadius: BorderRadius.circular(type.px(8)),
          border: Border.all(color: m.housingRim, width: type.px(2)),
        ),
        child: Text(
          label.toUpperCase(),
          maxLines: 1,
          style: AppTextStyles.monoValue(
            color: m.ink,
            size: type.claim,
            weight: FontWeight.w600,
            height: 1.0,
            tracking: 0,
          ),
        ),
      ),
    );
  }
}
