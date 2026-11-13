import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/theme/metered_colors.dart';

/// One reading inside the credit window.
class MeterCell {
  const MeterCell({
    required this.rubric,
    required this.value,
    required this.unit,
    this.nudge,
  });

  /// What the figure measures, printed above it.
  final String rubric;
  final String value;

  /// The unit, printed below in the same fixed cell.
  final String unit;

  /// Which character is caught mid-clack, or null for none. Only set it while
  /// bytes are actually crossing: a wheel frozen mid-turn is a claim of
  /// movement.
  final int? nudge;

  /// The comp advances 60px of tile and 22px of gutter between two cards, and
  /// the point is printed inside that gutter rather than costing a card of its
  /// own: "64" is 2.5 tiles across, "8.12" is 4.05.
  double get units {
    var w = 0.0;
    for (var i = 0; i < value.length; i++) {
      final point = value[i] == '.';
      if (i > 0 && !point && value[i - 1] != '.') w += 11 / 30;
      w += point ? 0.55 : 1.0;
    }
    return w;
  }
}

/// The credit window: a recessed well of fixed flip cells. A wheel only moves
/// when a byte actually crossed, so a still window is an honest window.
class FlipMeter extends StatelessWidget {
  const FlipMeter({super.key, required this.cells, this.recessed = true});

  final List<MeterCell> cells;

  /// Draw the black window cut into the card, or bare wheels on a card face.
  final bool recessed;

  /// Everything below is a fraction of the tile, which is the only length the
  /// window really owns, and every one of them is measured off the approved
  /// comp at 1024x1792 rather than off a plate: the hole runs 283..546, a tile
  /// 373..476 (103 tall, 60 wide, 22 of gutter between cards), the rubric's ink
  /// 339..358, the figures' ink 397..454 (58 tall), the unit's ink 491..513.
  ///
  /// It is *derived* from those parts rather than written down beside them.
  /// They were written down once, summed to 275, and the constant said 2.702,
  /// which is 262 — the well's own height. The stack was 13px taller than the
  /// hole for as long as it has existed; four columns of digits squeezed the
  /// whole meter by enough to hide it, and the day the window went to three
  /// columns the overflow showed up as 4.5px of yellow. A tile is the well's
  /// height divided by the stack, so the window keeps the comp's proportions on
  /// a phone of any height and cannot outgrow its own hole.
  static const double _stackOfTile =
      _padTop +
      _rubricOfTile +
      _rubricGap +
      1.0 +
      _unitGap +
      _unitOfTile +
      _padBottom;

  /// A tile is 60 wide against 102 tall.
  static const double _tileWidthOfTile = 60 / 102;

  /// The gutter the comp leaves between two cards: 22 against a 60-wide card.
  static const double _gutterOfTile = 22 / 60;

  /// A figure is 58px of ink. The face renders its figures at 0.760 of the em
  /// and its capitals at 0.746, both read off a capture rather than the
  /// family's sheet: a 76.7em figure put out 58px and a 33.5em rubric 25px.
  static const double _figureOfTile = 58 / 0.760 / 102;

  /// The rubric's 20px of cap and the unit's 22px, on the capital ratio.
  static const double _rubricOfTile = 20 / 0.746 / 102;
  static const double _unitOfTile = 22 / 0.746 / 102;

  /// The air between the print boxes and the tiles. `height: 1.0` leaves the
  /// ink only ~0.1em inside the top of its own box, so these are the comp's
  /// ink-to-ink rows minus that: the rubric's box starts 53 below the hole's
  /// crown to put its ink on 339, and its box ends 8.7 before the tile's crown
  /// at 373; the unit's box begins 12 past the tile's foot so its ink lands on
  /// 491 and ends 29 above the hole's floor.
  static const double _padTop = 53 / 102;
  static const double _rubricGap = 11.7 / 102;
  static const double _unitGap = 9.2 / 102;
  static const double _padBottom = 29.3 / 102;

  /// The plate's own columns across the hole: 226, 291, 205 and 212 of 934.
  /// They are not equal, and they are not proportional to how many cards each
  /// group turns — the window is ruled into four bays and the readings are set
  /// inside them.
  static const List<int> _columnFlex = [226, 291, 205, 212];

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    return LayoutBuilder(
      builder: (context, c) {
        // The plate sets the figure size; the window only ever shrinks it.
        var tileH = c.maxHeight / _stackOfTile;
        var tileW = tileH * _tileWidthOfTile;
        final flexes = cells.length == _columnFlex.length
            ? _columnFlex
            : List<int>.filled(cells.length, 1);
        final totalFlex = flexes.fold<int>(0, (sum, f) => sum + f);
        // A reading longer than its bay gives up size before it gives up a
        // digit: the window is fixed, and a card that slides out of it is a
        // broken meter.
        var k = 1.0;
        for (var i = 0; i < cells.length; i++) {
          final bay = c.maxWidth * flexes[i] / totalFlex - tileW * 0.10;
          final need = (cells[i].units + _gutterOfTile) * tileW;
          if (need > bay) k = math.min(k, bay / need);
        }
        tileW *= k;
        tileH *= k;
        final hairline = tileW / 60;
        // The bay boundaries, so the separators land where the plate put them
        // instead of costing a bay their share of the window.
        var before = 0.0;
        final bounds = <double>[];
        for (var i = 0; i < flexes.length - 1; i++) {
          before += c.maxWidth * flexes[i] / totalFlex;
          bounds.add(before);
        }
        return Stack(
          fit: StackFit.expand,
          // The bezel's outer rule is printed below the hole, on the card.
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(tileH * 0.15),
                gradient: recessed
                    ? LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [m.wellLit, m.well, m.wellShade],
                        stops: const [0.08, 0.46, 0.92],
                      )
                    : null,
                boxShadow: recessed
                    ? [
                        BoxShadow(
                          color: m.wellLip.withValues(alpha: 0.9),
                          blurRadius: 0,
                          spreadRadius: hairline,
                        ),
                        BoxShadow(
                          color: const Color(0x66000000),
                          blurRadius: tileH * 0.10,
                          offset: Offset(0, tileH * 0.04),
                        ),
                      ]
                    : null,
              ),
            ),
            // The window is set in a bezel, and three of its four walls catch
            // light. Measured off the plate along the hole's own edges: the left
            // lip reads #797f8a (L 127) over 423 pixels, the right #677b95
            // (L 120) over 458, the floor lifts to #506e8e (L 105) over 961, and
            // the top wall stays in shadow at #415975 (L 85). A BoxDecoration
            // cannot carry four different border colours under a radius, so the
            // chamfer is four clipped strips, and the three lit ones are this
            // one steel read at 1.0, 0.90 and 0.78 against the dark floor.
            if (recessed)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(tileH * 0.15),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: hairline * 3,
                        child: ColoredBox(color: m.wellBevel),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        height: hairline * 2,
                        child: ColoredBox(
                          color: m.wellBevel.withValues(alpha: 0.55),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: hairline * 3,
                        child: ColoredBox(
                          color: m.wellBevel.withValues(alpha: 0.90),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: hairline * 2,
                        child: ColoredBox(
                          color: m.wellBevel.withValues(alpha: 0.78),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // The bezel's outer edge, printed on the card 4px under the floor
            // and running from x 40 to x 964 at L 155. It is the last thing the
            // window owns before the card takes over again, and without it the
            // hole sits on the surface instead of cut into it.
            if (recessed)
              Positioned(
                left: hairline,
                right: hairline * 18,
                bottom: -hairline * 6,
                height: hairline * 2,
                child: ColoredBox(color: m.wellRule),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: tileH * _padTop,
              bottom: tileH * _padBottom,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (var i = 0; i < cells.length; i++)
                    Expanded(
                      flex: flexes[i],
                      child: _MeterGroup(
                        cell: cells[i],
                        tileWidth: tileW,
                        tileHeight: tileH,
                      ),
                    ),
                ],
              ),
            ),
            if (recessed)
              for (var i = 0; i < bounds.length; i++)
                Positioned(
                  left: bounds[i] - hairline / 2,
                  top: c.maxHeight * 0.5 - tileH * 0.72,
                  width: hairline,
                  height: tileH * 1.44,
                  child: ColoredBox(color: m.foil),
                ),
          ],
        );
      },
    );
  }
}

class _MeterGroup extends StatelessWidget {
  const _MeterGroup({
    required this.cell,
    required this.tileWidth,
    required this.tileHeight,
  });

  final MeterCell cell;
  final double tileWidth;
  final double tileHeight;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    final rubricSize = tileHeight * FlipMeter._rubricOfTile;
    final unitSize = tileHeight * FlipMeter._unitOfTile;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The rubric box is reserved even when the reading has no name, so
        // every row of wheels in the window turns at the same height. A still
        // gap where a word would be is not a layout bug — it is the plate.
        SizedBox(
          height: tileHeight * FlipMeter._rubricOfTile,
          child: cell.rubric.isEmpty
              ? null
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    cell.rubric,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.label(
                      color: m.ink,
                      size: rubricSize,
                      tracking: 0.0,
                    ).copyWith(height: 1.0),
                  ),
                ),
        ),
        SizedBox(height: tileHeight * FlipMeter._rubricGap),
        SizedBox(
          height: tileHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < cell.value.length; i++) ...[
                if (i > 0 && cell.value[i] != '.' && cell.value[i - 1] != '.')
                  SizedBox(width: tileWidth * FlipMeter._gutterOfTile),
                _WheelTile(
                  glyph: cell.value[i],
                  clacking: cell.nudge == i,
                  width: tileWidth,
                  height: tileHeight,
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: tileHeight * FlipMeter._unitGap),
        SizedBox(
          height: tileHeight * FlipMeter._unitOfTile,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              cell.unit,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: AppTextStyles.metric(
                color: m.ink,
                size: unitSize,
                weight: FontWeight.w500,
                tracking: 0,
              ).copyWith(height: 1.0),
            ),
          ),
        ),
      ],
    );
  }
}

/// A single flip tile. A mid-clack tile shows the figure tipping into view:
/// still legible, still moving, never an empty card.
class _WheelTile extends StatelessWidget {
  const _WheelTile({
    required this.glyph,
    required this.clacking,
    required this.width,
    required this.height,
  });

  final String glyph;
  final bool clacking;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    final style = AppTextStyles.metric(
      color: m.wheelInk,
      size: height * FlipMeter._figureOfTile,
      weight: FontWeight.w700,
      tracking: 0,
    );
    if (glyph == '.') {
      // The point is printed on the well, between two cards: it is not a
      // wheel, and a wheel that holds a point would have to be turned.
      return SizedBox(
        width: width * 0.55,
        child: Center(child: Text(glyph, style: style)),
      );
    }
    final radius = BorderRadius.circular(height * 0.085);
    final hairline = width / 60;
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              m.wheelRim,
              m.wheel,
              // The comp's card is not flat: at x 118 it reads L 46 three rows
              // under the crown and L 27 four rows above the foot, so the face
              // falls a little under half its own light on the way down.
              Color.lerp(m.wheel, Colors.black, 0.42)!,
            ],
            stops: const [0.0, 0.02, 1.0],
          ),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.75),
            width: hairline,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: height * 0.09,
              offset: Offset(0, height * 0.035),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (clacking)
                Transform.translate(
                  offset: Offset(0, -height * 0.09),
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.24)
                      ..rotateX(math.pi * 0.07),
                    child: Center(child: Text(glyph, style: style)),
                  ),
                )
              else
                Center(child: Text(glyph, style: style)),
              // The seam between two cards on the wheel.
              Positioned(
                left: 0,
                right: 0,
                top: height / 2 - hairline / 2,
                child: Container(
                  height: hairline,
                  color: Colors.black.withValues(alpha: 0.55),
                ),
              ),
              if (clacking)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: height / 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.40),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
