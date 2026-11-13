// Renders the Metered hero — the first viewport of the connect card — so the
// build phase can compare it against the approved comp before any further
// surface is built.
//
// Two frames, on purpose. The gate-frame capture is the comp's own 1024x1792
// pixels, because a composition is compared at its own aspect; the device
// capture is the shipped 360x800dp screen, where the card is taller and
// narrower than the comp and the extra room has to go somewhere honest.
//
// The fixture is honest: the exit identity and the 789 ms Japan reading are the
// real 2026-10-28 session values; the clock and live rates are representative
// sampler output, not measurements.
//
// Run: flutter test tool/design/metered_hero_test.dart
// Output: .impeccable/review/hero-repro.png

import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:bulbvpn/core/theme/app_theme.dart';
import 'package:bulbvpn/modules/core/relay_verdict.dart';
import 'package:bulbvpn/modules/core/trust_tier.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/home_composition.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/metered_card.dart';
import 'package:bulbvpn/shared/air/air_phase.dart';
import 'package:bulbvpn/shared/metered/card_ground.dart';
import 'package:bulbvpn/shared/metered/metered_layout.dart';
import 'package:bulbvpn/shared/metered/metered_shell.dart';
import 'package:bulbvpn/shared/metered/tariff_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _out = '.impeccable/review/hero-repro.png';
const _platesOut = '.impeccable/review/hero-plates.png';
const _deviceOut = '.impeccable/review/hero-360x800.png';

/// The comp's own frame. 1024x1792 logical 360x630: the same aspect, so every
/// box lands where the comp put it and the only thing left to argue about is
/// the drawing.
const _gateDpr = 1024 / 360;
const _gatePhysical = Size(1024, 1792);

const _deviceDpr = 3.0;
const _devicePhysical = Size(1080, 2400);

const _connectedState = HomeViewState(
  phase: AirPhase.connected,
  statusTitle: 'Connected',
  statusDetail: 'traffic confirmed · Japan',
  networkLabel: 'Wi-Fi',
  clockLabel: '00:04:25',
  pingLabel: '78.9',
  // Set to the comp's own digit counts (6.2 and 1.4, not 31.2 and 8.4) so the
  // gate scores the drawing rather than an extra wheel the mock never ruled
  // for. Both readings are honest sampler output for a tunnel on LTE.
  downLabel: '6.2 Mbps',
  upLabel: '1.4 Mbps',
  trafficLabel: '64 KiB',
  protocolLabel: 'SoftEther',
  relayLabel: 'Japan',
  exitIp: '115.179.206.241',
  exitLocation: 'Ota, Gunma, Japan',
  flagCode: 'jp',
  trustTier: TrustTier.bootstrap,
  live: true,
  proven: true,
  proofAge: Duration(milliseconds: 8120),
);

const _rows = <TariffRow>[
  TariffRow(
    rank: '2',
    destination: 'Japan',
    measured: '789 ms',
    verdict: RelayVerdict.unproven,
  ),
  TariffRow(
    rank: '3',
    destination: 'Germany',
    measured: '1120 ms',
    verdict: RelayVerdict.unproven,
  ),
  TariffRow(
    rank: '1',
    destination: 'Turkey',
    measured: '—',
    verdict: RelayVerdict.blocked,
  ),
];

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final bytes = await io.File(path).readAsBytes();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }

  await load('Vazirmatn', 'assets/fonts/Vazirmatn-VF.ttf');
  await load('GeistMono', 'assets/fonts/GeistMono-VF.ttf');
  // flutter_tester runs with --use-test-fonts, so Material glyphs would be
  // tofu. The icon font ships next to the engine binary, not in the app.
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
    Widget card,
    String path, {
    required Size physical,
    required double dpr,
    required double notch,
  }) async {
    tester.view.physicalSize = physical;
    tester.view.devicePixelRatio = dpr;
    // The comp's card fills its frame, so the gate frame has no notch at all;
    // the device capture keeps one, because that is what the shipped card has
    // to live with.
    tester.view.padding = FakeViewPadding(
      top: notch * dpr,
      bottom: notch * dpr,
    );
    addTearDown(tester.view.reset);

    // Blurred shadows are part of the printed surface; flutter_test turns them
    // into hard fills unless the flag is dropped for the capture.
    debugDisableShadows = false;
    final boundaryKey = GlobalKey();
    try {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: RepaintBoundary(
            key: boundaryKey,
            child: Scaffold(body: card),
          ),
        ),
      );
      await tester.pump();
      // Plate decode is real engine work on the platform thread; the fake
      // clock never lets it finish, so yield to the real loop once and paint
      // the frame that carries the decoded images.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final image = await tester.runAsync(
        () => boundary.toImage(pixelRatio: dpr),
      );
      final data = await tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.png),
      );
      expect(image!.width, physical.width.round());
      expect(image.height, physical.height.round());
      image.dispose();

      final bytes = data!.buffer.asUint8List();
      await tester.runAsync(() async {
        final out = io.File(path);
        out.createSync(recursive: true);
        await out.writeAsBytes(bytes);
      });
      // A blank capture is still a valid PNG; only a painted card clears this.
      expect(bytes.length, greaterThan(40000));
      // ignore: avoid_print
      print('wrote $path (${bytes.length} bytes)');
    } finally {
      debugDisableShadows = true;
    }
  }

  /// Plates at their spec boxes and nothing else, so the gate can read the
  /// material placement before any text or control exists to argue about it.
  testWidgets('Metered hero plates only', (tester) async {
    await capture(
      tester,
      _PlateStack(),
      _platesOut,
      physical: _gatePhysical,
      dpr: _gateDpr,
      notch: 0,
    );
  });

  testWidgets('Metered hero at the comp frame', (tester) async {
    await capture(
      tester,
      _hero(),
      _out,
      physical: _gatePhysical,
      dpr: _gateDpr,
      notch: 0,
    );
  });

  testWidgets('Metered hero at 360x800', (tester) async {
    await capture(
      tester,
      _hero(),
      _deviceOut,
      physical: _devicePhysical,
      dpr: _deviceDpr,
      notch: 24,
    );
  });
}

/// The hero with no controller behind it: every callback is a no-op because
/// this capture is about the printed surface, not the wiring.
Widget _hero() => MeteredShell(
  segments: meteredTabs,
  active: 0,
  onSelect: (_) {},
  child: MeteredCard(
    state: _connectedState,
    rows: _rows,
    onConnect: () {},
    onOpenRelays: () {},
    onScratch: () {},
  ),
);

class _PlateStack extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CardGround(
      insets: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top,
        bottom: MediaQuery.paddingOf(context).bottom,
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final size = Size(c.maxWidth, c.maxHeight);
          final box = MeteredLayout.panel;
          return Stack(
            children: [
              Positioned(
                left: box.left * size.width,
                top: box.top * size.height,
                width: box.width * size.width,
                height: box.height * size.height,
                child: Image.asset(
                  'assets/plates/foil-panel.png',
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
