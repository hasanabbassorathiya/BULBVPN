/// How much the operator behind a relay can see, and who that operator is.
///
/// Only [owned] and [byos] are private: traffic never passes an address the
/// user has not chosen. Community and bootstrap relays exit through a stranger,
/// so every surface that shows them must say "not private".
enum TrustTier { owned, byos, community, bootstrap }

extension TrustTierX on TrustTier {
  bool get isPrivate => this == TrustTier.owned || this == TrustTier.byos;

  String get name => switch (this) {
    TrustTier.owned => 'Owned relay',
    TrustTier.byos => 'Your server',
    TrustTier.community => 'Community relay',
    TrustTier.bootstrap => 'Bootstrap relay',
  };

  String get short => switch (this) {
    TrustTier.owned => 'OWNED',
    TrustTier.byos => 'YOURS',
    TrustTier.community => 'COMMUNITY',
    TrustTier.bootstrap => 'BOOTSTRAP',
  };

  String get disclosure => isPrivate ? name : '$name — not private';
}
