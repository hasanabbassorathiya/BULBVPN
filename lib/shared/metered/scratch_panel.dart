import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/theme/metered_colors.dart';
import 'package:bulbvpn/shared/metered/metered_layout.dart';
import 'package:bulbvpn/shared/metered/pressable.dart';

/// The scratch panel. What is behind it is the one piece of evidence the user
/// can check without trusting the app: the address traffic actually leaves
/// from. It stays sealed until bytes cross the tunnel.
class ScratchPanel extends StatelessWidget {
  const ScratchPanel({
    super.key,
    required this.open,
    required this.prompt,
    required this.type,
    this.exitIp,
    this.exitPlace,
    this.onOpen,
  });

  final bool open;
  final String prompt;

  /// The card's print sizes, so the reading is printed at the size the plate
  /// prints the rest of the card.
  final MeteredType type;

  final String? exitIp;
  final String? exitPlace;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => open
        ? _TornPanel(
            type: type,
            prompt: prompt,
            exitIp: exitIp,
            exitPlace: exitPlace,
          )
        : _SealedPanel(prompt: prompt, type: type, onTap: onOpen),
  );
}

/// The prompt, printed on the foil. The comp keeps it there after the foil is
/// torn: what the panel asked for does not disappear once it has answered.
class _Prompt extends StatelessWidget {
  const _Prompt({required this.prompt, required this.type});

  final String prompt;
  final MeteredType type;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    final size = type.promptLine;
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    final label = Flexible(
      child: Text(
        prompt,
        maxLines: 3,
        style: AppTextStyles.label(
          color: m.plateInk,
          size: size,
          tracking: 0.0,
        ).copyWith(height: 1.14, fontWeight: FontWeight.w700),
      ),
    );
    final tear = CustomPaint(
      size: Size(size * 0.52, size * 0.62),
      painter: _TrianglePainter(color: m.plateInk, direction: rtl ? TextDirection.rtl : TextDirection.ltr),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: rtl ? [tear, SizedBox(width: size * 0.35), label] : [label, SizedBox(width: size * 0.35), tear],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter({required this.color, required this.direction});

  final Color color;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final pointLeft = direction == TextDirection.rtl;
    canvas.drawPath(
      Path()
        ..moveTo(pointLeft ? size.width : 0, 0)
        ..lineTo(pointLeft ? 0 : size.width, size.height / 2)
        ..lineTo(pointLeft ? size.width : 0, size.height)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color || old.direction != direction;
}

class _SealedPanel extends StatelessWidget {
  const _SealedPanel({required this.prompt, required this.type, this.onTap});

  final String prompt;
  final MeteredType type;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(type.cardWidth * 24 / 1024),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [m.foil, m.foilDark, m.foil],
          stops: const [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Pressable(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: type.cardWidth * 24 / 1024),
          child: _Prompt(prompt: prompt, type: type),
        ),
      ),
    );
  }
}

/// The plate is one photograph of one tear: intact foil on the left, the curled
/// lip in the middle, paper on the right. The prompt stays on the foil and the
/// reading is printed only where the plate shows paper, so the words never sit
/// on the metal.
class _TornPanel extends StatelessWidget {
  const _TornPanel({
    required this.type,
    required this.prompt,
    this.exitIp,
    this.exitPlace,
  });

  final MeteredType type;
  final String prompt;
  final String? exitIp;
  final String? exitPlace;

  /// Measured off the plate: the foil ends and the curl begins here, the paper
  /// shows through the tear from here, and the torn lip of foil closes the
  /// right edge. The prompt never sits on the metal it asks to be scratched.
  static const double _foilLeft = 0.030;
  static const double _foilRight = 0.330;
  static const double _paperLeft = 0.462;
  static const double _paperRight = 0.955;

  /// The photographed plate comes back with its paper at L 225 and its foil a
  /// neutral grey; the card's own paper is L 209 and its foil warm. The ratios
  /// are the measured channel values (222/232, 209/224, 192/208), so the plate
  /// prints in the card's inks instead of beside them.
  static final ColorFilter _toCardInk = ColorFilter.matrix(<double>[
    0.957, 0, 0, 0, 0, //
    0, 0.933, 0, 0, 0, //
    0, 0, 0.923, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    return LayoutBuilder(
      builder: (context, c) {
        final plate = Transform(
          alignment: Alignment.center,
          transform: rtl ? Matrix4.rotationY(math.pi) : Matrix4.identity(),
          child: ColorFiltered(
            colorFilter: _toCardInk,
            child: Image.asset(
              'assets/plates/foil-panel.png',
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
              width: c.maxWidth,
              height: c.maxHeight,
            ),
          ),
        );
        // The plate tears one way: foil first, then paper. In RTL the tear
        // reads back to front, so the foil and paper swap sides and the
        // photograph is flipped so print never lands on the metal.
        final foilLeft = rtl ? c.maxWidth * (1 - _foilRight) : c.maxWidth * _foilLeft;
        final foilRight = rtl ? c.maxWidth * (1 - _foilLeft) : c.maxWidth * (1 - _foilRight);
        final paperLeft = rtl ? c.maxWidth * (1 - _paperRight) : c.maxWidth * _paperLeft;
        final paperRight = rtl ? c.maxWidth * (1 - _paperLeft) : c.maxWidth * (1 - _paperRight);
        return Stack(
          fit: StackFit.expand,
          children: [
            plate,
            Positioned(
              left: foilLeft,
              right: foilRight,
              top: 0,
              bottom: 0,
              child: _Prompt(prompt: prompt, type: type),
            ),
            Positioned(
              left: paperLeft,
              right: paperRight,
              top: 0,
              bottom: 0,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: rtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  FittedLine(
                    'EXIT ${exitIp ?? '—'}',
                    AppTextStyles.monoValue(
                      color: m.plateInk,
                      size: type.exitReading,
                      weight: FontWeight.w700,
                      tracking: 0,
                    ),
                  ),
                  SizedBox(height: type.exitPlace * 0.22),
                  FittedLine(
                    exitPlace ?? 'place unconfirmed',
                    AppTextStyles.monoValue(
                      color: m.plateInk.withValues(alpha: 0.82),
                      size: type.exitPlace,
                      tracking: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
