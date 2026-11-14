import 'package:flutter/material.dart';

import 'package:bulbvpn/core/theme/simple_colors.dart';

/// The surface card that holds one face of the app.
///
/// Dark mode only: surface print on near-black ground, with a hairline border
/// and rounded corners. The sheet itself rounds its own corners; this is the
/// card the face is printed on.
class SimpleCard extends StatelessWidget {
  const SimpleCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = context.simple;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: s.surface,
        border: Border.all(color: s.hairline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}
