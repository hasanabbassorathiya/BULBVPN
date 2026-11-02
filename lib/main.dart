import 'dart:async';

import 'package:bulbvpn/firebase_options.dart';
import 'package:bulbvpn/modules/core/log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Diagnostics run in the background. They must never delay the first frame:
  // on a loaded device the support-directory call was observed to take longer
  // than the timeout it was given, and deferring removes the dependency
  // entirely. Lines logged before the file opens are queued in memory.
  unawaited(_startDiagnostics());
  await dotenv.load();
  try {
    // The default app, not a named one: Analytics, Crashlytics, and Remote
    // Config all resolve `Firebase.app()`.
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);
  } catch (e, stack) {
    debugPrint('Firebase init skipped/failed: $e\n$stack');
  }
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  runApp(const ProviderScope(child: App()));
}

Future<void> _startDiagnostics() async {
  try {
    await Log().initializePersistence().timeout(
      const Duration(seconds: 4),
      onTimeout: () {},
    );
  } catch (_) {}
  try {
    await Log().logAppVersion();
  } catch (_) {}
}
