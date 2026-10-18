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
/// network call. A refresh then merges newer rows without clearing the list.
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
      Log().addLog('[Catalog] Bundled catalog failed: $e');
      return const [];
    }
  }

  static Future<List<VpnServer>> remote() async {
    final collected = <VpnServer>[];
    for (final url in vpnGatePublishedLists) {
      collected.addAll(await _getJson(url));
    }
    collected.addAll(await _officialCsv());
    collected.addAll(
      await _getJson(
        'https://raw.githubusercontent.com/alihusains/apigate/main/response.json',
      ),
    );
    if (collected.isEmpty) return const [];
    return _merge(const [], collected);
  }

  static Future<List<VpnServer>> _getJson(String url) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 || response.body.isEmpty) return const [];
      final servers = _fromJsonList(response.body);
      Log().addLog('[Catalog] ${servers.length} servers from $url');
      return servers;
    } catch (e) {
      Log().addLog('[Catalog] $url failed: $e');
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

  static Future<List<VpnServer>> _officialCsv() async {
    const urls = <String>[
      'https://www.vpngate.net/api/iphone/',
      'http://www.vpngate.net/api/iphone/',
    ];
    for (final url in urls) {
      try {
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
        if (response.statusCode != 200 || !response.body.contains('OpenVPN_ConfigData_Base64')) {
          continue;
        }
        final servers = <VpnServer>[];
        for (final line in response.body.split('\n')) {
          final server = _fromCsvLine(line);
          if (server != null) servers.add(server);
        }
        if (servers.isNotEmpty) {
          Log().addLog('[Catalog] ${servers.length} servers from official CSV');
          return servers;
        }
      } catch (e) {
        Log().addLog('[Catalog] Official CSV failed: $e');
      }
    }
    return const [];
  }

  static VpnServer? _fromCsvLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('*') || trimmed.startsWith('#')) {
      return null;
    }
    final parts = trimmed.split(',');
    if (parts.length < 15) return null;
    final b64 = parts.last.trim();
    if (b64.isEmpty) return null;
    return VpnServer(
      hostName: parts[0].trim(),
      ip: parts[1].trim(),
      countryLong: parts[5].trim(),
      countryShort: parts[6].trim(),
      score: int.tryParse(parts[2].trim()) ?? 0,
      ping: int.tryParse(parts[3].trim()) ?? 0,
      speed: int.tryParse(parts[4].trim()) ?? 0,
      numVpnSessions: int.tryParse(parts[7].trim()) ?? 0,
      uptime: int.tryParse(parts[8].trim()) ?? 0,
      openVpnConfigBase64: b64,
    );
  }
}
