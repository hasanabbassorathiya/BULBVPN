import 'package:bulbvpn/modules/core/trust_tier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only owned and your-server relays count as private', () {
    expect(TrustTier.owned.isPrivate, isTrue);
    expect(TrustTier.byos.isPrivate, isTrue);
    expect(TrustTier.community.isPrivate, isFalse);
    expect(TrustTier.bootstrap.isPrivate, isFalse);
  });

  test('public relays always disclose "not private"', () {
    for (final tier in [TrustTier.community, TrustTier.bootstrap]) {
      expect(tier.disclosure, endsWith('not private'));
      expect(tier.disclosure, contains(tier.name));
    }
    for (final tier in [TrustTier.owned, TrustTier.byos]) {
      expect(tier.disclosure, tier.name);
      expect(tier.disclosure, isNot(contains('not private')));
    }
  });
}
