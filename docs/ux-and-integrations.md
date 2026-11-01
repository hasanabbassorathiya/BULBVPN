# Integrations and the perceived-wait redesign

What changed in 1.2.0 (build 19), why it changed, and how to verify it. Each
entry is a problem observed in the shipped app followed by the solution now in
the tree. Design intent lives in `DESIGN.md`; this file is the engineering
ledger.

## Integrations

### Firebase was initialized as a named app

**Problem.** `main.dart` called `Firebase.initializeApp(name: 'bulbvpn')`.
Every `Firebase.app()` lookup (the default app) then threw, so Analytics never
logged, Crashlytics never recorded, and the Remote Config fetch had to fall
back to a named instance. The failure was silent: the app ran, the console
stayed empty.

**Solution.** The default app is initialized with
`DefaultFirebaseOptions.currentPlatform`. `FlutterError.onError` and
`PlatformDispatcher.instance.onError` now record fatal errors to Crashlytics,
and Crashlytics collection is on in release builds only. `AdsRemoteConfigNotifier`
still prefers `Firebase.app()` and falls back to the named `bulbvpn` app for
builds that register it separately (`lib/modules/monetization/ads_remote_config.dart`).

**Verify.** Release build → Firebase console → Analytics DebugView or
Realtime shows `session_start`; Crashlytics shows the app under the same
project. `adb logcat | grep '\[Ads\]'` prints `remote ads_enabled=…`.

### Analytics observer attached to the wrong object

**Problem.** The analytics observer was passed to `MaterialApp.router
(navigatorObservers: …)`, which does not accept that argument. It failed
analysis and, once removed, would have left screen tracking off.

**Solution.** The observer is created once in `routerProvider` and passed to
`GoRouter(observers: [observer])` (`lib/app/router/app_router.dart`). Custom
events are in `lib/shared/services/firebase_analytics_service.dart`:

| Event | Fired when |
|---|---|
| `vpn_connect_attempt` | each engine dial (`connection_method`: reality / softether / openvpn) |
| `vpn_connected` | tunnel proven, with method, relay, elapsed seconds |
| `vpn_disconnected` | user or system closes the tunnel |
| `vpn_failed` | every engine on the queue failed; also a non-fatal Crashlytics record |
| `connection_method_changed`, `server_selected` | picker changes |
| `premium_paywall_viewed`, `premium_purchase`, `premium_restore` | monetization funnel |
| `support_opened` | Support row tapped (`channel`: teleform) |

### Ads ship installed but off

**Problem.** AdMob inventory must exist before it is switched on, and it must
never appear for a user until the inventory is real and the switch is
deliberate.

**Solution.** The banner is built but gated by `adsEnabledProvider`, a
`StateNotifierProvider<bool>` seeded **false**. On launch it fetches the
Firebase Remote Config key `ads_enabled` (default `false`, timeout 10 s, debug
builds refetch every launch, release honours the 30-minute throttle) and
publishes `fetchAndActivate()`'s value. A failed or offline first fetch leaves
ads off; later launches reuse the last activated value, so the console flag
takes effect without an app update. Builds still carry Google's test IDs and
`useTestAds = true`; live IDs are a code change plus a new release, documented
in `docs/store-release-runbook.md`.

**Verify.** Firebase Remote Config → `ads_enabled = false` → no banner on
repeated launches. Publish `true`, relaunch twice → banner appears (test ad).

### RevenueCat is wired per platform, and says so when it is not

**Problem.** A premium screen that shows a price and a buy button when no store
key is configured turns a missing build secret into a lying UI.

**Solution.** `purchases_flutter` is configured from `REVENUECAT_APPLE_KEY` /
`REVENUECAT_GOOGLE_KEY` (`.env` or `--dart-define`), entitlement `premium`.
With no key the state is `PremiumStatus.unconfigured` and the paywall states
*"Store setup is not live in this build"* rather than a price. Successful
purchase and restore log analytics events. This build has an Apple key; the
Google key is absent, so Android premium honestly reports unconfigured until
the key is supplied.

**Verify.** iOS: paywall shows plans and a price from the store. Android:
paywall shows the unconfigured notice and no currency glyph.

### Support moves to Teleform; diagnostics leave the surface

**Problem.** In-app diagnostics and a support mailout are noise for normal
users, and the Teleform dashboard is login-gated so it cannot be linked
directly.

**Solution.**
- `AppLinks.supportUrl` reads `SUPPORT_URL` from `.env` or
  `--dart-define=SUPPORT_URL=…`. When empty the Support row is **not rendered**
  — no dead link. When set, the row opens the public form (or its Telegram
  hand-off) and logs `support_opened`.
- The Diagnostics section is gone from Settings. The log viewer remains
  reachable by long-pressing the Version row, which is documented for support
  use and invisible to ordinary browsing.
- `.env.example` documents both the support URL and the RevenueCat keys with
  no secrets.

**Verify.** Build with no `SUPPORT_URL` → Settings lists no Support row and no
Diagnostics section; long-press Version opens Logs. Build with the URL set →
Support row appears and opens the public form.

## The perceived-wait redesign

### Problem

On a censored network a connect can spend 20–40 seconds rotating paths before
one carries data. The old screen said *"Connecting"* and nothing else. Two
failures followed: the app looked frozen, and a progress-shaped lie (a
percentage or a fake bar) would have been worse — the wait is not linear and
the app cannot know how long it will take.

### Solution: show real work, not fake progress

Four psychological levers, all fed by measurements the controller already has:

1. **Labor illusion.** `ConnectStage` names the actual phase — `wake` (engine
   binding and pre-flight), `dial` (a specific relay is being attempted),
   `verify` (a first byte is being proven). The caption is never a spinner
   where a state word belongs.
2. **Goal gradient.** The trace draws three named stops on one hairline; each
   stop fills at 420 ms easeOutCubic as the phase completes, so progress is
   visible and finishable, not infinite.
3. **Preparedness.** At rest the detail line reads
   `prepared · {last good relay on this network}` from `RelayMemory`, and falls
   back to `path closed · {relay}` when no history exists. The app looks ready
   before the tap.
4. **Honest witness.** A mono line under the stops repeats what the controller
   published: `REALITY · path 2 of 3 · Germany`, then `REALITY · first bytes ·
   Germany`. Attempt counts are capped by the number of paths actually queued
   and in scope, so `path 2 of 3` is true. Nothing is smoothed, rounded up, or
   invented.

Supporting motion: the idle aperture breathes ±1.4% over 5.2 s (readiness, not
another loading animation); the busy arc keeps sweeping; haptics mark the
verification phase (selection click) and the proven tunnel (medium impact).
When the tunnel closes or fails, the trace clears and the prepared label
reloads for the current network. Reduced motion stops the breath and the arc
and pins the aperture, but the stage, witness, and copy still change — state
changes stop being decorative, not informative.

### What was deliberately not done

- No percentage, countdown, ETA, or simulated progress bar.
- No placeholder speeds or pings; unknown values stay `—`.
- No second accent, card grid, or decorative gradient (see `DESIGN.md` §9).
- No hiding of public-relay trust labels while the trace is on screen.

### Verify on device

1. Connect on Wi-Fi: stage moves wake → dial → verify, witness names the
   engine and relay, haptic fires at verify, status word switches to
   `Connected` under 260 ms.
2. Force a failure (block the relay or use a filtered network): the trace
   clears on `Blocked` and the idle line returns to `prepared · …`.
3. Relaunch: idle shows the last good relay for that network.
4. Enable "Remove animations": aperture is static, no arc or flow lines, trace
   and copy still update.

## Version and artifacts

- `pubspec.yaml`: `1.2.0+19`. iOS `CURRENT_PROJECT_VERSION = 19` in all nine
  `project.pbxproj` entries.
- Release notes: tunnels that keep trying, honest connect states, support via
  Teleform when configured, ads off by default.
- No new permission is added in this round. Analytics, Crashlytics, and the
  AdMob SDK were already dependencies; re-check Play Data Safety and App
  Privacy before `ads_enabled` is flipped to true.
