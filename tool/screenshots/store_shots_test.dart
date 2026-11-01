// Renders the Connected and in-flight connect surfaces at store sizes. The
// in-flight fixture also carries the stage trace (`wake/dial/verify`) and its
// controller witness line, which the UI only shows while preparing,
// connecting, or verifying.
//
// Provenance: this build network blocks every relay dial, so the emulator can
// only reach Standby and Blocked. These two states are rendered from the
// production widget tree with a fixture. The exit identity is real — the
// 2026-10-28 Japan session verified exit 115.179.206.241 (Ota, Gunma,
// ARTERIA) and a 789 ms TLS ping on IR Wi-Fi. Session clock, live rates, and
// protocol are representative sampler values, not measurements.
//
// Run: flutter test tool/screenshots/store_shots_test.dart
// Output: docs/design/evidence/phase1/renders/*.png

import 'dart:io';
import 'dart:ui' as ui;

import 'package:bulbvpn/core/theme/app_theme.dart';
import 'package:bulbvpn/modules/core/trust_tier.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/home_composition.dart';
import 'package:bulbvpn/shared/air/air_phase.dart';
import 'package:bulbvpn/shared/air/connect_trace.dart';
import 'package:bulbvpn/shared/layout/navbar/defyx_navbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _outDir = 'docs/design/evidence/phase1/renders';

HomeViewState _connected() => const HomeViewState(
  phase: AirPhase.connected,
  statusTitle: 'Connected',
  statusDetail: 'traffic confirmed · Japan',
  networkLabel: 'Wi-Fi',
  clockLabel: '00:12:47',
  pingLabel: '789',
  downLabel: '312 KB/s',
  upLabel: '84 KB/s',
  protocolLabel: 'SoftEther',
  relayLabel: 'Japan',
  exitIp: '115.179.206.241',
  exitLocation: 'Ota, Gunma · Japan',
  flagCode: 'jp',
  trustTier: TrustTier.bootstrap,
  live: true,
);

HomeViewState _connecting() => const HomeViewState(
  phase: AirPhase.connecting,
  statusTitle: 'Connecting',
  statusDetail: 'opening tunnel · Japan',
  networkLabel: 'Wi-Fi',
  clockLabel: '14:32',
  pingLabel: '789',
  downLabel: '—',
  upLabel: '—',
  protocolLabel: 'Automatic',
  relayLabel: 'Japan',
  exitIp: '',
  exitLocation: '',
  flagCode: 'jp',
  trustTier: TrustTier.bootstrap,
  live: false,
  connectStage: ConnectStage.dial,
  busyWitness: 'REALITY · path 2 of 3 · Japan',
);

HomeViewState _verifying() => const HomeViewState(
  phase: AirPhase.verifying,
  statusTitle: 'Verifying',
  statusDetail: 'checking the first byte',
  networkLabel: 'Wi-Fi',
  clockLabel: '14:33',
  pingLabel: '789',
  downLabel: '—',
  upLabel: '—',
  protocolLabel: 'Automatic',
  relayLabel: 'Japan',
  exitIp: '',
  exitLocation: '',
  flagCode: 'jp',
  trustTier: TrustTier.bootstrap,
  live: false,
  connectStage: ConnectStage.verify,
  busyWitness: 'REALITY · first bytes · Japan',
);

GoRouter _router(HomeViewState state) => GoRouter(
  initialLocation: '/main',
  routes: [
    ShellRoute(
      builder: (context, routeState, child) => Scaffold(
        extendBody: true,
        body: Stack(
          children: [
            child,
            const Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: DefyxNavBar(),
            ),
          ],
        ),
      ),
      routes: [
        GoRoute(
          path: '/main',
          builder: (context, routeState) => HomeComposition(
            state: state,
            onConnect: () {},
            onOpenServers: () {},
            onRefreshIps: () {},
            onCopyIp: () {},
          ),
        ),
      ],
    ),
  ],
);

class _Device {
  const _Device({
    required this.name,
    required this.physical,
    required this.topInset,
    required this.bottomInset,
  });

  final String name;
  final Size physical;
  final double topInset;
  final double bottomInset;

  double get dpr => 3;
  Size get logical => physical / dpr;
}

const _android = _Device(
  name: '360x800',
  physical: Size(1080, 2400),
  topInset: 24,
  bottomInset: 24,
);

const _iphone = _Device(
  name: '430x932',
  physical: Size(1290, 2796),
  topInset: 59,
  bottomInset: 34,
);

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final bytes = await File(path).readAsBytes();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }

  await load('SchibstedGrotesk', 'assets/fonts/SchibstedGrotesk-VF.ttf');
  await load('GeistMono', 'assets/fonts/GeistMono-VF.ttf');

  // flutter_tester runs with --use-test-fonts, so Material glyphs would be
  // tofu. The icon font ships next to the engine binary, not in the app.
  final sdkCache = File(Platform.resolvedExecutable).parent.parent.parent.parent;
  await load(
    'MaterialIcons',
    '${sdkCache.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
}

Future<(Uint8List, int, int)> _render(
  WidgetTester tester, {
  required HomeViewState state,
  required _Device device,
}) async {
  tester.view.physicalSize = device.physical;
  tester.view.devicePixelRatio = device.dpr;
  tester.view.padding = FakeViewPadding(
    top: device.topInset * device.dpr,
    bottom: device.bottomInset * device.dpr,
  );
  addTearDown(tester.view.reset);

  // flutter_test normally draws shadows as hard fills. Real blurred shadows
  // are part of the surface, and the binding's invariant check expects the
  // flag back at true before the test body returns.
  debugDisableShadows = false;
  try {
    return await _pumpAndCapture(tester, state: state, device: device);
  } finally {
    debugDisableShadows = true;
  }
}

Future<(Uint8List, int, int)> _pumpAndCapture(
  WidgetTester tester, {
  required HomeViewState state,
  required _Device device,
}) async {
  final boundaryKey = GlobalKey();
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) => ProviderScope(
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          routerConfig: _router(state),
          builder: (context, child) =>
              RepaintBoundary(key: boundaryKey, child: child!),
        ),
      ),
    ),
  );
  // One frame to lay out, then long enough for the clear-the-haze sweep and a
  // deterministic ambient drift sample. The ambient loop never settles, so
  // this cannot use pumpAndSettle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1600));

  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundaryKey),
  );
  // Image encoding is engine work outside the fake clock; without runAsync
  // the future completes but the test never tears down.
  final image = await tester.runAsync(
    () => boundary.toImage(pixelRatio: device.dpr),
  );
  final data = await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.png),
  );
  final size = (image!.width, image.height);
  image.dispose();

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();

  return (data!.buffer.asUint8List(), size.$1, size.$2);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadFonts);

  for (final (state, slug) in [
    (_connected(), 'connected'),
    (_connecting(), 'connecting'),
    (_verifying(), 'verifying'),
  ]) {
    for (final device in [_android, _iphone]) {
      testWidgets('$slug on ${device.name}', (tester) async {
        final (bytes, width, height) = await _render(
          tester,
          state: state,
          device: device,
        );
        final out = File('$_outDir/$slug-${device.name}.png');
        // dart:io futures also stall under the fake clock.
        await tester.runAsync(() async {
          out.createSync(recursive: true);
          await out.writeAsBytes(bytes);
        });
        // A blank capture would still be a valid PNG; 20 KB is a floor that
        // only a painted interface clears at these sizes.
        expect(bytes.length, greaterThan(20000));
        expect(width, (device.logical.width * device.dpr).round());
        expect(height, (device.logical.height * device.dpr).round());
        // ignore: avoid_print
        print('wrote ${out.path} (${bytes.length} bytes)');
      });
    }
  }
}
