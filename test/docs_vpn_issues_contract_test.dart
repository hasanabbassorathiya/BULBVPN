import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level regression tests for the rules recorded in `docs/vpn-issues.md`
/// and `docs/connection-solutions.md`.
///
/// Those catalogs close with a list of things that must never come back: an
/// 8s SoftEther cancel, a `sslDebug=3` shipping build, an OpenVPN dial on a
/// random high port, a second engine dialled before SoftEther. None of them
/// are visible to a Dart unit test — they live in Kotlin, Swift, an Xcode
/// project and an Android manifest — so nothing was actually enforcing them
/// except the prose. Each rule below is one assertion against the shipped
/// source, and each names the failure it prevents so a red test points at the
/// incident rather than the string.
///
/// These are deliberately cheap substring/shape checks, not parses. They will
/// fail on a legitimate refactor that moves a constant; that is the intended
/// cost, because the alternative is discovering the regression on an Iranian
/// carrier at 3am.
void main() {
  String read(String path) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path disappeared');
    return file.readAsStringSync();
  }

  late final String softEtherKt;
  late final String mainActivityKt;
  late final String controller;
  late final String manifest;
  late final String appGradle;
  late final String iosProvider;
  late final String macosProvider;
  late final String iosSession;

  setUpAll(() {
    softEtherKt = read(
      'android/app/src/main/kotlin/app/bulbvpn/com/SoftEtherVpnService.kt',
    );
    mainActivityKt = read(
      'android/app/src/main/kotlin/app/bulbvpn/com/MainActivity.kt',
    );
    controller = read('lib/modules/core/vpn_controller.dart');
    manifest = read('android/app/src/main/AndroidManifest.xml');
    appGradle = read('android/app/build.gradle.kts');
    iosProvider = read('ios/PacketTunnel/PacketTunnelProvider.swift');
    macosProvider = read('macos/PacketTunnel/PacketTunnelProvider.swift');
    iosSession = read('ios/PacketTunnel/SoftEtherSession.swift');
  });

  group('budgets that were shortened into a bug', () {
    // Android LTE: a budget capped at 8s cancelled the handshake at ~8.0s
    // (`SOFTETHER_ERR_CANCELLED`, -12) while DHCP alone needed ~9s.
    test('SoftEther dials with the full 28s, never an 8s cap', () {
      final calls = RegExp(
        r'connectWithDeadline\([^,]+,\s*(\d+)_?(\d*)\)',
      ).allMatches(softEtherKt).toList();
      expect(calls, isNotEmpty, reason: 'no deadline-bounded dial found');
      for (final call in calls) {
        final ms = int.parse('${call.group(1)}${call.group(2)}');
        expect(
          ms,
          greaterThanOrEqualTo(28_000),
          reason: 'SoftEther budget dropped to ${ms}ms — the 8s cancel bug',
        );
      }
    });

    test('the deadline helper itself does not impose a shorter budget', () {
      final body = softEtherKt.substring(
        softEtherKt.indexOf('private fun connectWithDeadline'),
      );
      expect(
        body.substring(0, 900),
        contains('budgetMs'),
        reason: 'connectWithDeadline ignores its caller budget',
      );
    });

    // An OpenVPN watchdog under the real AUTH time cut live handshakes at 10s.
    test('the Android per-attempt watchdog is at least 18s', () {
      final match = RegExp(
        r'_androidAttemptWatchdog\s*=\s*Duration\(seconds:\s*(\d+)\)',
      ).firstMatch(controller);
      expect(match, isNotNull);
      expect(int.parse(match!.group(1)!), greaterThanOrEqualTo(18));
    });

    // Docs: "Tuned; do not reintroduce 8s SoftEther cancel."
    test('the Apple SoftEther watchdog still outlives DHCP', () {
      final match = RegExp(
        r'_appleSoftEtherWatchdog\s*=\s*Duration\(seconds:\s*(\d+)\)',
      ).firstMatch(controller);
      expect(match, isNotNull);
      expect(int.parse(match!.group(1)!), greaterThanOrEqualTo(30));
    });
  });

  group('dial order', () {
    // Fresh installs on 19 Oct: only the Mac reached the SoftEther session,
    // because everything else spent the whole budget on OpenVPN timeouts.
    test('Apple dials SoftEther before the OpenVPN stage', () {
      final apple = controller.indexOf('_tryAppleSoftEther(container');
      final openVpn = controller.indexOf(
        '// UDP rarely dials on filtered paths',
      );
      expect(apple, greaterThan(-1));
      expect(
        apple,
        lessThan(openVpn),
        reason: 'OpenVPN is back in front of Apple SoftEther',
      );
    });

    /// Android's failure mode on Iranian LTE was spending the whole 100s budget
    /// dialling engines the carriers black-hole, then reporting the error the
    /// REALITY loop had already established. The contract is now that no
    /// SoftEther or OpenVPN dial exists on that branch at all.
    test('Android dials neither SoftEther nor OpenVPN', () {
      expect(
        controller.contains('_tryOneSoftEther(container'),
        isFalse,
        reason: 'a SoftEther dial is back on Android',
      );
      final android = controller.indexOf(
        "if (Platform.isAndroid) {\n      // Tear down any legacy SoftEther tunnel",
      );
      final reality = controller.indexOf('_tryReality(container', android);
      final verdict = controller.indexOf(
        "'[VpnController] No tunnel on Android:",
        android,
      );
      final openVpn = controller.indexOf(
        '// UDP rarely dials on filtered paths',
      );
      expect(android, greaterThan(-1));
      expect(reality, greaterThan(android));
      expect(
        verdict,
        greaterThan(reality),
        reason: 'Android can still fall out of the REALITY loop unreported',
      );
      expect(
        verdict,
        lessThan(openVpn),
        reason: 'the Android branch reaches the OpenVPN stage',
      );
    });

    test('a user stop during a handshake cannot hand the session to OpenVPN', () {
      final gate = controller.indexOf(
        'if (_manualDisconnect) {\n      _log.addLog(\'[VpnController] Connect cancelled by user\');',
      );
      expect(
        gate,
        greaterThan(-1),
        reason: 'post-handshake intent re-check gone',
      );
    });
  });

  group('OpenVPN 2.6 compatibility lines', () {
    final candidates = 'lib/modules/core/vpn_gate_candidates.dart';

    test('the 2.6 lines are injected for engines that need them', () {
      final src = read(candidates);
      for (final line in [
        'compat-mode 2.4.0',
        'data-ciphers AES-128-CBC',
        'provider legacy default',
      ]) {
        expect(
          src,
          contains(line),
          reason: '$line was dropped — AUTH stalls forever',
        );
      }
    });

    test('the same lines are stripped again for the Apple OpenVPN 3 stack', () {
      final src = read(candidates);
      expect(
        RegExp(
              r"^\s\*(compat-mode|data-ciphers|provider)\b",
              multiLine: true,
            ).hasMatch(src) ||
            src.contains(r"^\s*(compat-mode|data-ciphers|provider)\b"),
        isTrue,
        reason: 'the Apple strip regex is gone; 2.6 lines break OpenVPN 3',
      );
    });

    test('credentials stay inlined as an <auth-user-pass> block', () {
      expect(read(candidates), contains('<auth-user-pass>'));
      expect(controller, contains('<auth-user-pass>'));
    });
  });

  group('Apple markers and extension hygiene', () {
    test('the controller emits the host/SNI markers the extension reads', () {
      expect(controller, contains('# bulb-host'));
      expect(controller, contains('# bulb-sni'));
      expect(iosProvider, contains('name: "bulb-host"'));
      expect(iosProvider, contains('name: "bulb-sni"'));
      expect(macosProvider, contains('name: "bulb-host"'));
    });

    // sslDebug=3 jetsammed the iOS 16 packet tunnel extension.
    test('no shipping provider leaves sslDebug above 1', () {
      for (final src in [iosProvider, macosProvider]) {
        expect(
          src,
          contains('sslDebugLevel = 1'),
          reason: 'sslDebug dropped to a debug-only value',
        );
        expect(src, isNot(contains('sslDebugLevel = 3')));
      }
    });

    // A failed connect left the app-side socketpair ends open before the
    // plain retry, leaking two fds per attempt.
    test('a failed Apple attempt closes its socketpairs before retrying', () {
      expect(
        RegExp(
          r'softether_request_stop\(created\)[\s\S]{0,400}?closeTunnelFds\(\)',
        ).hasMatch(iosSession),
        isTrue,
        reason: 'the retry path leaked four fds per attempt again',
      );
      final partial = iosSession.substring(
        iosSession.indexOf('guard let download = Self.socketPair'),
      );
      expect(
        partial.substring(0, 400),
        contains('close(upload.0)'),
        reason: 'a partial socketpair failure leaked the half it opened',
      );
      expect(
        iosSession,
        contains('softether_set_default_route(created, false)'),
        reason: 'the library is installing routes into the sandbox again',
      );
    });
  });

  group('Android packaging and lifecycle', () {
    test(
      'native libs are extracted, or SoftEther/OpenVPN have nothing to load',
      () {
        expect(manifest, contains('android:extractNativeLibs="true"'));
        expect(appGradle, contains('useLegacyPackaging = true'));
      },
    );

    // Android: a second service instance used to null out the first one's
    // static handle and tear down a live tunnel.
    test('service teardown is identity-checked', () {
      final onDestroy = softEtherKt.substring(
        softEtherKt.indexOf('override fun onDestroy()'),
      );
      expect(
        onDestroy.substring(0, 600),
        contains('if (instance === this)'),
        reason: 'onDestroy clobbers a newer service instance again',
      );
    });

    // The Dart side gave up at 45s but left the native handshake running, so
    // a late success installed a tunnel Dart had already recorded as failed.
    test('the activity timeout stops native work', () {
      expect(mainActivityKt, contains('requestStop("timeout")'));
    });

    // Disconnecting while nativeConnect was in flight produced a SIGSEGV in
    // libsoftether_jni.so; handle/fd access must stay under the lock.
    test('session state is guarded and deferred destroy still runs', () {
      expect(softEtherKt, contains('private val sessionLock'));
      expect(softEtherKt, contains('@Volatile private var client'));
      expect(softEtherKt, contains('@Volatile private var tunFd'));
      expect(softEtherKt, contains('releaseAfterHandshake('));
      expect(
        softEtherKt,
        contains('nativeRequestStop'),
        reason: 'teardown is back to killing nativeConnect mid-flight',
      );
    });
  });

  group('exit IP honesty', () {
    // The app is deliberately *not* excluded from its own TUN any more (docs
    // D7), so an exit lookup that fails must never fall back to the carrier
    // address.
    test('the carrier address can never be presented as the exit', () {
      final main = read(
        'lib/modules/main/presentation/screens/main_screen.dart',
      );
      expect(
        main,
        contains('exitIp.ip != beforeIp'),
        reason: 'a BEFORE address can be labelled as the exit again',
      );
    });

    test('a split-tunnel session is not claimed as a measured exit', () {
      final main = read(
        'lib/modules/main/presentation/screens/main_screen.dart',
      );
      expect(
        main,
        contains('appliedMode'),
        reason:
            'the UI is back to trusting the editor intent over what applied',
      );
    });
  });

  group('relay selection', () {
    test('OpenVPN dials are pinned to TCP 443', () {
      expect(controller, contains('_tcp443DialList'));
      expect(controller, contains('Candidate.withPort(c, 443)'));
    });

    // A country pick with 0 reachable listeners used to burn the whole budget
    // dialling known-dead hosts.
    test('strict selection fails fast instead of rotating dead hosts', () {
      expect(controller, contains('if (orderedReachable.isEmpty)'));
      expect(controller, contains('skipping dead-host rotation'));
    });

    test('a country pick still gets proven escape relays', () {
      expect(controller, contains("source: 'escape'"));
    });

    test('the VPN Gate catalog still carries the proven JP relays', () {
      final catalog = read('data/vpngate.json');
      expect(catalog, contains('219.100.37.105'));
      expect(catalog, contains('public-vpn-139.opengw.net'));
    });
  });

  group('liveness and the connected claim', () {
    test('the watchdog drops a session on 2 misses, not on a hunch', () {
      expect(
        RegExp(
          r'_watchdogMissesToDrop = (\d+)',
        ).firstMatch(controller)?.group(1),
        '2',
      );
    });

    test('an unanswered liveness query is never read as live', () {
      final liveness = read('lib/modules/core/tunnel_liveness.dart');
      expect(liveness, contains('querySystemVpnState'));
      expect(liveness, contains('OrphanTunnel'));
    });

    test('a network change while connected forces a clean redial', () {
      // The 20 Oct Irancell handover kept a session that was already routed
      // on the dead carrier; a green Connected with no egress followed.
      final handler = RegExp(
        r'if \(status == ConnectionStatus\.connected\) {\s*'
        r'_scheduleNetworkRedial\(\);\s*return;',
      );
      expect(
        handler.hasMatch(controller),
        isTrue,
        reason: 'a handover can adopt the old default route again',
      );
      final redial = RegExp(
        r'_scheduleNetworkRedial\(\{[\s\S]{0,1800}?'
        r'RealityEngine\.instance\.stop\(\)[\s\S]{0,600}?'
        r'SoftEtherVpn\.disconnect\(\)[\s\S]{0,600}?'
        r'_vpnService\.disconnect\(\)',
      );
      expect(
        redial.hasMatch(controller),
        isTrue,
        reason: 'the redial stopped tearing down all three engines first',
      );
    });

    test('the data-plane proof is cleared when the watchdog disarms', () {
      // A stale proof would let a later "adopted" session claim throughput
      // it never measured.
      expect(
        RegExp(
          r'void _disarmWatchdog\(\) \{[\s\S]{0,400}?'
          r'dataProofProvider\.notifier\)\.state = null;',
        ).hasMatch(controller),
        isTrue,
        reason: 'the disarm path no longer clears the proof',
      );
    });

    test('relay picks still spread across subnets', () {
      expect(
        controller,
        contains('final subnetCap = premium ? 3 : 2;'),
        reason:
            'the /24 cap was tightened back to one host, re-filling the '
            'budget with a single dead operator cluster',
      );
    });

    test('recovery never redials over a session that is up or being judged', () {
      // Emulator, 2 Nov: OpenVPN reached Connected with 64 KiB proven and the
      // pending recovery timer tore it down anyway. The throughput probe is
      // unawaited, so `_connect` returned while the claim was still `analyzing`
      // and counted that as a failed press.
      final entry = RegExp(
        r'void _scheduleRecovery\(\) \{[\s\S]{0,700}?holdsLiveSession\(',
      );
      expect(
        entry.hasMatch(controller),
        isTrue,
        reason: 'a live session opened a recovery ladder',
      );
      final fire = RegExp(
        r'_recoveryTimer = Timer[\s\S]{0,3000}?'
        r'final nowStatus = container\.read\(connectionStateProvider\)\.status;'
        r'[\s\S]{0,400}?holdsLiveSession\(nowStatus\)[\s\S]{0,500}?'
        r'Auto-reconnect \$attempt',
      );
      expect(
        fire.hasMatch(controller),
        isTrue,
        reason: 'the guard is read before the awaits and never re-taken',
      );
      final afterDial = RegExp(
        r'if \(holdsLiveSession\(status\)\) \{\s*'
        r'_autoReconnects = 0;',
      );
      expect(
        afterDial.hasMatch(controller),
        isTrue,
        reason: 'an unjudged handshake was treated as a failed attempt',
      );
    });
  });
}
