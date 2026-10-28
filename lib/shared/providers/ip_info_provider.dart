import 'dart:async';
import 'dart:convert';

import 'package:bulbvpn/modules/core/network_watch.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'connection_state_provider.dart';
import 'exit_ip_provider.dart';

/// Rich geolocation for a public IP, sourced from https://ipwho.is/.
class PublicIpInfo {
  final String ip;
  final String country;
  final String countryCode;
  final String region;
  final String city;
  final String isp;
  final bool success;

  const PublicIpInfo({
    required this.ip,
    required this.country,
    required this.countryCode,
    required this.region,
    required this.city,
    required this.isp,
    required this.success,
  });

  factory PublicIpInfo.fromJson(Map<String, dynamic> json) {
    final ip = (json['ip'] as String?) ?? '';
    if (ip.isEmpty || json['success'] == false) {
      return const PublicIpInfo(
        ip: '',
        country: '',
        countryCode: '',
        region: '',
        city: '',
        isp: '',
        success: false,
      );
    }
    final Map<String, dynamic>? countryJson =
        json['country'] is Map<String, dynamic>
        ? (json['country'] as Map<String, dynamic>)
        : null;
    return PublicIpInfo(
      ip: ip,
      country: (json['country'] is String)
          ? (json['country'] as String)
          : (countryJson?['name'] as String? ?? ''),
      countryCode: (json['country_code'] as String?) ?? '',
      region: (json['region'] as String?) ?? '',
      city: (json['city'] as String?) ?? '',
      isp:
          (json['connection'] is Map<String, dynamic> &&
              (json['connection'] as Map<String, dynamic>)['isp'] is String)
          ? ((json['connection'] as Map<String, dynamic>)['isp'] as String)
          : '',
      success: true,
    );
  }
}

/// The public IP before the tunnel ("BEFORE") and, once the tunnel is up,
/// the exit IP seen from inside it ("AFTER") — both enriched via ipwho.is.
class IpWhoState {
  final PublicIpInfo? before;
  final PublicIpInfo? after;

  const IpWhoState({this.before, this.after});

  IpWhoState copyWith({PublicIpInfo? before, PublicIpInfo? after}) {
    return IpWhoState(
      before: before ?? this.before,
      after: after ?? this.after,
    );
  }
}

class IpWhoNotifier extends StateNotifier<IpWhoState> {
  IpWhoNotifier(this._ref) : super(const IpWhoState()) {
    _ref.listen(connectionStateProvider, (previous, next) {
      final wasUp = previous?.status == ConnectionStatus.connected;
      final isUp = next.status == ConnectionStatus.connected;
      if (isUp && !wasUp) {
        _fetchExit();
      } else if (wasUp && !isUp) {
        state = IpWhoState(before: state.before);
        _fetch(replaceBefore: true);
      }
    });
    // A carrier handover (Wi-Fi ⇄ cellular) changes the BEFORE address while
    // the tunnel is down. Without this the screen kept the previous network's
    // IP until the app was restarted.
    _ref.listen(networkFingerprintProvider, (previous, next) {
      final changed =
          previous?.valueOrNull != null &&
          next.valueOrNull != null &&
          previous!.valueOrNull != next.valueOrNull;
      if (!changed) return;
      if (_ref.read(connectionStateProvider).status ==
          ConnectionStatus.connected) {
        // The tunnel drop handler refreshes once routing is back on the
        // carrier; asking now would trace the VPN exit, not the device.
        return;
      }
      _fetch(replaceBefore: true);
    });
    // Prime the BEFORE ip on app start (no tunnel yet).
    if (_ref.read(connectionStateProvider).status !=
        ConnectionStatus.connected) {
      _fetch(replaceBefore: true);
    }
  }

  static const _url = 'https://ipwho.is/';
  static const _timeout = Duration(seconds: 8);
  // Cloudflare's trace endpoint is not rate-limited and answers quickly from
  // Iranian carriers, where ipwho.is is often the request that never returns.
  // It carries the IP and country code; ipwho.is still supplies the city/ISP
  // when its one-per-minute window allows.
  static const _traceUrls = <String>[
    'https://1.1.1.1/cdn-cgi/trace',
    'https://www.cloudflare.com/cdn-cgi/trace',
  ];
  static const _traceTimeout = Duration(seconds: 6);

  // ipwho.is enforces a per-account rate limit (~1 successful request per
  // minute on the free tier; 429 with "retry after 60 seconds" otherwise).
  // Never call it more often than this, and fall back to the cached lookup.
  static const _minInterval = Duration(seconds: 60);
  DateTime _lastAttemptAt = DateTime.fromMillisecondsSinceEpoch(0);
  PublicIpInfo? _lastGoodInfo;

  final Ref _ref;
  int _generation = 0;

  /// [force] is for the user-initiated refresh: it skips the rate-limit
  /// window instead of waiting up to a minute for the next allowed lookup.
  Future<void> refresh({
    bool before = false,
    bool after = false,
    bool force = false,
  }) {
    return _fetch(replaceAfter: after, replaceBefore: before, force: force);
  }

  void _applyCached({required bool replaceBefore, required int gen}) {
    final cached = _lastGoodInfo;
    if (cached == null || gen != _generation || !replaceBefore) return;
    state = IpWhoState(before: cached, after: state.after);
    debugPrint(
      '[IpWho] rate-limited window; reused cached lookup ${cached.ip}',
    );
  }

  /// Looks up the tunnel exit address. The cached pre-tunnel record is never
  /// copied into AFTER — that made the connected screen repeat the Iranian IP.
  Future<void> _fetchExit({bool force = false}) async {
    final gen = ++_generation;
    String? exitIp;
    for (var i = 0; i < 10; i++) {
      exitIp = _ref.read(exitIpProvider)?.ip;
      final before = state.before?.ip;
      if (exitIp != null && exitIp.isNotEmpty && exitIp != before) break;
      await Future<void>.delayed(const Duration(seconds: 1));
      if (gen != _generation) return;
      exitIp = null;
    }
    final ip = exitIp;
    if (ip == null || gen != _generation) return;

    final since = DateTime.now().difference(_lastAttemptAt);
    if (!force && since < _minInterval) {
      final wait = _minInterval - since;
      debugPrint(
        '[IpWho] AFTER waits ${wait.inSeconds}s so the exit lookup is not the before IP',
      );
      await Future<void>.delayed(wait);
      if (gen != _generation) return;
    }
    _lastAttemptAt = DateTime.now();
    final info = await _attempt(ip: ip);
    if (info != null && info.success && info.ip == ip && gen == _generation) {
      state = state.copyWith(after: info);
      debugPrint(
        '[IpWho] AFTER resolved ${info.ip} (${info.countryCode}/${info.city})',
      );
    }
  }

  Future<bool> _fetch({
    bool replaceBefore = false,
    bool replaceAfter = false,
    bool force = false,
  }) async {
    if (replaceAfter) {
      await _fetchExit(force: force);
      return state.after != null;
    }
    final gen = ++_generation;
    if (replaceBefore) {
      // Trace first: it has no per-minute limit, so a network change always
      // produces the current address instead of the cached one.
      final traced = await _trace();
      if (gen != _generation) return false;
      if (traced != null) {
        state = IpWhoState(before: traced, after: state.after);
        debugPrint(
          '[IpWho] BEFORE traced ${traced.ip} (${traced.countryCode})',
        );
        unawaited(_enrichBefore(traced, gen));
        return true;
      }
    }
    final since = DateTime.now().difference(_lastAttemptAt);
    if (!force && since < _minInterval) {
      _applyCached(replaceBefore: replaceBefore, gen: gen);
      return replaceBefore && _lastGoodInfo != null;
    }
    _lastAttemptAt = DateTime.now();
    for (var attempt = 0; attempt < 2; attempt++) {
      final info = await _attempt();
      if (info != null && gen == _generation) {
        _lastGoodInfo = info;
        state = IpWhoState(
          before: replaceBefore ? info : state.before,
          after: replaceAfter ? info : state.after,
        );
        debugPrint(
          '[IpWho] ${replaceAfter ? 'AFTER' : 'BEFORE'} resolved ${info.ip} (${info.countryCode}/${info.city})',
        );
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (gen != _generation) return false;
    }
    // Both attempts failed (possibly 429) — serve the cached lookup instead of
    // hammering the API; the next state change may retry after the interval.
    if (replaceBefore) {
      _applyCached(replaceBefore: true, gen: gen);
    }
    return false;
  }

  /// Adds city/ISP detail without ever delaying the IP itself. The rate-limit
  /// window belongs to ipwho.is, not to this refresh.
  Future<void> _enrichBefore(PublicIpInfo traced, int gen) async {
    final since = DateTime.now().difference(_lastAttemptAt);
    if (since < _minInterval) return;
    _lastAttemptAt = DateTime.now();
    final info = await _attempt(ip: traced.ip);
    if (info == null || !info.success || info.ip != traced.ip) return;
    if (gen != _generation || state.before?.ip != traced.ip) return;
    _lastGoodInfo = info;
    state = IpWhoState(before: info, after: state.after);
    debugPrint(
      '[IpWho] BEFORE enriched ${info.ip} '
      '(${info.countryCode}/${info.city})',
    );
  }

  Future<PublicIpInfo?> _trace() async {
    for (final url in _traceUrls) {
      try {
        final res = await http.get(Uri.parse(url)).timeout(_traceTimeout);
        if (res.statusCode != 200 || res.body.isEmpty) continue;
        String? ip;
        var loc = '';
        for (final line in const LineSplitter().convert(res.body)) {
          final i = line.indexOf('=');
          if (i <= 0) continue;
          final key = line.substring(0, i);
          if (key == 'ip') ip = line.substring(i + 1).trim();
          if (key == 'loc') loc = line.substring(i + 1).trim();
        }
        if (ip == null || ip.isEmpty) continue;
        return PublicIpInfo(
          ip: ip,
          country: '',
          countryCode: loc,
          region: '',
          city: '',
          isp: '',
          success: true,
        );
      } catch (e) {
        debugPrint('[IpWho] trace failed via $url: $e');
      }
    }
    return null;
  }

  Future<PublicIpInfo?> _attempt({String? ip}) async {
    try {
      final target = (ip == null || ip.isEmpty) ? _url : '$_url$ip';
      final res = await http.get(Uri.parse(target)).timeout(_timeout);
      if (res.statusCode == 429) {
        debugPrint('[IpWho] rate limited (429) — backing off');
        return null;
      }
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        return PublicIpInfo.fromJson(jsonDecode(res.body));
      }
    } catch (e) {
      debugPrint('[IpWho] lookup failed: $e');
    }
    return null;
  }
}

final ipWhoProvider = StateNotifierProvider<IpWhoNotifier, IpWhoState>((ref) {
  return IpWhoNotifier(ref);
});
