import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bulbvpn/modules/core/log.dart';
import 'package:bulbvpn/modules/core/vpn_server.dart';

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

  ServerPingState copyWith({Map<String, ServerPing>? byIp, bool? probing}) {
    return ServerPingState(
      byIp: byIp ?? this.byIp,
      probing: probing ?? this.probing,
    );
  }
}

/// Probes every server with a real TLS handshake to `ip:443` (4s cap each).
/// A plain TCP connect is not evidence of reachability: Iranian ISPs terminate
/// TCP locally, so a relay on another continent "answered" in 4.5 ms while the
/// handshake that SoftEther actually needs took 1.76 s. Timing the TLS
/// handshake keeps the displayed latency honest. Results land live, in bursts
/// of [_publishBatch] so one sweep is not one rebuild per relay.
class ServerPingNotifier extends StateNotifier<ServerPingState> {
  ServerPingNotifier({Future<ServerPing> Function(VpnServer server)? probe})
    : _probe = probe,
      super(const ServerPingState());

  /// Seam for the handshake so a sweep can be driven without a radio.
  final Future<ServerPing> Function(VpnServer server)? _probe;

  static const _timeout = Duration(seconds: 4);
  static const _maxConcurrent = 10;
  static const _staleAfter = Duration(minutes: 2);

  /// How many measured relays one state emission may carry.
  static const _publishBatch = 16;

  bool _running = false;
  bool _rerunRequested = false;
  List<VpnServer> _lastServers = const [];
  DateTime? _finishedAt;

  /// Bumped by [stopProbing] and [invalidate]. A worker that started under an
  /// older generation drops its result instead of publishing a stale value.
  int _generation = 0;

  /// True when the last completed sweep is old enough to be worth repeating
  /// (the server sheet uses this instead of wiping fresh values on every open).
  bool get isStale =>
      _finishedAt == null ||
      DateTime.now().difference(_finishedAt!) > _staleAfter;

  Future<void> ensureFresh(List<VpnServer> servers) async {
    if (servers.isEmpty || _running || !isStale) return;
    await pingAll(servers);
  }

  Future<void> pingAll(List<VpnServer> servers) async {
    _lastServers = servers;
    if (_running) {
      // A carrier switch landed mid-sweep. The timings from the old path are
      // not evidence for the new one, so run again as soon as it finishes.
      _rerunRequested = true;
      return;
    }
    _running = true;
    final generation = _generation;

    try {
      do {
        if (generation != _generation) break;
        _rerunRequested = false;
        await _probeAll(_lastServers, generation);
      } while (_rerunRequested && generation == _generation);
    } finally {
      _running = false;
      if (generation == _generation) {
        _finishedAt = DateTime.now();
        state = state.copyWith(probing: false);
      }
    }
  }

  /// Hands the radio back when a real dial starts. Results already measured
  /// are kept; only the probes that have not started are dropped. Probing 106
  /// relays while the tunnel handshake is in flight delays the thing the user
  /// actually asked for.
  void stopProbing() {
    _rerunRequested = false;
    _flushPending();
    _generation++;
    if (_running) state = state.copyWith(probing: false);
  }

  /// The physical network changed, so every measured latency describes the
  /// old path. Drops the table without starting a new sweep.
  void invalidate() {
    _rerunRequested = false;
    _generation++;
    _pending.clear();
    _finishedAt = null;
    state = const ServerPingState();
  }

  Future<void> _probeAll(List<VpnServer> servers, int generation) async {
    final fresh = <String, ServerPing>{
      for (final s in servers) s.ip: ServerPing.pending,
    };
    state = ServerPingState(byIp: fresh, probing: true);
    _pending.clear();

    final slots = List<int>.generate(servers.length, (i) => i);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        if (generation != _generation) return;
        final i = next++;
        if (i >= slots.length) return;
        final server = servers[i];
        await _probeOne(server, generation);
      }
    }

    final workerCount = _maxConcurrent.clamp(
      1,
      servers.isEmpty ? 1 : servers.length,
    );
    final workers = List.generate(workerCount, (_) => worker());
    await Future.wait(workers);

    if (generation == _generation) {
      _flushPending();
      Log().addLog(
        '[Ping] Measured ${state.byIp.values.where((p) => p.status == PingStatus.ok).length}/${servers.length} servers',
      );
    }
  }

  Future<void> _probeOne(VpnServer server, int generation) async {
    final probe = _probe;
    if (probe != null) {
      _publish(server.ip, await probe(server), generation);
      return;
    }
    Socket? socket;
    final stopwatch = Stopwatch()..start();
    try {
      final attempt = SecureSocket.connect(
        server.ip,
        443,
        timeout: _timeout,
        // VPN Gate relays use self-signed certificates; the probe only times
        // the handshake and never sends data.
        onBadCertificate: (_) => true,
      );
      // The dart:io timeout only covers the TCP connect. Carriers that accept
      // the handshake and then stall TLS leave this future pending for
      // minutes, which stalls the whole sweep, so cap the handshake too.
      unawaited(
        attempt
            .then((s) {
              try {
                s.destroy();
              } catch (_) {}
            })
            .catchError((_) {}),
      );
      socket = await attempt.timeout(_timeout);
      stopwatch.stop();
      final ms = stopwatch.elapsedMilliseconds;
      _publish(server.ip, ServerPing.ok(ms), generation);
    } catch (_) {
      stopwatch.stop();
      _publish(server.ip, ServerPing.timeout, generation);
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  /// Probe results waiting for the next state emission.
  ///
  /// The home screen and the server sheet both watch this state, and the
  /// sheet re-groups all 106 relays by country on every change. Publishing per
  /// relay measured 109 emissions for one sweep (test/server_ping_batch_test)
  /// — 109 full rebuilds while 10 TLS handshakes were still running.
  final Map<String, ServerPing> _pending = <String, ServerPing>{};

  void _publish(String ip, ServerPing ping, int generation) {
    if (generation != _generation) return;
    _pending[ip] = ping;
    if (_pending.length >= _publishBatch) _flushPending();
  }

  void _flushPending() {
    if (_pending.isEmpty) return;
    final cur = Map<String, ServerPing>.from(state.byIp)..addAll(_pending);
    _pending.clear();
    state = state.copyWith(byIp: cur);
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
List<VpnServer> sortByMeasuredPing(
  List<VpnServer> servers,
  Map<String, ServerPing> byIp,
) {
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
