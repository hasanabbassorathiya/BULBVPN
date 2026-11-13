import 'package:flutter/material.dart';

/// Metered palette: the printed face of a payphone card and the credit window
/// cut into it. Day is the card in daylight; Night is the same card after
/// dark, where the meter window is the only thing still lit.
///
/// Every colour here is sampled off the approved plate at its modal value, so
/// the palette is the card's own inks rather than a theme that resembles it.
///
/// Text pairs are asserted at WCAG AA in `test/metered_theme_test.dart`.
@immutable
class MeteredColors extends ThemeExtension<MeteredColors> {
  const MeteredColors({
    required this.brightness,
    required this.card,
    required this.cardDeep,
    required this.cardEdge,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.rule,
    required this.ruleStrong,
    required this.value,
    required this.valueLift,
    required this.valueOn,
    required this.well,
    required this.wellLip,
    required this.wellBevel,
    required this.wellRule,
    required this.wellLit,
    required this.wellShade,
    required this.wheel,
    required this.wheelRim,
    required this.wheelInk,
    required this.housing,
    required this.housingRim,
    required this.slotHole,
    required this.paper,
    required this.foil,
    required this.foilDark,
    required this.plateInk,
    required this.blocked,
    required this.blockedLift,
    required this.proven,
  });

  final Brightness brightness;

  /// The card face itself.
  final Color card;

  /// The pressed-in shadow of the card, and the recess every control sits in.
  final Color cardDeep;

  /// Worn paint along the card's edge.
  final Color cardEdge;

  /// Ivory print. Everything that must be read.
  final Color ink;

  /// Ivory pulled toward the cobalt, for secondary print. Never neutral gray
  /// on a coloured surface.
  final Color inkSoft;

  /// Tertiary print: rubrics and small print that is present but not urgent.
  final Color inkFaint;

  /// 1px separation. The card has no borders, only rules.
  final Color rule;
  final Color ruleStrong;

  /// The one accent: the reading that is worth something.
  final Color value;

  /// The same hue lifted for small type on cobalt, where `value` falls under
  /// 4.5:1.
  final Color valueLift;

  /// Text printed *on* the accent.
  final Color valueOn;

  /// The recessed credit window. The plate's window is not a hole in a
  /// photograph: it is a bezel, and three of its four walls catch light.
  final Color well;
  final Color wellLip;

  /// The lit chamfer on the window's left and right lips, measured off the
  /// plate at #797f8a (L 127) and #677b95 (L 120). The top wall stays in
  /// shadow at L 85 and the floor lifts to L 105, both of which are this same
  /// steel read against the card's own navy rather than a fourth colour.
  final Color wellBevel;

  /// The hairline printed under the window's floor, at x 40..964 and L 155.
  /// The window ends at L 105 and the card resumes dark; this rule is the
  /// bezel's outer edge catching the light, and without it the window sits on
  /// the card instead of in it.
  final Color wellRule;

  /// The window's floor is not one value: lit off the left wall it reads a
  /// charcoal, in the middle a darker one, and against the right wall it loses
  /// another third of its light. The plate is a recess cut into the card, and a
  /// flat floor makes it a hole punched in a photograph.
  final Color wellLit;
  final Color wellShade;

  /// A flip counter's card, its lit top edge, and the figures printed on it.
  ///
  /// The card is *lighter* than the window it stands in, which is the one
  /// relation that makes a wheel read as an object rather than a hole: the comp
  /// prints the face at L 46 against a well floor at L 20, with a crown edge at
  /// L 84 one plate pixel deep, and the face falls to L 27 by the foot. A face
  /// darker than its background inverts that, and the window stops being a row
  /// of wheels.
  final Color wheel;
  final Color wheelRim;
  final Color wheelInk;

  /// The dark plate the slot is cut through, the light along its rim, and the
  /// hole itself.
  final Color housing;
  final Color housingRim;
  final Color slotHole;

  /// The paper under the foil, and the thermal receipt a session ends as.
  final Color paper;
  final Color foil;
  final Color foilDark;

  /// Print that sits on foil or paper instead of on the card: the card's own
  /// cobalt, darkened until it is ink rather than a hole in the plate.
  final Color plateInk;

  /// A relay that did not deliver. Stays on the sheet, in the warm red the
  /// plate uses for the row it flags — never the accent, because a failure
  /// that borrows the colour of a good reading is the pseudo-Connected bug
  /// wearing a new face.
  final Color blocked;
  final Color blockedLift;

  /// The mark that says bytes actually crossed.
  final Color proven;

  static const day = MeteredColors(
    brightness: Brightness.light,
    card: Color(0xFF012248),
    cardDeep: Color(0xFF01152F),
    cardEdge: Color(0xFF4A6A8C),
    ink: Color(0xFFE9E1D4),
    inkSoft: Color(0xFFC2BAAA),
    inkFaint: Color(0xFF97907F),
    rule: Color(0x66D8CCBB),
    ruleStrong: Color(0xFFF3E4D4),
    value: Color(0xFFF66D2D),
    valueLift: Color(0xFFFF8B4C),
    valueOn: Color(0xFF10202F),
    well: Color(0xFF0E1215),
    wellLip: Color(0xFF000000),
    wellBevel: Color(0xFF797F8A),
    wellRule: Color(0xFF919CAE),
    wellLit: Color(0xFF1C2127),
    wellShade: Color(0xFF0A0C0F),
    wheel: Color(0xFF323030),
    wheelRim: Color(0xFF5C5C5D),
    wheelInk: Color(0xFFF0E7D6),
    housing: Color(0xFF1E2426),
    housingRim: Color(0xFFB9AEA4),
    slotHole: Color(0xFF020304),
    paper: Color(0xFFDED1C0),
    foil: Color(0xFFAEA8A0),
    foilDark: Color(0xFF6E6B66),
    plateInk: Color(0xFF05132A),
    blocked: Color(0xFFC9452B),
    blockedLift: Color(0xFFF08A63),
    proven: Color(0xFFF66D2D),
  );

  /// The payphone at night: the card goes charcoal and only the meter window
  /// keeps its light.
  static const night = MeteredColors(
    brightness: Brightness.dark,
    card: Color(0xFF101215),
    cardDeep: Color(0xFF08090B),
    cardEdge: Color(0xFF33393F),
    ink: Color(0xFFEDE7DA),
    inkSoft: Color(0xFFBCC3CB),
    inkFaint: Color(0xFF8A929B),
    rule: Color(0x406E7A86),
    ruleStrong: Color(0xFF96A2AE),
    value: Color(0xFFF4713C),
    valueLift: Color(0xFFF98F5F),
    valueOn: Color(0xFF14100C),
    well: Color(0xFF0B0D10),
    wellLip: Color(0xFF000000),
    wellBevel: Color(0xFF5A616B),
    wellRule: Color(0xFF6E7887),
    wellLit: Color(0xFF16191D),
    wellShade: Color(0xFF070809),
    wheel: Color(0xFF2C2A2B),
    wheelRim: Color(0xFF4A4B4E),
    wheelInk: Color(0xFFF6EAD2),
    housing: Color(0xFF1A1D20),
    housingRim: Color(0xFF7D848A),
    slotHole: Color(0xFF000000),
    paper: Color(0xFFD8D2C4),
    foil: Color(0xFF9BA0A5),
    foilDark: Color(0xFF5C6166),
    plateInk: Color(0xFF12181F),
    blocked: Color(0xFFD9573A),
    blockedLift: Color(0xFFF59770),
    proven: Color(0xFFF4713C),
  );

  bool get isNight => brightness == Brightness.dark;

  @override
  MeteredColors copyWith({
    Brightness? brightness,
    Color? card,
    Color? cardDeep,
    Color? cardEdge,
    Color? ink,
    Color? inkSoft,
    Color? inkFaint,
    Color? rule,
    Color? ruleStrong,
    Color? value,
    Color? valueLift,
    Color? valueOn,
    Color? well,
    Color? wellLip,
    Color? wellBevel,
    Color? wellRule,
    Color? wellLit,
    Color? wellShade,
    Color? wheel,
    Color? wheelRim,
    Color? wheelInk,
    Color? housing,
    Color? housingRim,
    Color? slotHole,
    Color? paper,
    Color? foil,
    Color? foilDark,
    Color? plateInk,
    Color? blocked,
    Color? blockedLift,
    Color? proven,
  }) {
    return MeteredColors(
      brightness: brightness ?? this.brightness,
      card: card ?? this.card,
      cardDeep: cardDeep ?? this.cardDeep,
      cardEdge: cardEdge ?? this.cardEdge,
      ink: ink ?? this.ink,
      inkSoft: inkSoft ?? this.inkSoft,
      inkFaint: inkFaint ?? this.inkFaint,
      rule: rule ?? this.rule,
      ruleStrong: ruleStrong ?? this.ruleStrong,
      value: value ?? this.value,
      valueLift: valueLift ?? this.valueLift,
      valueOn: valueOn ?? this.valueOn,
      well: well ?? this.well,
      wellLip: wellLip ?? this.wellLip,
      wellBevel: wellBevel ?? this.wellBevel,
      wellRule: wellRule ?? this.wellRule,
      wellLit: wellLit ?? this.wellLit,
      wellShade: wellShade ?? this.wellShade,
      wheel: wheel ?? this.wheel,
      wheelRim: wheelRim ?? this.wheelRim,
      wheelInk: wheelInk ?? this.wheelInk,
      housing: housing ?? this.housing,
      housingRim: housingRim ?? this.housingRim,
      slotHole: slotHole ?? this.slotHole,
      paper: paper ?? this.paper,
      foil: foil ?? this.foil,
      foilDark: foilDark ?? this.foilDark,
      plateInk: plateInk ?? this.plateInk,
      blocked: blocked ?? this.blocked,
      blockedLift: blockedLift ?? this.blockedLift,
      proven: proven ?? this.proven,
    );
  }

  @override
  MeteredColors lerp(covariant MeteredColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return MeteredColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      card: c(card, other.card),
      cardDeep: c(cardDeep, other.cardDeep),
      cardEdge: c(cardEdge, other.cardEdge),
      ink: c(ink, other.ink),
      inkSoft: c(inkSoft, other.inkSoft),
      inkFaint: c(inkFaint, other.inkFaint),
      rule: c(rule, other.rule),
      ruleStrong: c(ruleStrong, other.ruleStrong),
      value: c(value, other.value),
      valueLift: c(valueLift, other.valueLift),
      wheel: c(wheel, other.wheel),
      wheelRim: c(wheelRim, other.wheelRim),
      wheelInk: c(wheelInk, other.wheelInk),
      housing: c(housing, other.housing),
      housingRim: c(housingRim, other.housingRim),
      slotHole: c(slotHole, other.slotHole),
      paper: c(paper, other.paper),
      foil: c(foil, other.foil),
      foilDark: c(foilDark, other.foilDark),
      plateInk: c(plateInk, other.plateInk),
      blocked: c(blocked, other.blocked),
      blockedLift: c(blockedLift, other.blockedLift),
      proven: c(proven, other.proven),
      valueOn: c(valueOn, other.valueOn),
      well: c(well, other.well),
      wellLip: c(wellLip, other.wellLip),
      wellBevel: c(wellBevel, other.wellBevel),
      wellRule: c(wellRule, other.wellRule),
      wellLit: c(wellLit, other.wellLit),
      wellShade: c(wellShade, other.wellShade),
    );
  }
}

extension MeteredOnContext on BuildContext {
  MeteredColors get metered =>
      Theme.of(this).extension<MeteredColors>() ?? MeteredColors.day;
}
