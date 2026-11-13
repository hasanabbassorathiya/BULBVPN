import 'package:flutter/material.dart';

import 'package:bulbvpn/shared/metered/card_ground.dart';
import 'package:bulbvpn/shared/metered/metered_layout.dart';
import 'package:bulbvpn/shared/metered/tear_strip_nav.dart';

/// The frame every Metered screen is printed on: one card, and the torn strip
/// that selects which of its faces is showing.
///
/// The ground and the nav live here rather than on each screen because the
/// plate says they are the *device*, not the *page* — the card fills the face
/// edge to edge and the tear runs along its foot. A screen that repainted its
/// own ground would restamp the worn rim on every route, and the rim is the one
/// mark on the card that must not repeat: it is the same scratch, the same
/// corner, in the same place, every time you look at the phone.
class MeteredShell extends StatelessWidget {
  const MeteredShell({
    super.key,
    required this.child,
    required this.segments,
    required this.active,
    required this.onSelect,
  });

  final Widget child;
  final List<TearSegment> segments;
  final int active;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return CardGround(
      // The card is the screen, so only the notch and the home indicator cut
      // into it; everything inside these insets is printed by a route.
      insets: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top,
        bottom: MediaQuery.paddingOf(context).bottom,
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final size = Size(c.maxWidth, c.maxHeight);
          final type = MeteredType(size.width);
          final box = MeteredLayout.nav;
          return Stack(
            children: [
              // The route owns the whole face, not the strip's leftover: a
              // screen is printed on the card, and the tear is laid over its
              // foot. Routes pad themselves by `meteredNavExtent`.
              Positioned.fill(child: child),
              Positioned(
                left: box.left * size.width,
                top: box.top * size.height,
                width: box.width * size.width,
                height: box.height * size.height,
                child: TearStripNav(
                  type: type,
                  segments: segments,
                  active: active,
                  onSelect: onSelect,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The four tabs, at the widths the plate cuts them: 323, 214, 225 and 262 of
/// its 1024 across. The torn tab is the widest and SETTINGS earns its length,
/// so the strip is not an even split. The app and the capture harness both read
/// this, so a screenshot can never show a tear the phone does not print.
const List<TearSegment> meteredTabs = [
  TearSegment(label: 'CONNECT', index: 0, flex: 32),
  TearSegment(label: 'RELAYS', index: 1, flex: 21),
  TearSegment(label: 'METER', index: 2, flex: 22),
  TearSegment(label: 'SETTINGS', index: 3, flex: 26),
];

/// The depth of the tear that runs along the foot of the card, as a length a
/// route pads its own print by so nothing it says lands under a torn tab.
double meteredNavExtent(double screenHeight) =>
    screenHeight * (1.0 - MeteredLayout.nav.top);
