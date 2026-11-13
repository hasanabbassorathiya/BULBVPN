import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bulbvpn/modules/core/tunnel_liveness.dart';

void main() {
  group('orphan tunnel classification', () {
    test('the daemon kept the tunnel up after the UI process died', () {
      // The symptom: Android still shows a live VPN while the relaunched app
      // has no in-memory session. The Xray service lives in its own process,
      // so it survives and keeps forwarding.
      const state = SystemVpnState(
        reported: true,
        vpnNetworkUp: true,
        realityDaemonUp: true,
      );
      expect(
        TunnelLiveness.classify(state, realitySessionRecorded: true),
        OrphanTunnel.reality,
      );
    });

    test('a VPN that is not ours is never adopted', () {
      const state = SystemVpnState(
        reported: true,
        vpnNetworkUp: true,
        realityDaemonUp: false,
      );
      expect(
        TunnelLiveness.classify(state, realitySessionRecorded: true),
        OrphanTunnel.otherOwner,
      );
    });

    test('our own stalled tunnel is not blamed on another app', () {
      // The desync the user sees: Android's key still says "VPN on", the
      // SoftEther TUN is installed, but it stopped forwarding so isTunnelUp()
      // reads false. Before, this arm answered `otherOwner` and the session
      // record was discarded.
      const state = SystemVpnState(
        reported: true,
        vpnNetworkUp: true,
        softEtherTunnelUp: true,
      );
      expect(
        TunnelLiveness.classify(state, realitySessionRecorded: true),
        OrphanTunnel.ours,
      );
    });

    test('our kill switch counts as our interface, not another app', () {
      const state = SystemVpnState(
        reported: true,
        vpnNetworkUp: true,
        lockedDown: true,
      );
      expect(
        TunnelLiveness.classify(state, realitySessionRecorded: false),
        OrphanTunnel.ours,
      );
    });

    test('a live daemon tunnel still outranks our held interface', () {
      const state = SystemVpnState(
        reported: true,
        vpnNetworkUp: true,
        realityDaemonUp: true,
        softEtherTunnelUp: true,
      );
      expect(
        TunnelLiveness.classify(state, realitySessionRecorded: true),
        OrphanTunnel.reality,
      );
    });

    test('a lingering daemon with no recorded session proves nothing', () {
      const state = SystemVpnState(
        reported: true,
        vpnNetworkUp: true,
        realityDaemonUp: true,
      );
      expect(
        TunnelLiveness.classify(state, realitySessionRecorded: false),
        OrphanTunnel.none,
      );
    });

    test('no VPN network means nothing to adopt', () {
      const state = SystemVpnState(
        reported: true,
        vpnNetworkUp: false,
        realityDaemonUp: true,
      );
      expect(
        TunnelLiveness.classify(state, realitySessionRecorded: true),
        OrphanTunnel.none,
      );
    });

    test('an unanswered query is treated as unknown, not as a live tunnel', () {
      const state = SystemVpnState(reported: false);
      expect(
        TunnelLiveness.classify(state, realitySessionRecorded: true),
        OrphanTunnel.none,
      );
    });
  });

  group('session record', () {
    test('stays written while our own tunnel is still up', () {
      const state = SystemVpnState(
        reported: true,
        vpnNetworkUp: true,
        realityDaemonUp: true,
      );
      expect(
        TunnelLiveness.clearsSessionOnRestart(
          state,
          realitySessionRecorded: true,
        ),
        isFalse,
      );
    });

    test('is dropped once the tunnel is really gone', () {
      const state = SystemVpnState(
        reported: true,
        vpnNetworkUp: false,
        realityDaemonUp: false,
      );
      expect(
        TunnelLiveness.clearsSessionOnRestart(
          state,
          realitySessionRecorded: true,
        ),
        isTrue,
      );
    });

    test('is dropped when the live tunnel belongs to another app', () {
      const state = SystemVpnState(
        reported: true,
        vpnNetworkUp: true,
        realityDaemonUp: false,
      );
      expect(
        TunnelLiveness.clearsSessionOnRestart(
          state,
          realitySessionRecorded: true,
        ),
        isTrue,
      );
    });

    test('survives while our own interface is still installed', () {
      const stalled = SystemVpnState(
        reported: true,
        vpnNetworkUp: true,
        softEtherTunnelUp: true,
      );
      const blocked = SystemVpnState(
        reported: true,
        vpnNetworkUp: true,
        lockedDown: true,
      );
      expect(
        TunnelLiveness.clearsSessionOnRestart(
          stalled,
          realitySessionRecorded: true,
        ),
        isFalse,
      );
      expect(
        TunnelLiveness.clearsSessionOnRestart(
          blocked,
          realitySessionRecorded: true,
        ),
        isFalse,
      );
    });
  });

  test('a stop that left the daemon holding the tunnel is detected', () {
    const stillUp = SystemVpnState(
      reported: true,
      vpnNetworkUp: true,
      realityDaemonUp: true,
    );
    const gone = SystemVpnState(
      reported: true,
      vpnNetworkUp: false,
      realityDaemonUp: false,
    );
    expect(TunnelLiveness.realityTunnelStillHeld(stillUp), isTrue);
    expect(TunnelLiveness.realityTunnelStillHeld(gone), isFalse);
  });

  group('platform contract', () {
    test('reads the keys the activity actually returns', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('app.bulbvpn.com/softether');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'systemState'
                ? {
                    'vpnNetworkUp': true,
                    'realityDaemonUp': true,
                    'softEtherTunnelUp': false,
                    'lockedDown': false,
                  }
                : null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final state = await querySystemVpnState();
      expect(state.reported, isTrue);
      expect(state.vpnNetworkUp, isTrue);
      expect(state.realityDaemonUp, isTrue);
      expect(state.oursHeld, isFalse);
      expect(
        TunnelLiveness.classify(state, realitySessionRecorded: true),
        OrphanTunnel.reality,
      );
    });

    test('reads our own interface flags the activity sends', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('app.bulbvpn.com/softether');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'systemState'
                ? {
                    'vpnNetworkUp': true,
                    'realityDaemonUp': false,
                    'softEtherTunnelUp': true,
                    'lockedDown': false,
                  }
                : null,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final state = await querySystemVpnState();
      expect(state.softEtherTunnelUp, isTrue);
      expect(state.oursHeld, isTrue);
      expect(
        TunnelLiveness.classify(state, realitySessionRecorded: true),
        OrphanTunnel.ours,
      );
      expect(
        TunnelLiveness.clearsSessionOnRestart(
          state,
          realitySessionRecorded: true,
        ),
        isFalse,
      );
    });

    test('an unanswered query never yields an adoption', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('app.bulbvpn.com/softether');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => throw MissingPluginException(),
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final state = await querySystemVpnState();
      expect(
        TunnelLiveness.classify(state, realitySessionRecorded: true),
        OrphanTunnel.none,
      );
      expect(TunnelLiveness.realityTunnelStillHeld(state), isFalse);
    });
  });
}
