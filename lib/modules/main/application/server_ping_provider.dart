import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bulbvpn/modules/core/log.dart';
import 'package:bulbvpn/modules/main/presentation/screens/main_screen.dart';

/// Outcome of a live latency probe for one server. Unlike the `ms` column
/// broadcast by the server list, this is measured by the device itself.
enum PingStatus { pending, ok, timeout }

class ServerPing {
  final PingStatus status;
  final int ms;

  const ServerPing._(this.status, this.ms);

  static const pending = ServerPing._(PingStatus.pending, 0);
  static const timeout = ServerPing._(PingStatus.timeout, 0);

  const ServerPing.ok(int ms) : this._(PingStatus.ok, ms);
}

/// Holds the latest measured ping per server IP. `null` = not yet probed.
class ServerPingState {
  final Map<String, ServerPing> byIp;
  final bool probing;
  const ServerPingState({this.byIp = const {}, this.probing = false});

  ServerPingState copyWith({
    Map<String, ServerPing>? byIp,
    bool? probing,
  }) {
    return ServerPingState(byIp: byIp ?? this.byIp, probing: probing ?? this.probing);
  }
}

/// Probes every server with a real TCP connect to `ip:443` (a single
/// round-trip, ~3s cap each), so the values shown are true device latency —
/// NOT the server-provided `ms`. Results stream in live as each probe lands.
class ServerPingNotifier extends StateNotifier<ServerPingState> {
  ServerPingNotifier() : super(const ServerPingState());

  static const _timeout = Duration(seconds: 3);
  static const _maxConcurrent = 10;

  bool _running = false;

  Future<void> pingAll(List<VpnServer> servers) async {
    if (_running) return;
    _running = true;

    final fresh = <String, ServerPing>{
      for (final s in servers) s.ip: ServerPing.pending,
    };
    state = ServerPingState(byIp: fresh, probing: true);

    try {
      final slots = List<int>.generate(servers.length, (i) => i);
      var next = 0;

      Future<void> worker() async {
        while (true) {
          final i = next++;
          if (i >= slots.length) return;
          final server = servers[i];
          await _probeOne(server);
        }
      }

      final workerCount = _maxConcurrent.clamp(1, servers.isEmpty ? 1 : servers.length);
      final workers = List.generate(workerCount, (_) => worker());
      await Future.wait(workers);

      Log().addLog('[Ping] Measured ${state.byIp.values.where((p) => p.status == PingStatus.ok).length}/${servers.length} servers');
    } finally {
      _running = false;
      state = state.copyWith(probing: false);
    }
  }

  Future<void> _probeOne(VpnServer server) async {
    Socket? socket;
    final stopwatch = Stopwatch()..start();
    try {
      socket = await Socket.connect(server.ip, 443, timeout: _timeout);
      stopwatch.stop();
      final ms = stopwatch.elapsedMilliseconds;
      _publish(server.ip, ServerPing.ok(ms));
    } catch (_) {
      stopwatch.stop();
      _publish(server.ip, ServerPing.timeout);
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  void _publish(String ip, ServerPing ping) {
    final cur = Map<String, ServerPing>.from(state.byIp);
    cur[ip] = ping;
    state = state.copyWith(byIp: cur);
  }

  void clear() {
    if (_running) return;
    state = const ServerPingState();
  }
}

final serverPingProvider =
    StateNotifierProvider<ServerPingNotifier, ServerPingState>((ref) {
  return ServerPingNotifier();
});

/// Sorts a server list by measured ping (ascending), putting unreachable /
/// unprobed servers last. Falls back to stable original order when no live
/// measurement exists for a server so users never see unprobed servers jump
/// to the top with the unreliable `ms` value.
List<VpnServer> sortByMeasuredPing(List<VpnServer> servers, Map<String, ServerPing> byIp) {
  final stable = List<VpnServer>.of(servers);
  stable.sort((a, b) {
    final pa = byIp[a.ip];
    final pb = byIp[b.ip];
    if (pa == null && pb == null) return 0;
    if (pa == null) return 1;
    if (pb == null) return -1;
    final ao = pa.status == PingStatus.ok ? pa.ms : 1 << 30;
    final bo = pb.status == PingStatus.ok ? pb.ms : 1 << 30;
    return ao.compareTo(bo);
  });
  return stable;
}
