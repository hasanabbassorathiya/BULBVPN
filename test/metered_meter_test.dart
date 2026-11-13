import 'package:flutter_test/flutter_test.dart';

import 'package:bulbvpn/modules/core/trust_tier.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/home_composition.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/metered_card.dart';
import 'package:bulbvpn/shared/air/air_phase.dart';
import 'package:bulbvpn/shared/widgets/staggered_in.dart'
    show formatMbps, formatRate, formatVolume;

/// The credit window is four bays that print the sampler's own labels, so the
/// unit under each figure has to be the one that figure was divided by. A card
/// that fixes Mbps under a Kbps reading overstates the tunnel by three orders
/// of magnitude in the one number the user reads to decide whether it works.
HomeViewState state({
  required String trafficLabel,
  required String downLabel,
  required String upLabel,
  bool live = true,
  Duration? proofAge = const Duration(milliseconds: 8120),
}) {
  return HomeViewState(
    phase: AirPhase.connected,
    statusTitle: 'Connected',
    statusDetail: 'traffic confirmed · Japan',
    networkLabel: 'Wi-Fi · HomeNet',
    clockLabel: '00:04:12',
    pingLabel: '42',
    protocolLabel: 'SoftEther',
    relayLabel: 'Japan',
    exitIp: '203.0.113.7',
    exitLocation: 'Tokyo · Example ISP',
    flagCode: 'jp',
    trustTier: TrustTier.bootstrap,
    proven: true,
    trafficLabel: trafficLabel,
    downLabel: downLabel,
    upLabel: upLabel,
    live: live,
    proofAge: proofAge,
  );
}

void main() {
  group('the credit window takes its units from the readings', () {
    test('a live session prints one unit per bay, in the band each came in', () {
      final cells = meteredCellsFor(
        state(
          trafficLabel: '14.2 MiB',
          downLabel: '1.2 Mbps',
          upLabel: '240 Kbps',
        ),
      );

      expect(cells.map((c) => c.rubric), ['TRAFFIC', '', 'DOWN', 'UP']);
      expect(cells.map((c) => c.value), ['14.2', '8.12', '1.2', '240']);
      expect(cells.map((c) => c.unit), ['MiB', 's', 'Mbps', 'Kbps']);
    });

    test('a trickle keeps its own band instead of the card\'s', () {
      // 688 Kbps is a real Iranian-mobile-data reading, and the DOWN bay was
      // born printed Mbps: this is the exact defect the rule exists to stop.
      final cells = meteredCellsFor(
        state(
          trafficLabel: '64 KiB',
          downLabel: '688 Kbps',
          upLabel: '12 Kbps',
        ),
      );

      expect(cells[2].value, '688');
      expect(cells[2].unit, 'Kbps');
      expect(cells[3].unit, 'Kbps');
    });

    test('a closed session names a unit under an empty wheel', () {
      // Nothing crossed, so the wheels are still and the traffic figure is
      // zero — but the inch is not missing: '0 B' is the honest volume and a
      // blank rate keeps the band the card would measure it in.
      final cells = meteredCellsFor(
        state(
          trafficLabel: '0 B',
          downLabel: '—',
          upLabel: '—',
          live: false,
        ),
      );

      expect(cells[0].value, '0');
      expect(cells[0].unit, 'B');
      expect(cells[1].value, '—');
      expect(cells[2].value, '—');
      expect(cells[2].unit, 'Mbps');
      // The age of the last byte is a reading the card may not invent.
      expect(cells[1].unit, 's');
    });

    test('the window never prints an SI prefix on a binary divisor', () {
      // The four units the sampler can produce, against the four the card may
      // print: KB and MB are 1024-divided figures wearing 1000 prefixes.
      const forbidden = ['KB', 'MB', 'GB', 'KB/s', 'MB/s'];
      for (final label in [
        '0 B',
        '2 KiB',
        '14.2 MiB',
        '3.00 GiB',
      ]) {
        final cells = meteredCellsFor(
          state(trafficLabel: label, downLabel: '2.6 Mbps', upLabel: '84 Kbps'),
        );
        expect(forbidden, isNot(contains(cells[0].unit)));
      }
    });
  });

  group('a figure names the division it used', () {
    test('cumulative volume divides by 1024 and says so', () {
      expect(formatVolume(0), '0 B');
      expect(formatVolume(1536), '2 KiB');
      expect(formatVolume(1048576 * 14.2), '14.2 MiB');
      expect(formatVolume(1073741824 * 3), '3.00 GiB');
    });

    test('a link rate is decimal bits', () {
      // The unit a user's speed test and their provider's plan both use, so it
      // is the unit the hero answers in.
      expect(formatMbps(327680), '2.6 Mbps');
      expect(formatMbps(86016), '688 Kbps');
      expect(formatMbps(0), '0 Kbps');
    });

    test('probe throughput stays in bytes because probes compare in bytes', () {
      expect(formatRate(899804), '879 KB/s');
    });
  });
}
