import 'package:bulbvpn/modules/core/relay_target.dart';

/// SoftEther listeners VPN Gate relays answer on besides 443.
///
/// Measured against public relays: 443, 992 and 1194 complete a TLS handshake
/// with the hub certificate (CN=opengw.net); 995 closes on a POP3S listener
/// instead. 992/1194 are mail and OpenVPN ports, so a middlebox that filters
/// VPN endpoints by HTTPS port often leaves them alone.
const List<int> softEtherAlternatePorts = <int>[992, 1194];

/// Reachability is a property of a listener, not a host: a relay can be
/// blocked on 443 and still answer on 992, so the probe cache keys both.
String relayReachabilityKey(String dial, int port) => '$dial:$port';

/// Re-dials the leading relays on [ports], at most [perPort] of each.
///
/// Only called once the whole shortlist failed on its primary port: probing
/// alternates first would double the probe cost of every normal connect.
List<RelayTarget> alternatePortTargets(
  List<RelayTarget> targets,
  List<int> ports, {
  int perPort = 6,
}) {
  final existing = <String>{
    for (final target in targets)
      relayReachabilityKey(target.dial, target.port),
  };
  final alternates = <RelayTarget>[];
  for (final port in ports) {
    var taken = 0;
    for (final target in targets) {
      if (taken >= perPort) break;
      if (target.dial.isEmpty) continue;
      final alternate = target.copyWith(port: port);
      if (!existing.add(
        relayReachabilityKey(alternate.dial, alternate.port),
      )) {
        continue;
      }
      alternates.add(alternate);
      taken++;
    }
  }
  return alternates;
}
