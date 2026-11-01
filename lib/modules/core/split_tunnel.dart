import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which apps' traffic enters the tunnel.
enum TunnelMode {
  /// Every app uses the tunnel (the historical behaviour).
  all,

  /// Everything except the selected apps uses the tunnel.
  bypass,

  /// Only the selected apps use the tunnel; everything else stays on the
  /// carrier.
  allow;

  static TunnelMode fromName(String? name) => values.firstWhere(
        (mode) => mode.name == name,
        orElse: () => TunnelMode.all,
      );
}

class SplitTunnelConfig {
  const SplitTunnelConfig({
    this.mode = TunnelMode.all,
    this.packages = const <String>{},
  });

  final TunnelMode mode;
  final Set<String> packages;

  /// A split mode with nothing selected would either mean nothing (bypass) or
  /// leave only BULBVPN itself inside the tunnel (allow), so it degrades to
  /// the full tunnel instead of silently breaking connectivity.
  TunnelMode get appliedMode =>
      mode == TunnelMode.all || packages.isEmpty ? TunnelMode.all : mode;

  bool get isSplit => mode != TunnelMode.all;

  int get appCount => packages.length;

  SplitTunnelConfig copyWith({TunnelMode? mode, Set<String>? packages}) {
    return SplitTunnelConfig(
      mode: mode ?? this.mode,
      packages: packages ?? this.packages,
    );
  }

  Map<String, Object?> toJson() => {
        'mode': mode.name,
        'packages': packages.toList()..sort(),
      };

  factory SplitTunnelConfig.fromJson(Map<String, Object?> json) {
    final rawPackages = json['packages'];
    return SplitTunnelConfig(
      mode: TunnelMode.fromName(json['mode']?.toString()),
      packages: {
        if (rawPackages is List) ...rawPackages.whereType<String>(),
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SplitTunnelConfig &&
      other.mode == mode &&
      other.packages.length == packages.length &&
      other.packages.containsAll(packages);

  @override
  int get hashCode => Object.hash(mode, Object.hashAllUnordered(packages));

  @override
  String toString() => 'SplitTunnelConfig(${mode.name}, ${packages.length} apps)';
}

/// Reads and writes the routing choice. The in-memory copy is what the
/// connect path uses, so a change made in Settings applies to the next dial
/// without another async read on the handshake hot path.
class SplitTunnelStore {
  static const _key = 'split_tunnel';

  static SplitTunnelConfig? _cached;

  static SplitTunnelConfig? get cached => _cached;

  static Future<SplitTunnelConfig> load() async {
    final memo = _cached;
    if (memo != null) return memo;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      final config = raw == null
          ? const SplitTunnelConfig()
          : SplitTunnelConfig.fromJson(
              jsonDecode(raw) as Map<String, Object?>,
            );
      _cached = config;
      return config;
    } catch (_) {
      return const SplitTunnelConfig();
    }
  }

  static Future<void> save(SplitTunnelConfig config) async {
    _cached = config;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(config.toJson()));
    } catch (_) {}
  }

  @visibleForTesting
  static void resetCache() => _cached = null;
}

class SplitTunnelNotifier extends StateNotifier<SplitTunnelConfig> {
  SplitTunnelNotifier()
      : super(SplitTunnelStore.cached ?? const SplitTunnelConfig()) {
    _hydrate();
  }

  Future<void> _hydrate() async {
    final loaded = await SplitTunnelStore.load();
    if (!mounted || loaded == state) return;
    state = loaded;
  }

  Future<void> setMode(TunnelMode mode) => _apply(state.copyWith(mode: mode));

  Future<void> setPackage(String package, {required bool selected}) {
    final next = {...state.packages};
    if (selected) {
      next.add(package);
    } else {
      next.remove(package);
    }
    return _apply(state.copyWith(packages: next));
  }

  Future<void> clearPackages() => _apply(state.copyWith(packages: const {}));

  Future<void> _apply(SplitTunnelConfig config) async {
    if (config == state) return;
    state = config;
    await SplitTunnelStore.save(config);
  }
}

final splitTunnelProvider =
    StateNotifierProvider<SplitTunnelNotifier, SplitTunnelConfig>(
  (ref) => SplitTunnelNotifier(),
);
