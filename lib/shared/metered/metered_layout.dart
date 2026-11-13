import 'package:flutter/material.dart';

/// The measured layout of the approved Metered comp, as fractions of the card
/// frame.
///
/// The comp is 1024x1792 and its card fills the frame, so every fraction below
/// is a division of a box measured off the comp in its own pixels. A phone's
/// card area is a different aspect, which is why the blocks are re-based to the
/// frame they are drawn in instead of being scaled by a single factor: the card
/// keeps the comp's boxes in proportion, not the comp's boxes in pixels.
class MeteredLayout {
  const MeteredLayout._();

  static const double cardRadius = 14;

  static const Rect masthead = Rect.fromLTRB(0.046, 0.0248, 0.660, 0.077);

  /// The clock hangs from the same ink top as the wordmark: its kicker prints
  /// at the wordmark's cap line and its digits land on the rule.
  static const Rect sessionClock = Rect.fromLTRB(0.690, 0.024, 0.945, 0.083);

  /// The hairline that separates the wordmark from the clock. The comp rules
  /// the header into two columns before it rules the header off the card.
  static const Rect headerRule = Rect.fromLTRB(0.666, 0.017, 0.667, 0.095);

  /// The two ivory rules the header stands on, and the claims sit under. The
  /// vertical hairline breaks what would be one line into two, and the comp
  /// prints both segments — a rule across the whole card would cut through the
  /// gap the columns are separated by.
  static const Rect mastheadRule = Rect.fromLTRB(0.055, 0.0932, 0.648, 0.0942);
  static const Rect clockRule = Rect.fromLTRB(0.690, 0.0932, 0.945, 0.0942);

  static const Rect claims = Rect.fromLTRB(0.055, 0.1032, 0.945, 0.133);

  /// The credit window is the hole cut in the plate, measured as the hole and
  /// not as the box drawn around it: the lit bezel lands at x43..981, y281..550.
  static const Rect well = Rect.fromLTRB(0.0420, 0.1579, 0.9580, 0.3047);
  static const Rect panel = Rect.fromLTRB(0.046, 0.319, 0.954, 0.408);
  static const Rect slot = Rect.fromLTRB(0.168, 0.4464, 0.834, 0.5502);
  static const Rect table = Rect.fromLTRB(0.046, 0.575, 0.954, 0.730);
  static const Rect terms = Rect.fromLTRB(0.0459, 0.751, 0.9531, 0.858);
  static const Rect nav = Rect.fromLTRB(0.000, 0.882, 1.000, 1.000);

  /// The four columns the plate rules the tariff sheet into, as widths of the
  /// 927 inside its own border. They are not equal: a destination needs the
  /// room and a verdict does not. The relay slip is this table at a longer
  /// length, so it rules the same four and prints the same words.
  static const List<int> tableColumns = [143, 311, 228, 245];

  /// The slot the plate cuts for a switch: about 156 of its own pixels across
  /// and 74 down — wide enough for a thumb, and no wider than the row that
  /// carries it. Both the relay sheet and the terms face punch this one size,
  /// so a control reads as the same part of the card wherever it appears.
  static const Size switchSlot = Size(156, 74);

  /// The card's own aspect, so a surface can reserve the same shape.
  static const double platePanelAspect = 1536 / 585;

  static Rect scale(Rect unit, Size size) => Rect.fromLTRB(
    unit.left * size.width,
    unit.top * size.height,
    unit.right * size.width,
    unit.bottom * size.height,
  );
}

/// The print sizes of the comp, bound to the width of the card they are drawn
/// on.
///
/// Each value is a size in the comp's own pixels, divided by 1024 so the same
/// ink occupies the same part of a 360pt card as it does of the plate. Two
/// measurements set them, and which one wins is stated per line:
///
/// * **Cap height** — the ink of one line divided by the ratio the face
///   renders at. Vazirmatn at w800 puts 0.660 of its size in caps, Geist Mono
///   at w500 0.720, and its figures at w700 0.760.
/// * **Advance** — the horizontal pitch the comp actually printed. Geist Mono
///   advances 0.600em per glyph, so a line's pitch divided by the glyph count
///   pins the size independently of how tall its caps came out. Where a cap
///   reading and an advance reading disagree, the advance wins: the pixel diff
///   is driven by how far the words reach across the card, not by how tall
///   they stand.
///
/// Letter-spacing is measured the same way, off the comp's own glyph runs, and
/// it is 0 on almost every line: the card's mono print is set tight and gets
/// its air from the size. The four exceptions name themselves below.
class MeteredType {
  const MeteredType(this.cardWidth);

  final double cardWidth;

  double _em(double compEm) => compEm * cardWidth / 1024.0;

  /// A length the plate measures in its own pixels, converted to the logical
  /// points of this card.
  ///
  /// Every hairline has to come through here. A rule drawn in points is the
  /// right thickness to the eye on a 360pt card and 2.84x too heavy when the
  /// same card is printed to the plate's 1024 for the diff, and the plate's own
  /// rules are 2px at 1024 — so a point-based border reads as a cream frame
  /// around a box the comp drew with a pencil.
  double px(double compPx) => compPx * cardWidth / 1024.0;

  /// BULBVPN: 60px of cap. The face puts 0.726 of its size in caps, so 60 of
  /// ink is 82.6 of em. At that em the eight letter gaps alone account for the
  /// plate's 429px, which leaves barely 2px per gap: the wordmark is set tight,
  /// not tracked. Solving for the width rather than trusting the mock's air is
  /// what keeps it from running past the header rule.
  double get wordmark => _em(82.6);
  double get wordmarkTracking => wordmark * 0.0266;

  /// SESSION TIME / REGISTERED RELAY SERVICE: 22px of cap.
  double get kicker => _em(30.6);

  /// The four claim lines: 19px of cap. The plate sets them tighter than the
  /// kicker, and 14 characters of PRIVATE ACCESS reach only 241px of it.
  double get claim => _em(24.0);

  /// The session clock figures: the plate's digits are 237px across and 63 of
  /// them tall, which the face reaches at 91 of em.
  double get clock => _em(91.0);

  // The credit window's rubric, figure and unit sizes are not here: FlipMeter
  // owns them as fractions of the tile, because a meter printed at three
  // columns instead of four has to shrink its whole stack together.

  /// TAP TO DISCONNECT: 28px of cap, and the 17 characters of it reach 380px
  /// of the plate — 22.4 of pitch, which is 37.3 of a monospaced em. The pitch
  /// wins because the hole is cut to the width of the word.
  double get slotLabel => _em(37.3);

  /// A relay column heading: 22px of cap. Short words, so the cap pins it.
  double get tableHead => _em(30.6);

  /// A relay row's figures: 25px of ink.
  double get tableRow => _em(32.9);

  /// A place name in a row, which carries a descender; the same size, since
  /// the row is one line of ink from top to bottom.
  double get tableRowMixed => _em(32.0);

  /// The terms heading: 27 chars of it reach 447px of the plate.
  double get termsHead => _em(28.0);

  /// A numbered step: the longer of the two spans 706px over 58 characters.
  double get termsStep => _em(21.0);

  /// The promise in the terms' right column: TOMORROW's 8 letters reach 150px.
  double get termsRight => _em(27.5);

  /// The scratch panel's reading: 32px pinned by the digits' pitch.
  double get exitReading => _em(32.0);

  /// The place under it.
  double get exitPlace => _em(31.9);

  /// The scratch prompt: three lines of 31px, printed on the foil and staying
  /// printed after the foil comes away.
  double get promptLine => _em(31.0);

  /// The segment that has been torn off: CONNECT's 7 letters reach 169px of
  /// the plate in the display face.
  double get navLabel => _em(44.0);

  /// A segment still attached to the card: 25px of cap in the mono face. The
  /// comp prints the torn tab larger than the tabs it did not tear.
  double get navLabelAttached => _em(34.7);

  /// REGISTERED RELAY SERVICE: 24 letters reach the wordmark's rule, so the
  /// kicker that shares the masthead is tracked; the clock's kicker is not.
  double get kickerRegister => kicker * 0.175;
  double get kickerSession => kicker * 0.056;

  /// The left pair of claims is tracked, the right pair is not — it hangs off
  /// the rule it ends at instead of running to it.
  double get claimLeft => claim * 0.12;
}

/// One line of print that gives up size before it gives up words. A card that
/// truncates its own instructions is not a card.
///
/// It hugs the line rather than filling the box it is handed, so it can sit in
/// a Column without pushing its siblings out; the parent's cross-axis alignment
/// decides where the line lands.
class FittedLine extends StatelessWidget {
  const FittedLine(this.text, this.style, {super.key});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(text, maxLines: 1, style: style),
  );
}
