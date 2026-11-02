import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_vless/flutter_vless.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bulbvpn/modules/core/log.dart';
import 'package:bulbvpn/modules/core/reality/reality_relay.dart';

/// The VLESS+REALITY tunnel on Android.
///
/// One engine, one native session. [start] dials a single relay and either
/// reports CONNECTED within [connectTimeout] or tears the native service down,
/// so a dead relay can never leave the orb on "Connecting" behind a TUN that
/// already captures traffic. The native service publishes a status every
/// second; those snapshots are the only source of byte counters and of the
/// live/not-live signal used by the UI.
///
/// A native CONNECTED is necessary but not sufficient: on some networks the
/// TLS handshake completes and then the stream is throttled to a trickle.
/// [probeTunnel] pushes a real transfer through the installed TUN, so that
/// state is never adopted as a working session.
class RealityEngine {
  RealityEngine._();

  static final RealityEngine instance = RealityEngine._();

  /// DNS-free tiny request through the TUN. It also provides the RTT shown to
  /// the user; an IP literal keeps it independent of the tunnel's DNS.
  static const traceProbeUrl = 'https://1.1.1.1/cdn-cgi/trace';

  /// Second liveness target. The IP literal above is fast but occasionally
  /// filtered; either tiny request succeeding proves the path is alive.
  static const traceProbeFallbackUrl =
      'https://www.cloudflare.com/cdn-cgi/trace';

  /// Bulk transfer through the TUN. A relay that passes the handshake and
  /// then carries a burst before freezing is the common Iranian failure: the
  /// probe must therefore cross a volume that real browsing crosses. A
  /// Wikipedia article arrives over one HTTP/2 flow, so per-flow throughput is
  /// what the threshold has to reflect.
  static const bulkProbeUrl =
      'https://speed.cloudflare.com/__down?bytes=524288';

  static const connectTimeout = Duration(seconds: 12);
  static const tunnelProbeTimeout = Duration(seconds: 10);
  static const _traceProbeTimeout = Duration(seconds: 6);
  static const _dnsTimeout = Duration(seconds: 4);

  /// 128 KiB in ten seconds is ~13 KB/s: the floor at which a page load
  /// finishes instead of hanging halfway through its largest resource.
  static const _tunnelProbeMinBytes = 128 * 1024;
  static const _teardownTimeout = Duration(seconds: 3);

  final _log = Log();
  final _events = StreamController<VlessStatus>.broadcast();

  Future<FlutterVless>? _clientFuture;
  bool _permissionRequested = false;

  DateTime? _lastEventAt;
  VlessStatus? _lastStatus;
  bool _sessionActive = false;
  bool _nativeMayExist = false;
  String? _activeRelayId;
  RealityRelay? _activeRelay;

  /// Raw native security: REALITY is the only engine supplied by a plugin; on
  /// Apple the packet-tunnel extension target does not exist in this build.
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  bool get isSessionActive => _sessionActive;

  String? get activeRelayId => _activeRelayId;

  /// The relay that owns the current (or most recent) native session. Kept
  /// after a disconnect so a drop can be attributed to the relay that caused
  /// it and the next dial can prefer a different one.
  RealityRelay? get activeRelay => _activeRelay;

  VlessStatus? get lastStatus => _lastStatus;

  DateTime? get lastEventAt => _lastEventAt;

  /// Status snapshots from the native service. One per second while connected.
  Stream<VlessStatus> get statuses => _events.stream;

  void _onStatus(VlessStatus status) {
    _lastStatus = status;
    _lastEventAt = DateTime.now();
    if (status.connectionState == VlessConnectionState.disconnected) {
      _sessionActive = false;
      _activeRelayId = null;
    }
    if (!_events.isClosed) _events.add(status);
  }

  Future<FlutterVless> _ensureClient() async {
    final pending = _clientFuture;
    if (pending != null) return pending;
    final future = _createClient();
    _clientFuture = future;
    try {
      return await future;
    } catch (_) {
      if (identical(_clientFuture, future)) _clientFuture = null;
      rethrow;
    }
  }

  Future<FlutterVless> _createClient() async {
    final client = FlutterVless(onStatusChanged: _onStatus);
    await client.initializeVless();
    return client;
  }

  /// Requests the notification permission and the system VPN consent once.
  ///
  /// The OpenVPN path already asks for VPN consent on every connect, and the
  /// consent is app-wide, so this normally resolves without a dialog. Asking
  /// once per process keeps a denial from re-prompting on every attempt.
  Future<bool> ensurePermission() async {
    if (_permissionRequested) return true;
    final client = await _ensureClient();
    try {
      final granted = await client.requestPermission();
      _permissionRequested = true;
      return granted;
    } catch (e) {
      _log.addLog('[RealityEngine] permission request failed: $e');
      return false;
    }
  }

  /// Dials [relay]. Returns null on success, or a short failure reason.
  ///
  /// [blockedApps] is the split-tunnel deny list. The plugin cannot express an
  /// allow list, so callers must skip REALITY for that mode.
  Future<String?> start(
    RealityRelay relay, {
    List<String>? blockedApps,
  }) async {
    if (!isSupported) return 'unsupported';
    final client = await _ensureClient();
    await stop();

    final config = relay.toXrayConfigJson();
    var accepted = false;
    final completer = Completer<VlessConnectionState>();
    final sub = _events.stream.listen((status) {
      final state = status.connectionState;
      if (state == VlessConnectionState.connected) {
        if (!completer.isCompleted) completer.complete(state);
      } else if (state == VlessConnectionState.disconnected && accepted) {
        if (!completer.isCompleted) completer.complete(state);
      }
    });

    final watch = Stopwatch()..start();
    try {
      _nativeMayExist = true;
      await client.startVless(
        remark: 'BULBVPN · ${relay.displayName}',
        config: config,
        blockedApps: (blockedApps?.isEmpty ?? true) ? null : blockedApps,
        androidDnsPolicy: AndroidDnsPolicy.proxy,
        androidDnsProxyOutboundTag: 'proxy',
        notificationDisconnectButtonName: 'Disconnect',
      );
      accepted = true;
    } catch (e) {
      await sub.cancel();
      await stop();
      _log.addLog('[RealityEngine] start rejected: $e');
      return _reason(e);
    }

    VlessConnectionState? state;
    try {
      state = await completer.future.timeout(connectTimeout);
    } on TimeoutException {
      state = null;
    } finally {
      await sub.cancel();
    }
    watch.stop();

    if (state != VlessConnectionState.connected) {
      await stop();
      _log.addLog(
        '[RealityEngine] ${relay.countryCode}/${relay.host} did not connect '
        '(${state?.name ?? 'timeout'} after ${watch.elapsed.inMilliseconds}ms)',
      );
      return state == null ? 'timeout' : state.name;
    }

    _sessionActive = true;
    _activeRelayId = relay.id;
    _activeRelay = relay;
    _log.addLog(
      '[RealityEngine] CONNECTED ${relay.countryCode}/${relay.endpoint} '
      'in ${watch.elapsed.inMilliseconds}ms',
    );
    return null;
  }

  /// Pushes real traffic through the installed TUN.
  ///
  /// `null` means no session is live, so there is nothing to judge. A
  /// non-null result with [TunnelProbe.ok] false means the service is up but
  /// the tunnel could not carry a bulk transfer: the exact signature of a
  /// relay whose IP path is throttled after the handshake. Callers must
  /// treat that as a failed dial, not as "connected".
  ///
  /// [bulk] false sends only the tiny trace request, for a cheap liveness
  /// check where the question is "is the tunnel still reachable", not "how
  /// much can it move".
  Future<TunnelProbe?> probeTunnel({
    bool bulk = true,
    Duration timeout = tunnelProbeTimeout,
  }) async {
    if (!_sessionActive) return null;
    final traces = [
      _fetch(traceProbeUrl, minBytes: 64, timeout: _traceProbeTimeout),
      _fetch(
        traceProbeFallbackUrl,
        minBytes: 64,
        timeout: _traceProbeTimeout,
      ),
    ];
    if (!bulk) {
      final trace = _preferTrace(await Future.wait(traces));
      return _fromTrace(trace, trace);
    }
    final results = await Future.wait([
      ...traces,
      _fetch(bulkProbeUrl, minBytes: _tunnelProbeMinBytes, timeout: timeout),
    ]);
    final trace = _preferTrace(results.sublist(0, 2));
    return _fromTrace(trace, results[2]);
  }

  static TunnelProbe _fromTrace(_Probe trace, _Probe transfer) {
    return TunnelProbe(
      ok: transfer.ok,
      traceMs: trace.ok ? trace.ms : 0,
      bytes: transfer.bytes,
      elapsedMs: transfer.ms,
      exitIp: trace.exitIp,
      exitCountry: trace.exitCountry,
      error: transfer.ok ? null : transfer.error,
    );
  }

  /// Prefers a successful trace (fast IP literal) and falls back to the one
  /// that moved the most bytes so callers still get a truthful failure.
  static _Probe _preferTrace(List<_Probe> probes) {
    for (final probe in probes) {
      if (probe.ok) return probe;
    }
    return probes.isEmpty
        ? const _Probe(ok: false, ms: 0, bytes: 0, error: 'no probe')
        : probes.reduce((a, b) => a.bytes >= b.bytes ? a : b);
  }

  Future<_Probe> _fetch(
    String url, {
    required int minBytes,
    required Duration timeout,
  }) async {
    final watch = Stopwatch()..start();
    final progress = _Progress();
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..autoUncompress = false;
    late final _Probe result;
    try {
      result = await _attempt(
        client,
        url,
        minBytes: minBytes,
        watch: watch,
        progress: progress,
      ).timeout(
        timeout,
        onTimeout: () => _Probe(
          ok: false,
          ms: watch.elapsedMilliseconds,
          bytes: progress.bytes,
          error: 'timeout after ${timeout.inSeconds}s',
        ),
      );
    } catch (error) {
      result = _Probe(
        ok: false,
        ms: watch.elapsedMilliseconds,
        bytes: progress.bytes,
        error: _shortError(error),
      );
    } finally {
      client.close(force: true);
    }
    if (!result.ok) {
      _log.addLog(
        '[RealityEngine] probe ${Uri.parse(url).host} failed in '
        '${result.ms}ms${result.dnsMs > 0 ? ' (dns ${result.dnsMs}ms)' : ''}: '
        '${result.error}',
      );
    }
    return result;
  }

  Future<_Probe> _attempt(
    HttpClient client,
    String url, {
    required int minBytes,
    required Stopwatch watch,
    required _Progress progress,
  }) async {
    final uri = Uri.parse(url);
    var dnsMs = 0;
    // Resolve first so a failure is attributed to DNS instead of being
    // reported as an anonymous stall of the whole request.
    if (InternetAddress.tryParse(uri.host) == null) {
      final dns = Stopwatch()..start();
      try {
        await InternetAddress.lookup(uri.host).timeout(_dnsTimeout);
      } catch (error) {
        return _Probe(
          ok: false,
          ms: watch.elapsedMilliseconds,
          bytes: 0,
          dnsMs: dns.elapsedMilliseconds,
          error: 'dns ${_shortError(error)}',
        );
      }
      dnsMs = dns.elapsedMilliseconds;
    }
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 400) {
      return _Probe(
        ok: false,
        ms: watch.elapsedMilliseconds,
        bytes: 0,
        dnsMs: dnsMs,
        error: 'http ${response.statusCode}',
      );
    }
    final drained = await _drain(response, minBytes, progress);
    watch.stop();
    final exit = _traceExit(drained.head);
    return _Probe(
      ok: drained.bytes >= minBytes,
      ms: watch.elapsedMilliseconds,
      bytes: drained.bytes,
      dnsMs: dnsMs,
      exitIp: exit.$1,
      exitCountry: exit.$2,
      error: drained.bytes >= minBytes ? null : 'only ${drained.bytes} bytes',
    );
  }

  /// Reads at most [limit] bytes, so a healthy fast path does not download the
  /// whole body and a stalled one is cut off by the caller's timeout. The head
  /// is kept because the trace body names the exit address traffic used.
  Future<({int bytes, String head})> _drain(
    HttpClientResponse response,
    int limit,
    _Progress progress,
  ) async {
    final head = BytesBuilder(copy: false);
    await for (final chunk in response) {
      progress.bytes += chunk.length;
      if (head.length < 512) head.add(chunk);
      if (progress.bytes >= limit) break;
    }
    final text = utf8.decode(head.takeBytes(), allowMalformed: true);
    return (bytes: progress.bytes, head: text);
  }

  static (String?, String?) _traceExit(String body) {
    String? ip;
    String? country;
    for (final line in const LineSplitter().convert(body)) {
      if (line.startsWith('ip=')) {
        ip = line.substring(3);
      } else if (line.startsWith('loc=')) {
        country = line.substring(4);
      }
    }
    return (ip, country);
  }

  static String _shortError(Object error) {
    final text = error is SocketException
        ? '${error.message}${error.osError == null ? '' : ' (${error.osError})'}'
        : error.toString();
    return text.length > 140 ? '${text.substring(0, 140)}…' : text;
  }

  /// Stops the native session and waits until the service releases the TUN.
  ///
  /// A new dial must never race the previous VpnService teardown: Android
  /// keeps the old interface until the service finishes, and a second
  /// `establish()` would fail.
  /// Adopts a tunnel the daemon kept after this process restarted.
  ///
  /// `XrayVPNService` runs in `:RunSoLibXrayDaemon` and outlives the UI
  /// process, so a relaunched app can face a working tunnel it never started
  /// in this lifetime. Marking it live is what lets Disconnect stop it and
  /// lets the liveness poller judge it by real bytes instead of by absence.
  Future<void> adoptDaemonSession({RealityRelay? relay}) async {
    _sessionActive = true;
    _nativeMayExist = true;
    _activeRelayId = relay?.id;
    _activeRelay = relay;
    _lastEventAt = null;
    _log.addLog(
      '[RealityEngine] Adopted daemon-held tunnel ${relay?.endpoint ?? 'relay unknown'}',
    );
    try {
      // stopVless() needs a client, and the native status push resumes once
      // the channel exists.
      await _ensureClient();
    } catch (e) {
      _log.addLog('[RealityEngine] adopt attach failed: $e');
    }
  }

  Future<void> stop() async {
    _sessionActive = false;
    _activeRelayId = null;
    if (!_nativeMayExist) return;
    _nativeMayExist = false;
    final teardown = Completer<void>();
    late final StreamSubscription<VlessStatus> sub;
    sub = _events.stream.listen((status) {
      if (status.connectionState == VlessConnectionState.disconnected &&
          !teardown.isCompleted) {
        teardown.complete();
      }
    });
    final FlutterVless client;
    try {
      // A process that adopted the daemon's tunnel never ran start() here, so
      // the channel has to be created on demand; without it an orphan tunnel
      // could be described but never stopped.
      client = await _ensureClient();
    } catch (e) {
      _log.addLog('[RealityEngine] stop could not attach: $e');
      await sub.cancel();
      return;
    }
    try {
      await client.stopVless();
    } catch (e) {
      _log.addLog('[RealityEngine] stop failed: $e');
      await sub.cancel();
      return;
    }
    try {
      await teardown.future.timeout(_teardownTimeout);
    } on TimeoutException {
      // No disconnect echo (the service may already have been gone). A short
      // settle still lets the OS release the interface before the next dial.
      await Future<void>.delayed(const Duration(milliseconds: 400));
    } finally {
      await sub.cancel();
    }
  }

  static String _reason(Object error) {
    if (error is PlatformException) return '${error.code}: ${error.message}';
    return error.toString();
  }
}

/// What a real transfer through the installed TUN measured.
class TunnelProbe {
  const TunnelProbe({
    required this.ok,
    required this.traceMs,
    required this.bytes,
    required this.elapsedMs,
    this.exitIp,
    this.exitCountry,
    this.error,
  });

  /// The bulk transfer completed. A session that fails this cannot be sold to
  /// the user as connected, even though the native service says CONNECTED.
  final bool ok;

  /// Round trip of the DNS-free tiny request, or 0 when it failed.
  final int traceMs;

  /// Bytes actually received by the bulk transfer.
  final int bytes;

  /// Time spent on the bulk transfer.
  final int elapsedMs;

  /// Public address reported by the trace body. When it matches the relay's
  /// country, the bytes demonstrably left through that relay.
  final String? exitIp;
  final String? exitCountry;

  /// Why the transfer failed, when it did.
  final String? error;

  int get rttMs => traceMs > 0 ? traceMs : elapsedMs;
}

/// Bytes received so far, readable even when the request is cut off by the
/// timeout: a relay that stalls halfway must still report what it moved.
class _Progress {
  int bytes = 0;
}

/// One probe attempt, including the stage that failed.
class _Probe {
  const _Probe({
    required this.ok,
    required this.ms,
    required this.bytes,
    this.dnsMs = 0,
    this.exitIp,
    this.exitCountry,
    this.error,
  });

  final bool ok;
  final int ms;
  final int bytes;
  final int dnsMs;
  final String? exitIp;
  final String? exitCountry;
  final String? error;
}

/// Whether the censorship-resistant engine may be used, and which relay the
/// user picked. Both are opt-in: community relays are not private, so nothing
/// here switches them on.
class RealitySettings {
  const RealitySettings({this.enabled = false, this.selectedId});

  final bool enabled;
  final String? selectedId;

  bool get usable => enabled || (selectedId?.isNotEmpty ?? false);

  RealitySettings copyWith({
    bool? enabled,
    String? selectedId,
    bool clearSelection = false,
  }) {
    return RealitySettings(
      enabled: enabled ?? this.enabled,
      selectedId: clearSelection ? null : (selectedId ?? this.selectedId),
    );
  }

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        if (selectedId != null) 'selected': selectedId,
      };

  static RealitySettings fromJson(Map<String, Object?> json) {
    final selected = json['selected']?.toString();
    return RealitySettings(
      enabled: json['enabled'] == true,
      selectedId: (selected == null || selected.isEmpty) ? null : selected,
    );
  }
}

class RealitySettingsStore {
  RealitySettingsStore._();

  static const _key = 'bulb_reality_v1';

  static RealitySettings? _cached;

  static RealitySettings? get cached => _cached;

  static Future<RealitySettings> load() async {
    final memo = _cached;
    if (memo != null) return memo;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      final settings = raw == null || raw.isEmpty
          ? const RealitySettings()
          : RealitySettings.fromJson(
              jsonDecode(raw) as Map<String, Object?>,
            );
      _cached = settings;
      return settings;
    } catch (_) {
      return const RealitySettings();
    }
  }

  static Future<void> save(RealitySettings settings) async {
    _cached = settings;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(settings.toJson()));
    } catch (_) {}
  }

  @visibleForTesting
  static void resetCache() => _cached = null;
}

class RealitySettingsNotifier extends StateNotifier<RealitySettings> {
  RealitySettingsNotifier()
      : super(RealitySettingsStore.cached ?? const RealitySettings()) {
    _hydrate();
  }

  Future<void> _hydrate() async {
    final loaded = await RealitySettingsStore.load();
    if (!mounted || loaded == state) return;
    state = loaded;
  }

  Future<void> setEnabled(bool enabled) {
    if (state.enabled == enabled) return Future.value();
    return _apply(state.copyWith(enabled: enabled));
  }

  Future<void> select(String? id) {
    final next = id == null
        ? state.copyWith(clearSelection: true)
        : state.copyWith(selectedId: id);
    if (next.enabled == state.enabled && next.selectedId == state.selectedId) {
      return Future.value();
    }
    return _apply(next);
  }

  Future<void> _apply(RealitySettings settings) async {
    state = settings;
    await RealitySettingsStore.save(settings);
  }
}

final realitySettingsProvider =
    StateNotifierProvider<RealitySettingsNotifier, RealitySettings>(
  (ref) => RealitySettingsNotifier(),
);

/// Whether this build can run the REALITY transport at all. A provider so the
/// sheet's opt-in UI can be exercised off-device.
final realitySupportedProvider = Provider<bool>(
  (ref) => RealityEngine.instance.isSupported,
);

final realityRelaysProvider = FutureProvider<List<RealityRelay>>((ref) {
  return RealityCatalog.load();
});
