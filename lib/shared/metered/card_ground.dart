import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bulbvpn/core/theme/metered_colors.dart';

import 'metered_layout.dart';

/// The card itself: printed PVC ground, the scuff plate laid over it, and the
/// worn paint along its edge. Every Metered surface sits inside this.
class CardGround extends StatelessWidget {
  const CardGround({
    super.key,
    required this.child,
    this.insets = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsets insets;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: m.card,
        borderRadius: const BorderRadius.all(
          Radius.circular(MeteredLayout.cardRadius),
        ),
        boxShadow: [
          BoxShadow(
            color: m.cardDeep.withValues(alpha: 0.9),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(
          Radius.circular(MeteredLayout.cardRadius),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/plates/card-ground.png',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              // The plate is already the card's ink: modulating it by the card
              // colour again only buries the grain. Night dims it instead, so
              // the cobalt reads as charcoal under the same scuffs.
              opacity: AlwaysStoppedAnimation(m.isNight ? 0.34 : 1.0),
            ),
            const _WornEdge(),
            Padding(padding: insets, child: child),
          ],
        ),
      ),
    );
  }
}

/// The paint that has rubbed off the corners and along the edge of a card that
/// has been in a pocket. It is the only decoration the ground is allowed.
///
/// On the plate it is a hairline that hugs the outline and wanders a few pixels
/// in depth, brightest at the corners, and a diagonal gradient can only say
/// "lighter here, darker there" — so it draws a bevel where the plate has a
/// scar, and this walks the card's own outline instead.
class _WornEdge extends StatelessWidget {
  const _WornEdge();

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The card is lit off its top-left corner and loses that light to
          // the bottom-right; the plate holds about 12 points of luminance
          // across the diagonal.
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(
                Radius.circular(MeteredLayout.cardRadius),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  m.cardEdge.withValues(alpha: 0.30),
                  Colors.transparent,
                  Colors.transparent,
                  m.cardDeep.withValues(alpha: 0.55),
                ],
                stops: const [0.0, 0.16, 0.74, 1.0],
              ),
            ),
          ),
          CustomPaint(
            painter: _WornRim(paper: m.paper, radius: MeteredLayout.cardRadius),
          ),
        ],
      ),
    );
  }
}

/// The broken ivory rim: the card's own substrate showing through its paint.
///
/// It is one scar that wanders in depth, not a row of ticks at a fixed one, and
/// not a band either: the plate's wear is a quarter-tone line within a few
/// pixels of the outline on every lip, and the corners are the only place it
/// lifts to full paper. The walk steps at the rate the lip's own profile
/// implies, so the hairline is continuous where the plate reads it continuous
/// and broken where the plate reads it broken.
class _WornRim extends CustomPainter {
  const _WornRim({required this.paper, required this.radius});

  final Color paper;
  final double radius;

  static const double _plateWidth = 1024;

  /// The two rows a straight lip is read at, the width each carries, and what
  /// the plate measures along it there.
  ///
  /// Read as a single row at six depths, the plate looks like a profile that
  /// peaks 2 to 6px in and tails to nothing by 18, and a rim built to that
  /// number paints a comb of paper-coloured dashes well inside the card. Read
  /// the other way — for each position along the lip, the *shallowest* depth
  /// that is bright at all — the same plate says something different: 88 to 98%
  /// of the way along every lip there is a bright pixel within 1 to 6px of the
  /// outline, and its median luminance is 78 to 84, which is paper at about a
  /// quarter over the card's navy. The wear is one faint hairline that hugs the
  /// edge and wanders a couple of pixels in depth, not a band of flakes, and the
  /// rows past 6px that the single-row reading filled were the plate's own
  /// scuffs, which the ground image already prints.
  static const List<double> _depth = [2.5, 5.5];
  static const List<double> _width = [2.0, 2.6];

  static const _Lip _top = _Lip([0.97, 0.40], [0.27, 0.19], [30, 12]);
  static const _Lip _left = _Lip([0.98, 0.45], [0.26, 0.19], [34, 14]);
  static const _Lip _right = _Lip([0.88, 0.50], [0.25, 0.19], [26, 12]);
  static const _Lip _bottom = _Lip([0.93, 0.55], [0.28, 0.20], [30, 14]);

  /// The corners are the one place the wear is genuinely bright: read along the
  /// arc it reaches full paper 6 to 10px in, where the straight lips stay a
  /// quarter over the navy. It sits inside the outline rather than on it, and
  /// the bottom-right is clean at the edge and heavily worn 10px in, which is
  /// where the card was pinched.
  static const List<double> _cornerDepth = [0, 5, 11];
  static const List<double> _cornerWidth = [2.0, 4.0, 5.0];
  static const _Lip _cornerTL = _Lip([0.26, 0.92, 0.78], [0.17, 0.82, 0.77], [
    26, 26, 22, //
  ]);
  static const _Lip _cornerTR = _Lip([0.20, 0.64, 0.38], [0.21, 0.48, 0.80], [
    26, 26, 22, //
  ]);
  static const _Lip _cornerBR = _Lip([0.00, 0.32, 1.00], [0.00, 0.23, 0.61], [
    26, 26, 22, //
  ]);
  static const _Lip _cornerBL = _Lip([0.54, 0.78, 1.00], [0.17, 0.50, 0.97], [
    26, 26, 22, //
  ]);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / _plateWidth;
    final r = math.min(radius, math.min(size.width, size.height) / 2);
    final body = Paint()
      ..color = paper
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;
    final x1 = size.width, y1 = size.height;

    var i = 0;
    i = _piece(body, x1 - 2 * r, _depth, _width, _top, k, 0, i, (a, b, ins, w) {
      canvas.drawLine(Offset(r + a, ins), Offset(r + b, ins), body);
    });
    i = _corner(
      canvas,
      body,
      Offset(x1 - r, r),
      r,
      -math.pi / 2,
      _cornerTR,
      k,
      i,
    );
    i = _piece(body, y1 - 2 * r, _depth, _width, _right, k, 1, i, (
      a,
      b,
      ins,
      w,
    ) {
      canvas.drawLine(Offset(x1 - ins, r + a), Offset(x1 - ins, r + b), body);
    });
    i = _corner(canvas, body, Offset(x1 - r, y1 - r), r, 0, _cornerBR, k, i);
    i = _piece(body, x1 - 2 * r, _depth, _width, _bottom, k, 2, i, (
      a,
      b,
      ins,
      w,
    ) {
      canvas.drawLine(
        Offset(x1 - r - a, y1 - ins),
        Offset(x1 - r - b, y1 - ins),
        body,
      );
    });
    i = _corner(
      canvas,
      body,
      Offset(r, y1 - r),
      r,
      math.pi / 2,
      _cornerBL,
      k,
      i,
    );
    i = _piece(body, y1 - 2 * r, _depth, _width, _left, k, 3, i, (
      a,
      b,
      ins,
      w,
    ) {
      canvas.drawLine(Offset(ins, y1 - r - a), Offset(ins, y1 - r - b), body);
    });
    _corner(canvas, body, Offset(r, r), r, math.pi, _cornerTL, k, i);
  }

  /// Walk one corner's quarter arc with its own lip, then hand the index on so
  /// the four corners and four sides do not all start their scatter at zero.
  ///
  /// A corner is 40 plate px of arc: one or two marks wide. Sampling the plate's
  /// 0.85 and 0.38 coverage there as a scatter leaves a corner either fully worn
  /// or untouched and lets the walk index decide which, so the corner takes its
  /// wear as a sweep instead, whose share of the arc the lip's coverage sets and
  /// whose place along it the hash picks, at each depth the plate reads. The
  /// plate's corners are broad bright arcs, not confetti.
  int _corner(
    Canvas canvas,
    Paint body,
    Offset centre,
    double r,
    double base,
    _Lip lip,
    double k,
    int index,
  ) {
    final quarter = math.pi / 2;
    for (var d = 0; d < lip.cov.length; d++) {
      if (lip.cov[d] <= 0) continue;
      final rr = r - _cornerDepth[d] * k;
      if (rr <= 0) continue;
      final sweep = (0.4 + 0.6 * lip.cov[d]) * quarter;
      final from = base + _hash(index + d, 5) * (quarter - sweep);
      body.color = paper.withValues(alpha: lip.lit[d]);
      body.strokeWidth = _cornerWidth[d] * k;
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: rr),
        from,
        sweep,
        false,
        body,
      );
    }
    return index + 1;
  }

  /// A deterministic hash of the walk index, not a time-varying one: the card
  /// is scuffed once, and a rim that re-scatters on repaint flickers.
  static double _hash(int i, int seed) {
    var h = (i * 2654435761 + seed * 40503) & 0x7fffffff;
    h = (h * 1103515245 + 12345) & 0x7fffffff;
    return (h >> 8) / 8388607.0;
  }

  /// Walk one side of the outline, stepping at the rate the lip's own profile
  /// implies rather than at a pitch picked to look right: a row the plate reads
  /// as bare across cov of its length, wearing marks of length mark, needs
  /// cov/mark mark-starts per plate px, and the sum of those six rates is how
  /// often the walk has to try. Each trial spends itself on one depth, chosen by
  /// that same share, so the row at 2px ends up holding the 75% the plate
  /// measures there and the row at 18px the 2%, and no row is a line of aligned
  /// ticks: the scar wanders in depth, which is what one rubbed edge is actually
  /// doing when the plate is read across it.
  int _piece(
    Paint body,
    double len,
    List<double> depth,
    List<double> width,
    _Lip lip,
    double k,
    int edge,
    int index,
    void Function(double from, double to, double ins, double w) draw,
  ) {
    if (len <= 0) return index;
    final rate = lip.rate;
    if (rate <= 0) return index;
    final step = k / rate;
    var i = index;
    for (var t = 0.0; t < len; t += step, i++) {
      var u = _hash(i, edge) * rate;
      var d = 0;
      while (d < lip.cov.length - 1 && u > lip.lambdaAt(d)) {
        u -= lip.lambdaAt(d);
        d++;
      }
      final f = math.min(
        lip.mark[d] * k * (0.6 + 0.8 * _hash(i, edge + 9)),
        len - t,
      );
      if (f <= 0) continue;
      body.color = paper.withValues(alpha: lip.lit[d]);
      body.strokeWidth = width[d] * k;
      // The six depths are where the plate was read, not six channels the wear
      // is confined to. Without the smear every mark that the profile sends to
      // 2px lands on the same row and chains into a run four times the plate's,
      // which is the difference between a scar and a dash.
      final ins = (depth[d] + (_hash(i, edge + 4) - 0.5) * 2.2) * k;
      draw(t, t + f, math.max(0.4 * k, ins), width[d] * k);
    }
    return i;
  }

  @override
  bool shouldRepaint(_WornRim old) =>
      old.paper != paper || old.radius != radius;
}

/// One lip's wear, read down it: the share of each depth row that is bare, the
/// luminance that bare carries as a fraction between the card's navy and its
/// paper, and the mean length of a mark at that depth.
class _Lip {
  const _Lip(this.cov, this.lit, this.mark);

  final List<double> cov;
  final List<double> lit;
  final List<double> mark;

  /// Mark-starts per plate px that leave exactly `cov[i]` of row i bare, and
  /// their sum: the walk's own stride is one over that.
  double lambdaAt(int i) => cov[i] / mark[i];

  double get rate {
    var s = 0.0;
    for (var i = 0; i < cov.length; i++) {
      s += lambdaAt(i);
    }
    return s;
  }
}
