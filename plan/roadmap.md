# BULBVPN roadmap

Forward-looking work after 1.1.0 (build 13). Store mechanics and the exact
commands used for this release live in `docs/store-release-runbook.md`.

## 1. Finish shipping 1.1.0

- **App Store.** Submitted 2026-10-28 (submission `353049b0-4a38-473f-8acc-5bad1e1b6cd7`),
  state WAITING_FOR_REVIEW. Release type is AFTER_APPROVAL, so it goes live
  automatically once Apple approves.
- **Google Play.** Production draft `1.1.0 (13)` is committed. Play classifies
  the app as a draft app, so the first production release must be sent for
  review from Play Console (Production → `1.1.0 (13)` → Send for review).
  After that first approval, later releases can be published through the API.
- Watch App Privacy and the content declarations if either store rejects.

## 2. Monetization

Ads are wired but remote-gated; nothing is served today.

1. Create the Firebase Remote Config boolean `ads_enabled = true` when the
   switch should flip. The key defaults to `false` and is read on launch, so
   later toggles need no app update.
2. Before enabling inventory, replace every test identifier:
   - `AndroidManifest.xml` → `com.google.android.gms.ads.APPLICATION_ID`
   - iOS `Runner/Info.plist` → `GADApplicationIdentifier`
   - live banner unit IDs in `lib/modules/monetization/ad_config.dart`
   - set `useTestAds = false` there as well
3. Confirm the UMP consent form and the Settings privacy-options link work in
   EEA/UK. Add an ATT prompt only if personalized ads are turned on.
4. Premium tier: choose the entitlement and what it gates, then wire
   RevenueCat. The old RevenueCat keys were removed from `PrivateApp`; do not
   put them back in source.

## 3. IR-resilience follow-ups

- Mobile-data matrix: the test phone has no SIM as of 2026-10-28. Verify
  MCI/Irancell, CGNAT, and DPI behaviour before trusting the Wi-Fi results.
- Relay scoring: persist and decay scores across launches; cap probe fan-out
  when on battery.
- SoftEther: tune the watchdog and rotate hubs when a country's relays die
  together.
- Apple tunnels: measure extension memory and battery on long sessions;
  revisit the IPv6 blackhole if Apple requirements change.

## 4. Engineering debt

- Crashlytics and Analytics initialize against the default Firebase app while
  only the named `bulbvpn` instance exists. Verify collection or move both to
  the named app.
- Analyzer warning: `unawaited_return_in_try_block` in
  `lib/modules/speed_test/application/services/upload_measurement_service.dart`.
- macOS Runner fails to link the tunnel with undefined Flutter symbols from
  the Firebase pods. The iOS targets are unaffected.
- Add widget tests for ad gating: Remote Config false/true, test IDs vs live
  IDs, and Settings visibility.
- Build-number discipline: bump `pubspec.yaml` and the iOS
  `CURRENT_PROJECT_VERSION` together, and never reuse an uploaded build
  number.

## 5. Distribution and release engineering

- Decide the branch policy. `redesign/production-grade` has carried the store
  releases; feature branches currently land there.
- Consider a CI pipeline around `scripts/build_release.sh`, `asc`, and `gpd`.
- Refresh screenshots for current device sizes, add localizations, and keep
  the brag video (`store/video/brag-1.1.0.mp4`) as the promo asset.
