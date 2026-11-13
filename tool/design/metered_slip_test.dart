// Renders the Metered relay slip and the import slip at the shipped device
// classes, so the sheet's own print — column register, rules, keys — is looked
// at rather than only asserted on.
//
// The height factor is the app's: a modal sheet gets 0.82 and 0.72 of the
// screen, which on a 360x800 phone is 656 dp and 576 dp. The widget tests run
// the sheet as a body, where it is handed the whole screen and cannot overflow.
// This capture is the one that can.
//
// Run: flutter test tool/design/metered_slip_test.dart
// Output: .impeccable/review/slip-<name>-<size>.png

import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:bulbvpn/core/theme/app_theme.dart';
import 'package:bulbvpn/modules/core/reality/reality_engine.dart';
import 'package:bulbvpn/modules/core/reality/reality_relay.dart';
import 'package:bulbvpn/modules/core/relay_memory.dart';
import 'package:bulbvpn/modules/core/server_catalog.dart';
import 'package:bulbvpn/modules/core/vpn_server.dart';
import 'package:bulbvpn/modules/main/application/relay_evidence_provider.dart';
import 'package:bulbvpn/modules/main/application/server_ping_provider.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/relay_import_sheet.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/server_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _dir = '.impeccable/review';

/// The two phones the app ships for: a 360x800 dp low-end Android and the
/// 430x932 dp iPhone the comp was drawn against.
const _sizes = <String, Size>{
  '360x800': Size(1080, 2400),
  '430x932': Size(1290, 2796),
};
const _dprs = <String, double>{'360x800': 3.0, '430x932': 3.0};

VpnServer _server(String ip, String country, String short) {
  return VpnServer(
    hostName: 'relay-$ip',
    ip: ip,
    countryLong: country,
    countryShort: short,
    score: 0,
    ping: 0,
    speed: 1048576,
    numVpnSessions: 3,
    uptime: 0,
    openVpnConfigBase64: '',
  );
}

class _FakeCatalog extends ServerCatalog {
  _FakeCatalog(this.servers);
  final List<VpnServer> servers;

  @override
  Future<List<VpnServer>> build() async => servers;
}

class _FakePings extends ServerPingNotifier {
  _FakePings(Map<String, ServerPing> byIp, bool probing) {
    state = ServerPingState(byIp: byIp, probing: probing);
  }

  @override
  Future<void> ensureFresh(List<VpnServer> servers) async {}

  @override
  Future<void> pingAll(List<VpnServer> servers) async {}
}

/// The settled sweep: four relays answered, one never did.
const _settled = <String, ServerPing>{
  '10.0.0.1': ServerPing.ok(45),
  '10.0.0.2': ServerPing.ok(210),
  '10.0.1.1': ServerPing.ok(95),
  '10.0.2.1': ServerPing.timeout,
  '10.0.3.1': ServerPing.ok(31),
};

/// The same sweep with three probes still in flight, which is what a first
/// open on a censored network actually looks like.
const _midSweep = <String, ServerPing>{
  '10.0.0.1': ServerPing.ok(45),
  '10.0.0.2': ServerPing.pending,
  '10.0.1.1': ServerPing.pending,
  '10.0.2.1': ServerPing.timeout,
  '10.0.3.1': ServerPing.pending,
};

const _japan = RealityRelay(
  id: 'community-jp-1',
  host: '171.244.8.1',
  port: 443,
  uuid: 'b0f6d1a2-3f4c-4d5e-8f9a-0b1c2d3e4f5a',
  publicKey: 'PFC3JN1er1JE2vAemwRhNjewz8I4NUWP4XHf2Dza4Es',
  serverName: 'www.google.com',
  shortId: '12e321ba',
  countryCode: 'JP',
  countryName: 'Japan',
  city: 'Tokyo',
);

const _own = RealityRelay(
  id: 'Home-1',
  host: '203.0.113.7',
  port: 2087,
  uuid: 'c1f6d1a2-3f4c-4d5e-8f9a-0b1c2d3e4f5b',
  publicKey: '',
  serverName: '',
  countryCode: '',
  countryName: 'Home-1',
  city: '',
  private: true,
  link:
      'trojan://s3cret@203.0.113.7:2087?security=tls'
      '&sni=cdn.example.net&type=grpc#Home-1',
);

Future<void> _loadFonts() async {
  Future<void> load(String family, String asset) async {
    final file = io.File(asset);
    if (!file.existsSync()) return;
    final bytes = await file.readAsBytes();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }

  await load('Vazirmatn', 'assets/fonts/Vazirmatn-VF.ttf');
  await load('GeistMono', 'assets/fonts/GeistMono-VF.ttf');
  final sdkCache = io.File(
    io.Platform.resolvedExecutable,
  ).parent.parent.parent.parent;
  await load(
    'MaterialIcons',
    '${sdkCache.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadFonts);

  Future<void> capture(
    WidgetTester tester,
    Widget sheet,
    String name,
    String sizeKey, {
    Map<String, ServerPing> pings = _settled,
    bool probing = false,
  }) async {
    final physical = _sizes[sizeKey]!;
    final dpr = _dprs[sizeKey]!;
    tester.view.physicalSize = physical;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);

    debugDisableShadows = false;
    final boundaryKey = GlobalKey();
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serversProvider.overrideWith(
              () => _FakeCatalog([
                _server('10.0.0.1', 'Japan', 'JP'),
                _server('10.0.0.2', 'Japan', 'JP'),
                _server('10.0.1.1', 'United States', 'US'),
                _server('10.0.2.1', 'Germany', 'DE'),
                _server('10.0.3.1', 'Singapore', 'SG'),
              ]),
            ),
            serverPingProvider.overrideWith(
              (ref) => _FakePings(pings, probing),
            ),
            realitySupportedProvider.overrideWithValue(true),
            realityRelaysProvider.overrideWith((ref) async => [_japan, _own]),
            relayEvidenceProvider.overrideWith(
              (ref) async => RelayEvidence(
                proven: {
                  '10.0.0.1': SessionProof(
                    dial: '10.0.0.1',
                    bytesPerSecond: 6200000,
                    at: DateTime.now().subtract(const Duration(minutes: 4)),
                  ),
                },
                health: null,
              ),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: RepaintBoundary(
              key: boundaryKey,
              child: Scaffold(
                backgroundColor: Colors.black45,
                body: SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: name == 'import' ? 0.72 : 0.82,
                      child: sheet,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));

      expect(tester.takeException(), isNull, reason: '$name at $sizeKey');

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final image = await tester.runAsync(
        () => boundary.toImage(pixelRatio: dpr),
      );
      final data = await tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.png),
      );
      image!.dispose();

      final path = '$_dir/slip-$name-$sizeKey.png';
      final bytes = data!.buffer.asUint8List();
      await tester.runAsync(() async {
        final out = io.File(path);
        out.createSync(recursive: true);
        await out.writeAsBytes(bytes);
      });
      expect(bytes.length, greaterThan(40000));
      // ignore: avoid_print
      print('wrote $path (${bytes.length} bytes)');
    } finally {
      debugDisableShadows = true;
    }
  }

  for (final sizeKey in _sizes.keys) {
    testWidgets('relay slip at $sizeKey', (tester) async {
      await capture(tester, const ServerSheet(), 'relay', sizeKey);
    });

    testWidgets('import slip at $sizeKey', (tester) async {
      await capture(tester, const RelayImportSheet(), 'import', sizeKey);
    });
  }

  /// A slip with three probes still in flight: the pending and absent readings
  /// are the ones a first-time user actually sees, and they are the rows with
  /// the least ink holding up the column.
  testWidgets('relay slip mid-sweep', (tester) async {
    await capture(
      tester,
      const ServerSheet(),
      'measuring',
      '360x800',
      pings: _midSweep,
      probing: true,
    );
  });
}
