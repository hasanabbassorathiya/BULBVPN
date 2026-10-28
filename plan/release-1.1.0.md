# Release 1.1.0 — build 13

Date: 2026-10-28

## Artifacts

| Platform | File | Size | Version |
|---|---|---|---|
| Android | `build/app/outputs/bundle/release/app-release.aab` | 48.9 MB | 1.1.0 (13) |
| iOS | `build/ios/ipa/BULBVPN.ipa` | 37.0 MB | 1.1.0 (13) |

Both were built from the working tree on `feat/ir-resilience-lantern`.

## What ships

- SoftEther-first connection for restrictive networks, with dead-country
  escape instead of an endless Connecting state.
- Live download/upload counters from the Apple tunnel extensions, and
  automatic refresh of ping, BEFORE IP, and device state when the network
  changes.
- Relay sheet grouped by country, fastest country first and relays sorted by
  measured ping inside each country.
- Diagnostics logs hidden outside debug builds.
- Ads behind Firebase Remote Config `ads_enabled`, default `false`.

## Store state at submission

### App Store Connect

- App: `6822892688` (BULBVPN - Free VPN Proxy)
- Version: `1.1.0`, id `fd28c159-3e87-4c5b-93c7-2d1d0a458429`
- Build: `13`, id `37c2175a-cfbb-47af-b4a7-a7d6907a6a29`, VALID
- Submission: `353049b0-4a38-473f-8acc-5bad1e1b6cd7`,
  WAITING_FOR_REVIEW since 2026-10-28T04:30:32Z
- Release type: AFTER_APPROVAL (goes live after approval)
- App Preview: `IPHONE_55`, brag video 1080x1920, 20 s,
  asset `58400019-6ad1-8490-8127-23efffc3609e`, state COMPLETE at submission
- `whatsNew` is empty: Apple does not allow it on a never-released app. It is
  a warning only.

### Google Play

- Package: `app.bulbvpn.com`
- Production track: draft release `1.1.0 (13)`, versionCode 13
- The bundle is uploaded and the draft is committed. Play rejects any
  non-draft release while the app is a draft app, so the first production
  release must be sent for review from Play Console. This is a Google
  restriction on first releases, not a missing configuration.
- Promo video: Play only accepts a YouTube URL, so the brag video cannot be
  attached as a file there. It is stored at `store/video/brag-1.1.0.mp4` and
  is attached to the App Store listing as an app preview.

## Verification

- `flutter test` 19/19.
- `flutter analyze` clean apart from the pre-existing
  `unawaited_return_in_try_block` warning in the speed test service.
- iOS device build, signed IPA, and Android release AAB all built with the
  release configuration.
- App Store version validation: 0 errors, 1 warning (`whatsNew`), 1 info
  (App Privacy state cannot be read through the public API).

## Follow-ups

Tracked in `plan/roadmap.md`: Play first-release console action, ads
enablement checklist, mobile-data testing, Crashlytics app-name mismatch, and
the macOS link failure.
