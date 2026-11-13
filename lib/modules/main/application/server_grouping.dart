import 'package:bulbvpn/modules/core/vpn_server.dart';

import 'server_ping_provider.dart';

class ServerGroup {
  final String countryCode;
  final String countryName;
  final List<VpnServer> servers;
  final ServerPing? bestPing;

  /// Whether this device carried traffic through at least one relay here.
  final bool proven;

  const ServerGroup({
    required this.countryCode,
    required this.countryName,
    required this.servers,
    required this.bestPing,
    this.proven = false,
  });

  int get bestMs => bestPing?.ms ?? 1 << 30;
}

/// Groups relays by country and orders everything by the strongest evidence
/// available, both between countries and inside them.
///
/// [proven] are dial keys this device completed a session through. A proven
/// relay leads its country and the country that holds one leads the list,
/// because the shortest TLS handshake on a censored network is the number that
/// used to win here while the relay behind it carried nothing. Countries
/// without a proof order by measured ping, then alphabetically; relays without
/// either sink to the bottom of their country. Catalog score breaks ties.
List<ServerGroup> groupServersByCountry(
  List<VpnServer> servers,
  Map<String, ServerPing> byIp, {
  Set<String> proven = const <String>{},
}) {
  final byName = <String, List<VpnServer>>{};
  for (final server in servers) {
    final name = server.displayCountry.isEmpty
        ? 'Private relays'
        : server.displayCountry;
    byName.putIfAbsent(name.toLowerCase(), () => []).add(server);
  }

  int rank(String ip) {
    if (proven.contains(ip)) return 0;
    final ping = byIp[ip];
    if (ping == null) return 2;
    return ping.status == PingStatus.ok ? 1 : 2;
  }

  int ms(String ip) {
    final ping = byIp[ip];
    return (ping == null || ping.status != PingStatus.ok) ? 1 << 30 : ping.ms;
  }

  final groups = byName.entries.map((entry) {
    final members = entry.value.toList()
      ..sort((a, b) {
        final byRank = rank(a.ip).compareTo(rank(b.ip));
        if (byRank != 0) return byRank;
        return ms(a.ip).compareTo(ms(b.ip));
      });
    ServerPing? best;
    for (final server in members) {
      if (rank(server.ip) > 1) continue;
      final ping = byIp[server.ip];
      if (ping == null || ping.status != PingStatus.ok) continue;
      if (best == null || ping.ms < best.ms) best = ping;
    }
    final first = members.first;
    return ServerGroup(
      countryCode: first.countryShort.toLowerCase(),
      countryName: first.displayCountry.isEmpty
          ? 'Private relays'
          : first.displayCountry,
      servers: members,
      bestPing: best,
      proven: members.any((s) => proven.contains(s.ip)),
    );
  }).toList();

  groups.sort((a, b) {
    final byProof = (b.proven ? 1 : 0).compareTo(a.proven ? 1 : 0);
    if (byProof != 0) return byProof;
    final byPing = a.bestMs.compareTo(b.bestMs);
    if (byPing != 0) return byPing;
    return a.countryName.toLowerCase().compareTo(b.countryName.toLowerCase());
  });
  return groups;
}
