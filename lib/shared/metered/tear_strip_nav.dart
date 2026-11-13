import 'package:flutter/material.dart';

import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/theme/metered_colors.dart';
import 'package:bulbvpn/shared/metered/metered_layout.dart';
import 'package:bulbvpn/shared/metered/pressable.dart';

class TearSegment {
  const TearSegment({required this.label, required this.index, this.flex = 1});
  final String label;
  final int index;
  final int flex;
}

/// The teeth of a tear, shared by the paper that tore and the stub it left.
///
/// They come from a fixed table, not a random one: a card does not re-tear
/// itself every frame. The tables are transcribed off the plate, one sample
/// every 3.5px down the band, because the plate's fibre turns every 3px — a
/// table sampled at 15px smooths into a wave and a wave is water, not paper.
const int _n = 61;

/// How far a torn paper edge sits inside its boundary, in tear units, positive
/// where the paper stops short of the boundary it was torn along. Measured off
/// the plate's CONNECT tab: it holds to about a third of the tear inside,
/// loosens to two thirds across the middle, and lets go again at the foot.
const List<double> _fibre = [
  0.75, 0.71, 0.10, 0.10, 0.49, 0.40, 0.36, //
  0.36, 0.36, 0.45, 0.58, 0.58, 0.49, 0.45, 0.36, //
  0.19, 0.28, 0.23, 0.23, 0.28, 0.32, 0.40, 0.45, //
  0.45, 0.49, 0.53, 0.53, 0.58, 0.53, 0.71, 0.53, //
  0.45, 0.45, 0.49, 0.49, 0.49, 0.36, 0.36, 0.23, //
  0.19, 0.19, 0.19, 0.02, -0.03, -0.16, 0.02, 0.02, //
  0.15, 0.19, 0.28, 0.28, 0.28, 0.19, 0.15, 0.06, //
  0.02, 0.10, 0.15, 0.15, 0.19, 0.19,
];

/// The two edges of a stub — the ribbon of paper that stayed on the card when
/// the tab came away — measured off both of the plate's surviving stubs and
/// averaged. They are independent tables because the paper tore on both sides
/// at once, so the two edges have nothing to say to each other. Together they
/// hold 0.84 of a tear, about 20 plate px, and they never pinch out: the stub
/// is a ribbon the full length of the band, not a stripe that fades.
const List<double> _stubL = [
  -0.38, -0.74, -0.64, -0.43, -0.43, -0.43, -0.43, //
  -0.41, -0.43, -0.43, -0.56, -0.60, -0.55, -0.73, //
  -0.85, -0.81, -0.86, -0.83, -0.75, -0.77, -0.77, //
  -0.71, -0.69, -0.69, -0.61, -0.59, -0.59, -0.55, //
  -0.55, -0.53, -0.53, -0.53, -0.48, -0.51, -0.51, //
  -0.51, -0.51, -0.53, -0.53, -0.53, -0.53, -0.51, //
  -0.51, -0.51, -0.60, -0.51, -0.51, -0.51, -0.51, //
  -0.48, -0.48, -0.48, -0.51, -0.55, -0.33, -0.57, //
  -0.57, -0.68, -0.74, -0.51, -0.45,
];

const List<double> _stubR = [
  -0.28, -0.23, -0.04, 0.16, 0.24, 0.35, 0.37, //
  0.27, 0.20, 0.14, 0.10, 0.05, 0.07, 0.12, //
  0.18, 0.29, 0.28, 0.29, 0.27, 0.20, 0.15, //
  0.12, 0.07, 0.05, 0.10, 0.00, 0.03, 0.12, //
  0.12, 0.07, 0.24, 0.16, 0.16, 0.13, 0.18, //
  0.29, 0.38, 0.48, 0.45, 0.53, 0.53, 0.68, //
  0.69, 0.53, 0.51, 0.54, 0.44, 0.37, 0.33, //
  0.38, 0.33, 0.37, 0.46, 0.52, 0.61, 0.58, //
  0.51, 0.48, 0.42, 0.35, 0.38,
];

double _at(List<double> table, int i, int phase) => table[(i + phase) % _n];

/// The edge of a tab that came away at the boundary `x`.
///
/// `dir` is -1 when the tab is to the left of the boundary and +1 when it is to
/// the right. `phase` walks each boundary through the table from its own place
/// so two tears on one card are not two copies of one shape.
double _tornEdge(double x, int i, int phase, int dir, double tear) =>
    x + dir * tear * _at(_fibre, i, phase);

/// The perforated strip along the foot of the card. The segment you are on has
/// been torn off — it is printed on the paper side, in the card's own ink — and
/// the rest are still attached, so the tear line runs down between them.
///
/// The tears are not a border. Where a tab came away the paper simply stops,
/// ragged, a third to two thirds of a tear inside the boundary; where nothing
/// came away the plate leaves a stub of paper about four fifths of a tear wide
/// standing on the boundary.
class TearStripNav extends StatelessWidget {
  const TearStripNav({
    super.key,
    required this.segments,
    required this.active,
    required this.onSelect,
    required this.type,
  });

  final List<TearSegment> segments;
  final int active;
  final ValueChanged<int> onSelect;

  /// The card's print sizes: a segment label is plate print like the rest.
  final MeteredType type;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    return LayoutBuilder(
      builder: (context, c) {
        final band = c.maxHeight;
        final total = segments.fold<int>(0, (sum, s) => sum + s.flex);
        // The boundary between segment i and i+1, in the same logical x the
        // Expandeds are laid out at, so the tear lands where the flex says.
        final boundaries = <double>[];
        var before = 0;
        for (var i = 0; i < segments.length - 1; i++) {
          before += segments[i].flex;
          boundaries.add(before / total * c.maxWidth);
        }
        final tear = band * 0.11;
        // The tab that came away, and the two boundaries it came away from.
        // Where there is no boundary the tab is the card's own edge and stays
        // square.
        final onLeft = active > 0 ? boundaries[active - 1] : null;
        final onRight = active < segments.length - 1
            ? boundaries[active]
            : null;
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            // The paper goes under the print: the label is on the tab, and the
            // tab's edge is torn, so the body has to be drawn first and by a
            // painter that agrees with the cut about where the fibre is.
            CustomPaint(
              painter: _TabPaper(
                left: onLeft,
                right: onRight,
                phase: active,
                band: band,
                tear: tear,
                paper: m.paper,
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < segments.length; i++)
                  Expanded(
                    flex: segments[i].flex,
                    child: Pressable(
                      onTap: () => onSelect(segments[i].index),
                      child: _Segment(
                        segment: segments[i],
                        active: i == active,
                        band: band,
                        type: type,
                      ),
                    ),
                  ),
              ],
            ),
            CustomPaint(
              painter: _TearPainter(
                boundaries: boundaries,
                tear: tear,
                paper: m.paper,
                active: active,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: band * 0.20,
              child: _Perforation(boundaries: boundaries, tear: tear),
            ),
          ],
        );
      },
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.segment,
    required this.active,
    required this.band,
    required this.type,
  });

  final TearSegment segment;
  final bool active;
  final double band;
  final MeteredType type;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    if (!active) {
      return Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            segment.label,
            maxLines: 1,
            style: AppTextStyles.label(
              color: m.ink,
              size: type.navLabelAttached,
              tracking: 0.0,
            ).copyWith(height: 1.0, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }
    // The torn tab is the card's own cobalt printed on the paper that came
    // away from it, in the display face the wordmark uses. The paper itself is
    // painted behind the row, because its edge is torn and a BoxDecoration
    // cannot draw one.
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: band * 0.10),
          child: Text(
            segment.label,
            maxLines: 1,
            style: AppTextStyles.masthead(
              color: m.plateInk,
              size: type.navLabel,
              tracking: 0.0,
            ),
          ),
        ),
      ),
    );
  }
}

/// The body of the tab that came away from the strip.
///
/// It is paper, and it tore: the two edges where it came free are the same
/// ragged polylines the plate's CONNECT tab shows, and the two edges that were
/// never attached to anything are the card's own outline. The paper runs right
/// up to the boundary and stops there — the plate draws no dark cut between the
/// tab and the navy, only the ragged edge itself against the card.
class _TabPaper extends CustomPainter {
  const _TabPaper({
    required this.left,
    required this.right,
    required this.phase,
    required this.band,
    required this.tear,
    required this.paper,
  });

  /// The boundary the tab tore away from on each side, or null where the tab
  /// runs to the card's own edge.
  final double? left;
  final double? right;

  /// The tab's own ordinal, so each of its torn edges walks the fibre table
  /// from the same place the tear painter walks it.
  final int phase;
  final double band;
  final double tear;
  final Color paper;

  /// The tab's corners are rounded only where nothing tore. The plate's top
  /// corner carries an 18px radius and its bottom one 55 — the tab was pulled
  /// upward and away, so the fibre left more paper behind at the foot.
  double get _topCorner => band * 0.085;
  double get _bottomCorner => band * 0.26;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final l = left;
    final r = right;
    final lp = (phase - 1) * 5;
    final rp = phase * 5;
    final tl = l == null ? _topCorner : 0.0;
    final tr = r == null ? _topCorner : 0.0;
    final bl = l == null ? _bottomCorner : 0.0;
    final br = r == null ? _bottomCorner : 0.0;

    final path = Path()
      ..moveTo(l == null ? tl : _tornEdge(l, 0, lp, 1, tear), 0);
    if (r != null) {
      for (var i = 0; i < _n; i++) {
        path.lineTo(_tornEdge(r, i, rp, -1, tear), h * i / (_n - 1));
      }
    } else {
      path.lineTo(size.width - tr, 0);
      path.quadraticBezierTo(size.width, 0, size.width, tr);
      path.lineTo(size.width, h - br);
      path.quadraticBezierTo(size.width, h, size.width - br, h);
    }
    if (l != null) {
      for (var i = _n - 1; i >= 0; i--) {
        path.lineTo(_tornEdge(l, i, lp, 1, tear), h * i / (_n - 1));
      }
    } else {
      path.lineTo(bl, h);
      path.quadraticBezierTo(0, h, 0, h - bl);
      path.lineTo(0, tl);
      path.quadraticBezierTo(0, 0, tl, 0);
    }
    canvas.drawPath(path..close(), Paint()..color = paper);
  }

  @override
  bool shouldRepaint(_TabPaper old) =>
      old.left != left ||
      old.right != right ||
      old.phase != phase ||
      old.band != band ||
      old.tear != tear ||
      old.paper != paper;
}

/// The punch holes a card is torn along. The line stops at every tear: a hole
/// that survives being torn through is a hole painted on, not a hole.
class _Perforation extends StatelessWidget {
  const _Perforation({required this.boundaries, required this.tear});

  final List<double> boundaries;
  final double tear;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    return SizedBox(
      width: double.infinity,
      child: CustomPaint(
        painter: _PunchPainter(
          // A punch through the card is a hole through it: the plate darkens to
          // near-black at the perforation, and cardDeep on cardDeep is a smudge
          // that reads as print rather than as an opening.
          hole: Color.lerp(m.card, const Color(0xFF000000), 0.82)!,
          lip: m.ink,
          boundaries: boundaries,
          skip: tear * 1.4,
        ),
      ),
    );
  }
}

class _PunchPainter extends CustomPainter {
  const _PunchPainter({
    required this.hole,
    required this.lip,
    required this.boundaries,
    required this.skip,
  });

  final Color hole;
  final Color lip;
  final List<double> boundaries;
  final double skip;

  @override
  void paint(Canvas canvas, Size size) {
    // The plate steps its punches 34.6px apart with a 16px hole, and this box
    // is the top fifth of a 211px band — so a hole is 0.38 of the box and a
    // step is 0.82 of it. The step comes from the band, not from the width, or
    // the punch line drifts as the card gets wider than the plate. The first
    // punch lands 29px into the card, which is 0.85 of a step.
    final diameter = size.height * 0.38;
    final step = size.height * 0.82;
    final centre = size.height * 0.50;
    final body = Paint()..color = hole;
    // The lip is a hairline of the plate's own weight: a punch that catches
    // light along its lower edge is a hole, and one drawn with a fat ring is a
    // dot.
    final lipPaint = Paint()
      ..color = lip.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.024;
    for (var x = step * 0.85; x < size.width; x += step) {
      if (boundaries.any((b) => (x - b).abs() < skip)) continue;
      final c = Offset(x, centre);
      canvas.drawCircle(c, diameter / 2, body);
      canvas.drawCircle(
        c.translate(0, size.height * 0.017),
        diameter / 2,
        lipPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_PunchPainter old) =>
      old.hole != hole ||
      old.lip != lip ||
      old.boundaries != boundaries ||
      old.skip != skip;
}

/// The stub of paper a tear leaves on the card.
///
/// Only the boundaries the tab did not come away from get one: where the tab
/// tore, its own ragged edge is the whole of the tear, and the plate paints
/// nothing beside it. Where nothing came away, the paper that held the two
/// halves together stays on the card as a ribbon four fifths of a tear wide,
/// standing on the boundary and frayed along both its edges.
class _TearPainter extends CustomPainter {
  const _TearPainter({
    required this.boundaries,
    required this.tear,
    required this.paper,
    required this.active,
  });

  final List<double> boundaries;
  final double tear;
  final Color paper;
  final int active;

  @override
  void paint(Canvas canvas, Size size) {
    final body = Paint()..color = paper;
    for (var b = 0; b < boundaries.length; b++) {
      // The tab took the paper at its own two boundaries; everything else kept
      // its stub.
      if (b == active || b == active - 1) continue;
      final x = boundaries[b];
      final phase = b * 5;
      final h = size.height;
      final path = Path();
      for (var i = 0; i < _n; i++) {
        final y = h * i / (_n - 1);
        final l = x + _at(_stubL, i, phase) * tear;
        if (i == 0) {
          path.moveTo(l, y);
        } else {
          path.lineTo(l, y);
        }
      }
      for (var i = _n - 1; i >= 0; i--) {
        path.lineTo(x + _at(_stubR, i, phase) * tear, h * i / (_n - 1));
      }
      canvas.drawPath(path..close(), body);
    }
  }

  @override
  bool shouldRepaint(_TearPainter old) =>
      old.boundaries != boundaries ||
      old.tear != tear ||
      old.paper != paper ||
      old.active != active;
}
