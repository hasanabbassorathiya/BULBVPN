import 'package:bulbvpn/modules/core/split_tunnel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SplitTunnelConfig', () {
    test('defaults to the full tunnel', () {
      const config = SplitTunnelConfig();
      expect(config.mode, TunnelMode.all);
      expect(config.appliedMode, TunnelMode.all);
      expect(config.isSplit, isFalse);
      expect(config.appCount, 0);
    });

    test('a split mode with no apps degrades to the full tunnel', () {
      const config = SplitTunnelConfig(mode: TunnelMode.allow);
      expect(config.mode, TunnelMode.allow);
      expect(config.appliedMode, TunnelMode.all);
    });

    test('round-trips through json', () {
      const config = SplitTunnelConfig(
        mode: TunnelMode.bypass,
        packages: {'com.example.bank', 'org.mozilla.firefox'},
      );
      final decoded = SplitTunnelConfig.fromJson(config.toJson());
      expect(decoded, config);
      expect(decoded.packages, hasLength(2));
      expect(decoded.appliedMode, TunnelMode.bypass);
    });

    test('unknown modes and malformed packages fall back safely', () {
      final decoded = SplitTunnelConfig.fromJson({
        'mode': 'sideways',
        'packages': ['com.example.app', 42, null],
      });
      expect(decoded.mode, TunnelMode.all);
      expect(decoded.packages, {'com.example.app'});
    });

    test('copyWith keeps the untouched field', () {
      const config = SplitTunnelConfig(mode: TunnelMode.allow, packages: {'a'});
      expect(config.copyWith(mode: TunnelMode.bypass).packages, {'a'});
      expect(config.copyWith(packages: {'b'}).mode, TunnelMode.allow);
    });
  });

  group('SplitTunnelStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      SplitTunnelStore.resetCache();
    });

    test('defaults when nothing is saved', () async {
      final loaded = await SplitTunnelStore.load();
      expect(loaded.mode, TunnelMode.all);
      expect(loaded.packages, isEmpty);
    });

    test('saves and reloads the selection', () async {
      await SplitTunnelStore.save(
        const SplitTunnelConfig(
          mode: TunnelMode.bypass,
          packages: {'com.example.bank'},
        ),
      );
      SplitTunnelStore.resetCache();
      final loaded = await SplitTunnelStore.load();
      expect(loaded.mode, TunnelMode.bypass);
      expect(loaded.packages, {'com.example.bank'});
    });

    test('serves the cached value without hitting prefs again', () async {
      await SplitTunnelStore.save(
        const SplitTunnelConfig(mode: TunnelMode.allow, packages: {'a.b'}),
      );
      final loaded = await SplitTunnelStore.load();
      expect(loaded.mode, TunnelMode.allow);
      expect(identical(loaded, SplitTunnelStore.cached), isTrue);
    });
  });

  /// appliedMode is what the next session does, and on Android the only
  /// dialled engine takes a deny list: an allow list there would mean no
  /// tunnel at all. The stored mode stays allow so the choice survives a
  /// build that can honour it, but nothing may read `mode` as a promise.
  test(
    'allow-list runs as the full tunnel on Android and as itself elsewhere',
    () {
      const saved = SplitTunnelConfig(
        mode: TunnelMode.allow,
        packages: {'a.b'},
      );
      for (final platform in const [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(
          saved.appliedMode,
          platform == TargetPlatform.android
              ? TunnelMode.all
              : TunnelMode.allow,
          reason: '$platform was not the platform the summary was computed for',
        );
        expect(
          saved.scopeSummary,
          platform == TargetPlatform.android
              ? 'All apps use the tunnel · only-selected cannot run'
              : 'Only · 1 app inside',
        );
      }
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
