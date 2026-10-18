import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:bulbvpn/modules/core/log.dart';
import 'package:bulbvpn/modules/core/vpn_server.dart';
import 'package:bulbvpn/modules/core/vpngate_source.dart';

/// Servers the home screen and the connect path share.
///
/// The bundled catalog is returned first so the list is on screen before any
/// network call. A refresh then merges newer rows from our GitHub Actions
/// published JSON — never from www.vpngate.net on-device.
final serversProvider =
    AsyncNotifierProvider<ServerCatalog, List<VpnServer>>(ServerCatalog.new);

class ServerCatalog extends AsyncNotifier<List<VpnServer>> {
  @override
  Future<List<VpnServer>> build() async {
    final bundled = await ServerCatalogLoader.bundled();
    Future<void>.delayed(Duration.zero, refresh);
    return bundled;
  }

  Future<void> refresh() async {
    final fresh = await ServerCatalogLoader.remote();
    if (fresh.isEmpty) return;
    final current = state.valueOrNull ?? const <VpnServer>[];
    state = AsyncData(_merge(current, fresh));
  }
}

List<VpnServer> _merge(List<VpnServer> current, List<VpnServer> fresh) {
  final byIp = <String, VpnServer>{
    for (final server in current)
      if (server.ip.isNotEmpty) server.ip: server,
  };
  for (final server in fresh) {
    if (server.ip.isEmpty) continue;
    byIp[server.ip] = server;
  }
  final merged = byIp.values.toList();
  merged.sort((a, b) => b.score.compareTo(a.score));
  return merged;
}

class ServerCatalogLoader {
  static const _asset = 'data/vpngate.json';

  static Future<List<VpnServer>> bundled() async {
    try {
      final raw = await rootBundle.loadString(_asset);
      final servers = _fromJsonList(raw);
      Log().addLog('[Catalog] Bundled ${servers.length} servers');
      return servers;
    } catch (e) {
      Log().addLog('[Catalog] Bundled catalog failed');
      return const [];
    }
  }

  /// Loads only our Actions-published lists (see [vpnGatePublishedLists]).
  static Future<List<VpnServer>> remote() async {
    final collected = <VpnServer>[];
    for (final url in vpnGatePublishedLists) {
      collected.addAll(await _getJson(url));
      if (collected.isNotEmpty) break;
    }
    if (collected.isEmpty) return const [];
    Log().addLog('[Catalog] Refreshed ${collected.length} servers');
    return _merge(const [], collected);
  }

  static Future<List<VpnServer>> _getJson(String url) async {
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 || response.body.isEmpty) return const [];
      return _fromJsonList(response.body);
    } catch (_) {
      return const [];
    }
  }

  static List<VpnServer> _fromJsonList(String body) {
    final decoded = json.decode(body);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((row) => VpnServer.fromJson(Map<String, dynamic>.from(row)))
        .where((server) => server.ip.isNotEmpty && server.hostName.isNotEmpty)
        .toList();
  }
}
