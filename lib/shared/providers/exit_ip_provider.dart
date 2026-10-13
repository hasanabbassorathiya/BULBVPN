import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'connection_state_provider.dart';

/// The public (exit) IP address as seen from inside the tunnel, plus the
/// ISO country code of the egress location when the lookup provides it.
class ExitIpInfo {
  final String ip;
  final String loc;

  const ExitIpInfo({required this.ip, this.loc = ''});
}

/// Fetches the exit IP right after the tunnel comes up and clears it as soon
/// as the connection drops. The lookup request itself travels through the
/// tunnel, so the returned address is the VPN egress address.
///
/// Freshly established community tunnels need a moment for routing to settle,
/// so besides the two immediate attempts the lookup makes delayed grace
/// retries. Each retry is abandoned as soon as the connection state changes.
class ExitIpNotifier extends StateNotifier<ExitIpInfo?> {
  ExitIpNotifier(this._ref) : super(null) {
    _ref.listen(connectionStateProvider, (previous, next) {
      final wasUp = previous?.status == ConnectionStatus.connected;
      final isUp = next.status == ConnectionStatus.connected;
      if (isUp && !wasUp) {
        refresh();
      } else if (!isUp) {
        _generation++;
        state = null;
      }
    });
    if (_ref.read(connectionStateProvider).status ==
        ConnectionStatus.connected) {
      refresh();
    }
  }

  static const _lookupUrl = 'https://www.cloudflare.com/cdn-cgi/trace';
  static const _timeout = Duration(seconds: 6);
  static const _retryDelays = <Duration>[
    Duration(seconds: 5),
    Duration(seconds: 15),
  ];

  final Ref _ref;
  int _generation = 0;

  Future<void> refresh() async {
    final gen = ++_generation;
    state = null;

    for (var attempt = 0; attempt < 2; attempt++) {
      if (await _attempt(gen)) return;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (gen != _generation) return;
    }

    // Immediate attempts failed — the tunnel routes may still be settling.
    for (final delay in _retryDelays) {
      await Future<void>.delayed(delay);
      if (gen != _generation || state != null) return;
      if (await _attempt(gen)) return;
    }
    if (gen == _generation) {
      debugPrint('[ExitIp] lookup failed after all retries');
    }
  }

  Future<bool> _attempt(int gen) async {
    try {
      final res = await http.get(Uri.parse(_lookupUrl)).timeout(_timeout);
      if (res.statusCode == 200 && gen == _generation) {
        final fields = <String, String>{};
        for (final line in const LineSplitter().convert(res.body)) {
          final i = line.indexOf('=');
          if (i > 0) fields[line.substring(0, i)] = line.substring(i + 1);
        }
        final ip = fields['ip'];
        if (ip != null && ip.isNotEmpty) {
          state = ExitIpInfo(ip: ip, loc: fields['loc'] ?? '');
          debugPrint('[ExitIp] resolved $ip (${fields['loc'] ?? '??'})');
          return true;
        }
      }
    } catch (_) {
      // Timeout or network error — caller handles the retry schedule.
    }
    return false;
  }
}

final exitIpProvider = StateNotifierProvider<ExitIpNotifier, ExitIpInfo?>((
  ref,
) {
  return ExitIpNotifier(ref);
});
