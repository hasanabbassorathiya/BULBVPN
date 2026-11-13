import 'package:bulbvpn/modules/core/session_liveness.dart';
import 'package:bulbvpn/shared/providers/connection_state_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// A dial that has a session installed but has not finished judging its first
/// byte is still a session. Recovery firing during that window tears down a
/// tunnel that was proven seconds later -- the churn behind "Android shows
/// connected but the app says disconnected".
void main() {
  group('holdsLiveSession', () {
    test('a tunnel under first-byte judgement is a live session', () {
      expect(holdsLiveSession(ConnectionStatus.analyzing), isTrue);
    });

    test('a proven tunnel is a live session', () {
      expect(holdsLiveSession(ConnectionStatus.connected), isTrue);
    });

    test('no recovery is owed by a state without a session', () {
      for (final status in const <ConnectionStatus>[
        ConnectionStatus.disconnected,
        ConnectionStatus.loading,
        ConnectionStatus.connecting,
        ConnectionStatus.disconnecting,
        ConnectionStatus.error,
        ConnectionStatus.noInternet,
      ]) {
        expect(holdsLiveSession(status), isFalse, reason: '$status has no tunnel');
      }
    });
  });
}
