/// A responsive type scale for the simple VPN app.
///
/// Sizes scale with card width relative to a 375-wide reference so a sheet
/// reads the same on a fold-out tablet as it does on a phone. Named sizes map
/// to roles, not fixed pixels, so the whole scale moves together.
class SimpleType {
  const SimpleType(this.maxWidth);

  final double maxWidth;

  double px(double p) => p * (maxWidth / 375).clamp(0.85, 1.15);

  /// Section title attached to a nav bar — large, bold, scale-down fitted.
  double get navLabelAttached => px(16);

  /// A row that carries a measure and a claim side by side.
  double get tableRowMixed => px(13);

  /// A claim about what something is — the row's second line.
  double get claim => px(12);

  /// A kicker — smallest print, beneath a claim.
  double get kicker => px(10);

  /// Letter spacing applied to claim-sized print.
  double get claimLeft => 0;

  /// An exit-place detail in an empty-state message.
  double get exitPlace => px(13);
}
