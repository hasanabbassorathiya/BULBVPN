// Renders the Metered terms family — the settings card, the routing card, the
// connection log — at the shipped device classes, so each face's own print
// (the head, the section rules, the right-hand values and the one switch the
// plate cuts) is looked at rather than only asserted on.
//
// The routes are mounted inside the real shell, because the tear at the foot of
// the card is what each face has to pad itself against; a capture that printed
// the list on a bare scaffold would hide the row the nav covers.
//
// Run: flutter test tool/design/metered_terms_test.dart
// Output: .impeccable/review/<face>-<size>.png

import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:bulbvpn/core/theme/app_theme.dart';
import 'package:bulbvpn/modules/settings/presentation/screens/logs_screen.dart';
import 'package:bulbvpn/modules/settings/presentation/screens/routing_screen.dart';
import 'package:bulbvpn/modules/settings/presentation/screens/settings_screen.dart';
import 'package:bulbvpn/shared/metered/metered_shell.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _dir = '.impeccable/review';

const _faces = <String, Widget>{
  'terms': SettingsScreen(),
  'routing': RoutingScreen(),
  'logs': LogsScreen(),
};

/// Faces whose Android branch is the one being reviewed. This host is macOS, so
/// without the override the routing plate would print the Apple copy and an
/// empty card — a plate of the branch nobody ships it for.
const _androidFaces = <String>{'routing'};

const _sizes = <String, Size>{
  '360x800': Size(1080, 2400),
  '430x932': Size(1290, 2796),
};
const _dprs = <String, double>{'360x800': 3.0, '430x932': 3.0};

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

  for (final sizeKey in _sizes.keys) {
    for (final face in _faces.entries) {
      testWidgets('${face.key} face at $sizeKey', (tester) async {
        tester.view.physicalSize = _sizes[sizeKey]!;
        tester.view.devicePixelRatio = _dprs[sizeKey]!;
        addTearDown(tester.view.reset);

        debugDisableShadows = false;
        if (_androidFaces.contains(face.key)) {
          debugDefaultTargetPlatformOverride = TargetPlatform.android;
        }
        final boundaryKey = GlobalKey();
        try {
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light,
                home: RepaintBoundary(
                  key: boundaryKey,
                  child: Scaffold(
                    body: MeteredShell(
                      segments: meteredTabs,
                      active: 3,
                      onSelect: (_) {},
                      child: face.value,
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

          expect(
            tester.takeException(),
            isNull,
            reason: '${face.key} $sizeKey',
          );

          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(boundaryKey),
          );
          final image = await tester.runAsync(
            () => boundary.toImage(pixelRatio: _dprs[sizeKey]!),
          );
          final data = await tester.runAsync(
            () => image!.toByteData(format: ui.ImageByteFormat.png),
          );
          image!.dispose();

          final path = '$_dir/${face.key}-$sizeKey.png';
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
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
}
