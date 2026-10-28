import 'package:bulbvpn/modules/core/vpn_server.dart';

import 'server_ping_provider.dart';

class ServerGroup {
  final String countryCode;
  final String countryName;
  final List<VpnServer> servers;
  final ServerPing? bestPing;

  const ServerGroup({
    required this.countryCode,
    required this.countryName,
    required this.servers,
    required this.bestPing,
  });

  int get bestMs => bestPing?.ms ?? 1 << 30;
}

/// Groups relays by country, orders each country by its fastest measured
/// relay, and orders the relays inside a country by measured ping.
///
/// Country order is the user-visible promise: the country with the lowest
/// measured ping sits on top. Countries without a successful probe follow
/// alphabetically; servers without a successful probe sit at the bottom of
/// their country. Original order (catalog score) breaks ties.
List<ServerGroup> groupServersByCountry(
  List<VpnServer> servers,
  Map<String, ServerPing> byIp,
) {
  final byName = <String, List<VpnServer>>{};
  for (final server in servers) {
    final name = server.displayCountry.isEmpty
        ? 'Private relays'
        : server.displayCountry;
    byName.putIfAbsent(name.toLowerCase(), () => []).add(server);
  }

  final groups = byName.entries.map((entry) {
    final members = sortByMeasuredPing(entry.value, byIp);
    ServerPing? best;
    for (final server in members) {
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
    );
  }).toList();

  groups.sort((a, b) {
    final byPing = a.bestMs.compareTo(b.bestMs);
    if (byPing != 0) return byPing;
    return a.countryName.toLowerCase().compareTo(b.countryName.toLowerCase());
  });
  return groups;
}
