import 'dart:async';
import 'dart:convert';

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

  final Ref _ref;
  int _generation = 0;

  Future<void> refresh() async {
    final gen = ++_generation;
    state = null;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await http
            .get(Uri.parse('https://www.cloudflare.com/cdn-cgi/trace'))
            .timeout(const Duration(seconds: 6));
        if (res.statusCode == 200 && gen == _generation) {
          final fields = <String, String>{};
          for (final line in const LineSplitter().convert(res.body)) {
            final i = line.indexOf('=');
            if (i > 0) fields[line.substring(0, i)] = line.substring(i + 1);
          }
          final ip = fields['ip'];
          if (ip != null && ip.isNotEmpty) {
            state = ExitIpInfo(ip: ip, loc: fields['loc'] ?? '');
            return;
          }
        }
      } catch (_) {
        // Timeout or network error — fall through to the retry delay.
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (gen != _generation) return;
    }
  }
}

final exitIpProvider = StateNotifierProvider<ExitIpNotifier, ExitIpInfo?>((
  ref,
) {
  return ExitIpNotifier(ref);
});
