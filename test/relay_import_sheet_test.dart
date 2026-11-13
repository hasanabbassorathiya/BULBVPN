import 'dart:convert';

import 'package:bulbvpn/core/theme/app_theme.dart';
import 'package:bulbvpn/modules/core/reality/reality_relay.dart';
import 'package:bulbvpn/modules/core/reality/relay_vault.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/relay_import_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opens the sheet the way the server sheet does, so the route `Add` pops is a
/// real route and the assertions run on the screen underneath it.
Future<void> _open(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  RelayVault.resetCache();
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) => ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRelayImportSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The import sheet exists to make a wrong link visible before it is saved, so
/// these tests are about what the preview says, not about how it looks.
void main() {
  testWidgets('a pasted link is described before it is kept', (tester) async {
    await _open(tester);

    await tester.enterText(
      find.byType(TextField),
      'trojan://s3cret@203.0.113.7:2087?security=tls'
      '&sni=cdn.example.net&type=grpc&serviceName=video#Home-1',
    );
    await tester.tap(find.text('READ'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('ONE SERVER READ'), findsOneWidget);
    expect(find.text('Home-1'), findsOneWidget);
    expect(find.text('Trojan · gRPC · TLS · 203.0.113.7:2087'), findsOneWidget);
    expect(find.text('pretends to be cdn.example.net'), findsOneWidget);
    // Reading stores nothing. A preview must not write a credential to the
    // phone before the user has seen what it is.
    expect(RelayVault.cached, isEmpty);

    await tester.tap(find.text('ADD 1'));
    await tester.pumpAndSettle();

    final stored = RelayVault.cached;
    expect(stored, hasLength(1));
    expect(stored.single.private, isTrue);
    expect(stored.single.link, contains('trojan://'));
  });

  testWidgets('a server with no TLS cannot be added quietly', (tester) async {
    await _open(tester);

    await tester.enterText(
      find.byType(TextField),
      'vless://15c4ff1c-8c0a-4c0e-bb7f-4d3f0a4f2f11'
      '@plain.example.net:8080?encryption=none&type=ws#Plain',
    );
    await tester.tap(find.text('READ'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('runs without TLS'),
      findsOneWidget,
      reason: 'a profile with no TLS has to be said out loud',
    );
    expect(
      find.text('VLESS · WebSocket · plain.example.net:8080'),
      findsOneWidget,
    );
  });

  testWidgets('text that is not a profile is named, not swallowed', (
    tester,
  ) async {
    await _open(tester);

    await tester.enterText(find.byType(TextField), 'https:// sub.example/a');
    await tester.tap(find.text('READ'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No server in that text'), findsOneWidget);
    // Still on the READ key: nothing was previewed, so there is nothing to
    // add. A failure that quietly offered Save is how a bad paste becomes a
    // silent empty vault.
    expect(find.text('READ'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'vless://uuid@host');
    await tester.tap(find.text('READ'));
    await tester.pumpAndSettle();
    // A link with no port is still a destination: it reads as 443, which the
    // row prints as a bare host because the endpoint omits the default port.
    // What matters here is that it was previewed rather than refused, and that
    // a link with no TLS says so instead of looking like an ordinary server.
    expect(find.text('ONE SERVER READ'), findsOneWidget);
    expect(find.text('VLESS · TCP · host'), findsOneWidget);
    expect(find.textContaining('runs without TLS'), findsOneWidget);
  });

  testWidgets('an http subscription is refused before the socket opens', (
    tester,
  ) async {
    await _open(tester);

    await tester.enterText(
      find.byType(TextField),
      'http://sub.example.net/profile',
    );
    await tester.tap(find.text('READ'));
    await tester.pumpAndSettle();

    expect(find.textContaining('plain http is refused'), findsOneWidget);
    expect(RelayVault.cached, isEmpty);
  });

  testWidgets('a whole subscription body becomes several rows', (tester) async {
    await _open(tester);

    const links = [
      'trojan://a@192.0.2.1:443?security=tls&type=grpc#A',
      'trojan://b@192.0.2.2:443?security=tls#B',
    ];
    await tester.enterText(
      find.byType(TextField),
      base64Encode(utf8.encode('${links[0]}\n${links[1]}\n')),
    );
    await tester.tap(find.text('READ'));
    await tester.pumpAndSettle();

    expect(find.text('SERVERS READ'), findsOneWidget);
    expect(find.text('Trojan · gRPC · TLS · 192.0.2.1'), findsOneWidget);
    expect(find.text('Trojan · TCP · TLS · 192.0.2.2'), findsOneWidget);

    await tester.tap(find.text('ADD 2'));
    await tester.pumpAndSettle();
    final stored = RelayVault.cached.map((RealityRelay r) => r.id).toList();
    expect(stored, containsAll(<String>['A', 'B']));
  });
}
