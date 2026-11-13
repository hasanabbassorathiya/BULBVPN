# BULBVPN — VPN issues log

Every connection problem hit while shipping SoftEther / OpenVPN over
VPN Gate. Grouped by network, then by platform. Status is as of
**2 Nov 2026** — every row was re-checked against source in the
verification pass near the end of this file; device claims still date from
**20 Oct 2026** (country-pick SoftEther escape verified on Android; iPad
SoftEther Connected after VPN profile Allow) because no hardware was
attached for the re-check.

**One exception, 7 Nov 2026:** Android no longer dials SoftEther or OpenVPN at
all. Every row below whose fix says "fallback", "fall through" or names a
SoftEther budget describes Apple behaviour and the Android history; the
Android half of those fixes is gone. See `connection-solutions.md` §8 and §13.

The step-by-step Android IR method lives in
[`instruction.md`](instruction.md). This file is the issue catalog.

---

## Working path (what finally stuck)

| Layer | Choice |
|---|---|
| Android dial | **REALITY/XHTTP only** — community pool plus relays the user imported, each adopted only after a real transfer through the TUN. 100 s budget, 12-dial cap. No SoftEther, no OpenVPN |
| Apple first dial | SoftEther TLS on TCP 443 (hub `VPNGATE`, user/pass `vpn`/`vpn`) |
| Apple fallback | OpenVPN TCP 443 last, 0–1 servers |
| Preferred SoftEther hosts | `219.100.37.105` / `public-vpn-139.opengw.net`, `.179` / `187` (`.192` is not in the catalog and was dropped). Apple only |
| Apple profile marker | `# bulb-host` / `# bulb-sni` — extension never starts OpenVPNAdapter for that profile |
| SoftEther dial budget | Full 28s (not an 8s cap) — Apple only; nothing on Android reaches it |

---

## By network

### Iran — mobile data (Irancell, Hamrah Aval)

| Issue | Symptom | Root cause | Fix / status |
|---|---|---|---|
| Handshake killed on network flicker | App dies or fails the moment TUN comes up | Android reports a new `cellular`+`vpn` network; old code called disconnect while `nativeConnect` was still inside SoftEther → `SIGSEGV` in `libsoftether_jni.so` | Do not tear down `nativeConnect` from another thread; `nativeRequestStop` only while in flight. **Fixed.** |
| Green Connected, dead tunnel | UI Connected, `nread_max=0B`, `nc 1.1.1.1 443` times out | SoftEther data loop kept the pre-DHCP TUN fd after `establish()` created `tun1` | Set the routed fd *before* `softether_connect` returns; do not rely on `softether_replace_tun_fd` alone. **Fixed.** |
| Session socket into own tunnel | Second SoftEther dial after default route returns `-4`, no second “TLS connected” | `VpnService.protect()` alone was not enough on Android 11; TLS went into TUN | Exclude the VPN app from the routed interface so the process stays on `rmnet0`. **Fixed.** |
| OpenVPN UDP stall | Connect hangs or never AUTH | Carrier / middlebox drops or stalls UDP OpenVPN | SoftEther TLS/TCP 443 first; OpenVPN TCP 443 only as fallback. **Mitigated.** |
| Carrier DNS black-hole | `*.opengw.net` never resolves | Carrier DNS | Resolve / probe by IP; keep SNI as the host name for TLS. **Mitigated.** |
| BEFORE IP geolocated as Baku | UI / IP DB shows Azerbaijan while radio is Irancell | Irancell CGNAT (`26.54.x` etc.) mis-geolocated | Trust radio (`rmnet0`, `mtnirancell`), not the city name. **Documented, not a bug.** |
| SoftEther AUTH then routed retry fails | Auth to e.g. `150.40.105.5`, DHCP `10.211.1.x`, then `-4`/`-5`/`-12`/`-100` on other relays | Routed retry / dead relays | Fall through SoftEther pool then OpenVPN. On one Irancell pass OpenVPN `27.92.236.186:1654` carried traffic (HTTP to `1.1.1.1` ray `…NRT`). **Working with fallback.** |

Confirmed IR mobile success class: Connected, real download (~6 KB/s+), exit shown as Japan (e.g. `27.92.236.186`).

### Iran — Wi‑Fi

| Issue | Symptom | Root cause | Fix / status |
|---|---|---|---|
| Wi‑Fi “works”, mobile does not | Same build connects on Wi‑Fi, fails on LTE | Network-change callback fires later on Wi‑Fi, so SoftEther often finished before disconnect; mobile flicker is immediate | Same Android SoftEther lifecycle fixes as above. **Fixed.** |
| OpenVPN VERIFY OK, no CONNECTED | TCP connects, cert OK, then 22s timeout | Live TCP listeners that never PUSH; VPN Gate churn | Prefer SoftEther; rank OpenVPN toward last-good / `219.100.37.0/24`. **Mitigated.** |
| Manual L2TP/IPsec from VPN Gate worked on iOS | User copied L2TP IP + `vpn`/`vpn` + secret; SoftEther OpenVPN apps failed | System L2TP path ≠ OpenVPN 3 / SoftEther client path | App does not implement L2TP; SoftEther TCP 443 in the packet tunnel is the in-app equivalent for IR. **By design.** |

### Global / non-IR (and mixed test networks)

| Issue | Symptom | Root cause | Fix / status |
|---|---|---|---|
| Dead OpenVPN listeners | `VERIFY OK` then timeout on many hosts | VPN Gate relays accept TCP and stall after cert | SoftEther first; OpenVPN backup with short rotation. **Mitigated.** |
| Proven host disappears | Last CONNECTED IP (e.g. `219.100.37.196`) not in next list | Relays rotate / go quiet | Keep preferred SoftEther set; last-good pin for OpenVPN ranking. **Mitigated.** |
| Random high ports | Dials to 1220 / 1467 / 1527 hang | Non-443 OpenVPN often dead from IR and elsewhere | OpenVPN limited to TCP 443. **Fixed.** |
| Exit country/flag mismatch | Mac UI showed Korean flag labeled Japan | UI inferred the country from the picker / fastest server instead of the session that actually came up | `RelayTarget` + `connectedRelayProvider`; UI reads only the native relay and says “Connected relay” when metadata is missing. **Fixed.** |
| Other-country pick hangs on Connecting | SoftEther plan RU-only → probe 0/5 → skip SoftEther → OpenVPN retries the same dead hosts until the 55s budget | Strict SoftEther refused to leave the picked country; OpenVPN still dialled “unprobed” dead listeners | SoftEther plan appends proven / measured escape relays after the country list; OpenVPN fail-fast when strict probe finds 0 reachable; Android SoftEther now TCP-probes first. **Fixed in controller.** |
| Competing system VPN | SoftEther TCP probes all fail while another VPN owns the default route | e.g. OstrichVPN Connected on Mac while BULBVPN dials | Disconnect other VPNs before testing BULBVPN. **Documented.** |
| BEFORE vs AFTER confusion | Users think BEFORE is “wrong country” | CGNAT / upstream transit | Show AFTER as the checkable exit; document BEFORE as unreliable. **Documented.** |

---

## By platform

### Android

| Issue | Symptom | Root cause | Fix / status |
|---|---|---|---|
| SoftEther cancelled at ~8s | `connect code -12` `SOFTETHER_ERR_CANCELLED` ~8074ms, then crash | Budget capped at 8s; DHCP needs ~9s on these relays | `connectWithDeadline` uses full `budgetMs` (28s). **Fixed.** |
| fdsan double-close in `closeTun` | Process abort after cancel | Closing the same TUN fd twice | Probe with `ParcelFileDescriptor.fromFd` (dup) before `adoptFd` close. **Fixed.** |
| OpenVPN AUTH stall (2.6) | Sits in AUTH forever | ics-openvpn 2.6 ignores plain `cipher AES-128-CBC` without compat lines | `compat-mode 2.4.0`, `data-ciphers AES-128-CBC`, `provider legacy default`, inline `<auth-user-pass>`. **Fixed.** |
| OpenVPN watchdog too short | Live handshake cut at 10s | Watchdog < real AUTH time | Watchdog 18s. **Fixed.** |
| Native libs not extracted | SoftEther / OpenVPN native bits missing | Android  packing | `useLegacyPackaging = true`, `extractNativeLibs=true`. **Fixed.** |
| SoftEther before OpenVPN missing | Fresh install: Android failed while Mac SoftEther worked | Dial order OpenVPN-first | SoftEther first on Android too. **Fixed** (confirmed 06:53). |
| Network callback during connect | SIGSEGV / instant fail on LTE | See IR mobile | Hold / ignore tunnel-up as “drop” during handshake. **Fixed.** |
| Wrong TUN after DHCP | Connected UI, no traffic | See IR mobile | Unrouted learn → routed session with app exclusion. **Fixed.** |

### iPhone (iOS)

| Issue | Symptom | Root cause | Fix / status |
|---|---|---|---|
| OpenVPN VERIFY OK → timeout | No `SSL Handshake` / PUSH / CONNECTED | Dead or non-PUSH OpenVPN listeners; TLS 1.0 pin required when OpenVPN *does* work | SoftEther first via marker profile; OpenVPN keeps TLS 1.0 min=max + AES-CBC + no client cert. **Fixed path: SoftEther.** |
| OpenVPN needs TLS 1.0 | Without pin, modern TLS fails VPN Gate SoftEther OpenVPN | Server offers TLS 1.0 / CBC suites | Patch OpenVPNAdapter (`forceCiphersuitesAESCBC`, TLS 1.0). **Fixed for OpenVPN path.** |
| `sslDebug=3` jetsams sibling iPad | Cannot leave debug at 3 for shared builds | Memory / log volume on iOS 16 extension | Keep `sslDebug=1` in shipping providers. **Fixed.** |
| SoftEther in extension | Need IR-reliable path without L2TP | OpenVPNAdapter alone insufficient | `libsoftether` + socketpair fd adapter + `createTCPConnection` + bind last live `en*`/`pdp_ip*`; `# bulb-host` / `# bulb-sni`. **Fixed.** |
| Tunnel socket into VPN | SoftEther TLS loops into utun | Must not use sandbox utun for control plane the same way | TCP via `NEProvider.createTCPConnection`; bind physical iface; `softether_set_default_route(false)`. **Fixed.** |
| Extension timeout | SoftEther hangs forever | No assigned IP | Poll `softether_get_assigned_ip` up to ~12s; extension ~45s; Apple watchdog ~50s; plain-password retry if connect ≠ 0. **Fixed.** |
| Dial order OpenVPN-first | Fresh install: iPhone failed, Mac SoftEther succeeded | Controller order | SoftEther before OpenVPN. **Fixed** (confirmed). |
| Wireless screenshot / capture | Cannot grab Connected UI over CoreDevice-only | No USB; `idevicescreenshot` / Screen Recording limits; `screenshotOff` blanks caps | Capture needs USB or temporary `screenshotOn`; shipping stays secure. **Open for automation.** |

### iPad (iOS 16.7.x)

| Issue | Symptom | Root cause | Fix / status |
|---|---|---|---|
| Same OpenVPN stall as iPhone | VERIFY OK, timeout | Same as iPhone | SoftEther first. **Fixed.** |
| `sslDebug=3` jetsam | Extension killed under memory pressure | Do not ship level 3 | `sslDebug=1`. **Fixed.** |
| `virtualInterface` unavailable | SoftEther TCP path APIs differ | iOS 18+ API not on iOS 16 | Use socketpair + `createTCPConnection`, not virtualInterface. **Fixed.** |
| Empty appex version | installd rejects extension | `MissingBundleVersion` | Appex `CFBundleVersion` non-empty and matching app. **Fixed.** |
| `devicectl` invisible | Cannot use modern devicectl install | Older iPad / pairing | Use `flutter` / `ios-deploy`. **Documented.** |
| SoftEther-first missing | Fresh install failed with Mac succeeding | Dial order | SoftEther first. **Fixed** (confirmed). |

### macOS

| Issue | Symptom | Root cause | Fix / status |
|---|---|---|---|
| OpenVPN VERIFY OK → DISCONNECTED | Same stall as Apple mobile | Dead OpenVPN listeners | SoftEther first (already preferred on Mac earlier). **Working.** |
| utun SoftEther fails in NE sandbox | Native SoftEther cannot drive sandbox utun like Android TUN | Platform limit | Platform-rewritten iOS SoftEther archive + fd adapter (socketpairs), same as iOS. **Fixed.** |
| Wrong OpenSSL link | Duplicate crypto / link errors | SoftEther static lib already embeds OpenSSL | Do not also link separate libssl/libcrypto. **Fixed.** |
| x86_64 slice | Build noise / wrong arch on Apple Silicon | Config | `EXCLUDED_ARCHS = x86_64` on macOS 26 configs. **Fixed.** |
| Codesign / entitlements | Install / extension fails | Unexpanded `$(AppIdentifierPrefix)`, `--deep` | Extract entitlements before modify; no `--deep`. **Fixed.** |
| UI cropped / narrow | Window ~800×632 cuts brand/status | Layout max width / window size | Responsive Mac UI still pending product work. **Open (UI).** |
| Flag wrong for Japan | Korean flag, Japan label | UI geolocation mapping | **Open.** |

### Windows

| Issue | Symptom | Root cause | Fix / status |
|---|---|---|---|
| No attached host | Cannot verify or upload | No Windows machine in the lab | OpenVPN 2.6 path with same compat lines as Android is implemented; SoftEther Zig libs exist but untested here. **Untested.** |
| OpenVPN 2.6 AUTH | Same as Android without compat | Missing `compat-mode` / `data-ciphers` / legacy provider | `configForCurrentEngine` injects 2.6 lines. **Believed fixed, not device-verified.** |

---

## Cross-cutting protocol issues

| Issue | Detail | Status |
|---|---|---|
| Two engines, one profile | Android/Windows OpenVPN 2.6 needs compat lines; Apple OpenVPN 3 rejects them — must strip on Apple | **Fixed** (`configForCurrentEngine` / strip) |
| SoftEther ≠ OpenVPN “fix” | VPN Gate is SoftEther; OpenVPNAdapter and SoftEtherZig are different clients | SoftEther client is the reliable IR path |
| TLS 1.0 only for Apple OpenVPN | `TLSv1.0/TLS-DHE-RSA-WITH-AES-256-CBC-SHA` when OpenVPN works | SoftEther path uses TLS 1.2 (e.g. AES-256-CBC) on Android confirmation |
| Dial order | OpenVPN-first: only Mac SoftEther path survived fresh install | SoftEther-first on all attached platforms **Fixed** |
| Watchdogs | Apple ~50s / extension ~45s; Android SoftEther 28s; Android OpenVPN 18s | Tuned; do not reintroduce 8s SoftEther cancel |
| Screen security vs QA | `screenshotOff` while Connected blanks captures (FLAG_SECURE / black iOS) | Temporary `screenshotOn` for marketing shots only; shipping stays off |

---

## Error codes / log lines (quick index)

| Signal | Meaning |
|---|---|
| SoftEther `-4` | Connect / routed failure (often socket into tunnel or dead peer) |
| SoftEther `-5`, `-100` | Relay pool failures (treat as miss, rotate) |
| SoftEther `-12` `SOFTETHER_ERR_CANCELLED` | Budget cancelled too early (was 8s bug) |
| OpenVPN `VERIFY OK` then silence | Listener accepted TCP/cert, never finished PUSH |
| `startTunnel timed out waiting for CONNECTED` | Apple OpenVPN path miss (~22s historically) |
| `nread_max=0B` | SoftEther reading wrong / dead TUN |
| `SIGSEGV` in `libsoftether_jni.so` | Disconnect during `nativeConnect` |
| fdsan abort in `closeTun` | Double-close TUN fd |
| jetsam of PacketTunnel / VPNExtension | Often `sslDebug=3` on iOS 16 |

Useful tags: `BulbSoftEther`, `libsoftether`, `flutter`. Apple: app `tmp/bulb.log`, group `Library/Caches/bulb-tunnel.log`.

---

## Truthful state and long-session hardening (20 Oct 2026)

| Problem | Root cause | Durable fix |
|---|---|---|
| Stale “Connected” after a drop | UI trusted the engine flag and a persisted session independently | Native liveness is authoritative; engine reconciliation drops the relay on 2–3 misses; resume clears a dead persisted session |
| Picker country ≠ exit country | Connect path and UI each chose a relay | One `RelayTarget`; `connectedRelayProvider` is written only by the dial that succeeded; UI shows that relay |
| Other-country pick hung on Connecting | Strict SoftEther was country-only; when TCP probe found 0 reachable, OpenVPN dialled the same dead hosts until the budget expired | SoftEther plan keeps the pick first, then appends proven / measured SoftEther as escape; OpenVPN fail-fast when strict probe finds 0 reachable; Android SoftEther TCP-probes first. Verified 20 Oct on OnePlus (US pick → CONNECTED SoftEther `219.100.37.105` JP) |
| Endless reconnect loop | No budget, no manual-disconnect memory | 3 attempts at 2s / 8s / 20s; reset on success or manual connect; skipped after manual stop and after OS `revoked`; offline postponement refunds the attempt |
| Relay switch during a dial lost | `_connect` returned early while busy | Manual switch is queued (`_connectQueued`) and runs after the in-flight attempt unwinds |
| Android use-after-free on stop | `nativeConnect`/TUN teardown raced the service thread | All handle/fd access under `sessionLock`; `@Volatile` `client`/`tunFd`; deferred destroy while connecting |
| Same tunnel reported as a new relay | Service only checked `running` | Same `activeHost` returns “already running”; a different host returns `relay_changed` so Dart tears down and re-dials |
| Dial kept running after app gave up | MainActivity 45s timeout returned but did not stop native | Timeout now calls `requestStop("timeout")`; the late handshake cannot install a tunnel Dart counts as failed |
| Apple retry leaked socketpairs | A failed `connect` left the app-side ends open before the plain retry | Failed attempts close both tunnel socketpairs; a partial socketpair failure closes the half it opened |
| Android service destroyed a newer instance | `onDestroy` unconditionally nulled the static `instance` | Identity-checked teardown; the old instance can no longer clobber the new one |
| Android reported the carrier IP as the exit | The app is excluded from its own TUN for reliability, so an in-app exit-IP lookup leaves directly | Android no longer presents the carrier address as the exit; it shows the connected relay and “not measured on this device” |
| A late handshake could resurrect a manual disconnect | `_connect` did not re-check the user’s intent after a long await | Success is rejected and the native session torn down when `_manualDisconnect` or a queued relay is set; OpenVPN/Apple paths do the same |
| Timed-out handshake leaked its native client | `shutdown` deferred destroy while `connectInFlight`, but nothing destroyed it afterwards | `shutdown` schedules `releaseAfterHandshake`; the client and fds are destroyed once `nativeConnect` unwinds |
| `flutter run` could not find the APK | `android/build.gradle.kts` omitted Flutter’s build-directory redirect | Restored `rootProject.layout.buildDirectory = ../../build` and subproject dirs |
| iOS Debug could not find SoftEther headers/lib | `VPNExtension` Debug config lacked the bridging header, header/library paths and `-lsoftether` (only Release/Profile had them) | Added the same settings to Debug |

---

## Verification pass (2 Nov 2026)

Every row above was re-checked against the current source. No phone was
attached (`adb devices` empty, `flutter devices` finds only the Mac and
Chrome, the iPhone needs Developer Mode over wireless and errors with code
-27), so this pass proves *the fix is still in the tree* — it does not
re-prove any tunnel behaviour on a radio.

### Machine-checked, and green

`test/docs_vpn_issues_contract_test.dart` is new: 27 assertions over the
rules this catalog says must not come back, because prose enforced them.
It pins the Android 28s SoftEther budget against the old 8s `-12` cancel,
the 18s per-attempt watchdog, SoftEther dialling before the OpenVPN stage,
the 2.6 `compat-mode` / `data-ciphers` / `provider legacy` lines *and*
their Apple strip, `# bulb-host` / `# bulb-sni` on both sides of the
bridge, `sslDebugLevel = 1` with `= 3` forbidden, `extractNativeLibs` and
`useLegacyPackaging`, the identity-checked `onDestroy`,
`requestStop("timeout")`, `sessionLock` + `@Volatile` +
`releaseAfterHandshake`, the socketpair close on a failed Apple attempt,
TCP-443 pinning, strict-selection fail-fast, the `escape` source, the
2-miss watchdog, the carrier address never being labelled the exit, a
network change while Connected forcing a clean three-engine redial, the
data-plane proof being cleared in `_disarmWatchdog`, and the 2-per-`/24`
relay spread.

Alongside it: `flutter analyze` clean but for one pre-existing
`unawaited_return_in_try_block` warning in the speed-test upload service;
`flutter test` **165 passed**; `:app:compileReleaseKotlin` and
`:app:compileDebugKotlin` **BUILD SUCCESSFUL** (the previous pass had to
record these edits as uncompiled — that caveat is retired). The Apple
tunnel sources pass `swiftc -parse`, which is syntax only: nothing was
linked or run.

### Measured, not asserted

The bundled REALITY relays were probed end-to-end through Xray at
`2026-11-01T11:39Z`: **8 of 9 healthy**, with `community-ee-5` failing on a
TLS reset — a relay that has left the internet, correctly excluded by the
health file rather than trusted. This is the only real data-plane evidence
in the pass. Note that `relay-health.yml` and `ci.yml` exist only on
`feat/greatest-vpn`; `main` carries just `build.yml`, so the three-hourly
probe cannot fire on the default branch until this work merges.

### What this pass could not verify

Every row whose proof is a radio, a TUN, or a second VPN: the IR-mobile
SIGSEGV class, the wrong-TUN-after-DHCP class, `nread_max=0B`, carrier DNS
black-holes, the Baku mis-geolocation, OpenVPN `VERIFY OK`-then-silence,
the competing-system-VPN case, all iPhone / iPad / macOS / Windows Connect
claims, and the six items under "What is still open". Source presence is
not a tunnel. **0 of 6 open items closed.**

### New defects this pass found

1. **`.env` is committed while also listed in `.gitignore`.**
   `git ls-files .env` returns it (last touched by `c772012`), so the
   ignore rule has no effect and the next secret added to that file will
   be committed believing it is protected. The current contents are not a
   leak — Firebase API keys and app IDs, RevenueCat *public* SDK keys, and
   a public `t.me` handle, all client-side by design, with no keystore
   password or bot token present.
2. **The relay catalog is fetched and trusted unsigned.**
   `docs/research-vpn-architecture.md:349` requires "never trust an
   unsigned server list" with Ed25519 verification and expiry rejection;
   the only match for `signature` anywhere in `lib/modules/core/` is an
   unrelated prose comment in `reality_engine.dart:213`. A CDN or upstream
   compromise can still redirect the tunnel. The REALITY health file is
   the one channel that is id-keyed and cannot inject an unknown relay.
3. **iOS never calls `requestTrackingAuthorization` directly.**
   Nothing in `lib/`, `ios/Runner` asks for ATT; the banner relies on
   Google's `loadAndShowConsentFormIfRequired`
   (`lib/modules/monetization/ad_service.dart:48`) to surface it. That may
   be sufficient, but it is an assumption about a third-party flow rather
   than something this app controls or can verify without a device.

The ad consent path itself is clean: `AdConfig.canRequestAds` cannot be
true in a release build without live IDs (`ad_config.dart:50-51`),
`useTestAds` is `false`, and there is no hard-coded UMP `debugGeography`
anywhere in the tree.

### Doc drift corrected by this pass

`docs/instruction.md` is now headed as the 20 Oct method log, because the
code has moved past it: 8 liveness misses not 3, a 1.5s retired-fd join not
8s, MTU 1280 with a captured-and-dropped `::/0` rather than 1200 and
IPv4-only, the app deliberately *inside* its own TUN via `protect()` rather
than excluded, §F's `retireClient()` second-session design superseded by
one client plus `nativeReplaceTun`, and two relay-selection numbers: §C's
"one host per `/24`" is now **2, or 3 when premium**
(`lib/modules/core/vpn_controller.dart:1047`), and §H's "one endpoint per
`/24`" is actually a **round-robin spread** that will take a second host
from a subnet once the others run out (`vpn_controller.dart:1563` — the
function's own comment still says "one per /24 per pass", which is the
origin of the doc drift). The banner also records that a handover while
Connected now forces a clean redial through all three engines rather than
trusting the old session (`vpn_controller.dart:750-752`, `774-823`), and
that data-plane proof is cleared only in `_disarmWatchdog`
(`vpn_controller.dart:361`), not on the restore path. In this file, the
"Fallback" row was wrong: OpenVPN does not get 8 attempts — it dials last,
usually 0 or 1 servers, and returns an empty dial list when the strict
probe finds none (`lib/modules/core/vpn_controller.dart:1685`).

Still declared but unused by `lib/`: `flutter_screenutil`, whose `.sp`
DESIGN.md §3 now bans. Eight test files still wrap a `ScreenUtilInit` that
nothing reads any more, so the dependency is inert rather than harmful —
but it is a standing invitation to reintroduce the double-scaling bug.

---

## What is still open

1. **Windows** — no device verification or store upload.
2. **Play production “completed”** — blocked while the Play app itself is draft.
3. **Mac App Store** — no `3rd Party Mac Developer Installer` identity on the build Mac.
4. **Picked country may exit elsewhere** — SoftEther escape prefers a live tunnel over hanging; the UI shows the connected relay, not the picker.
5. **iPad / Mac full-screen responsive layout** — product UI work, not tunnel.
6. **Automated Connected screenshots** — screen security + wireless iPhone capture limits.

---

## Simulator and emulator pass, 2 Nov 2026 — Android green, Apple still device-only

The disk pressure that had blocked an emulator was cleared (61 Gi free), a
`BulbVpn_Fresh` AVD booted to `arm64-v8a`, and a fresh iPhone 16 simulator
was created. The Android half then went all the way to a proven tunnel; the
iOS half stayed unreachable for a structural reason that is itself a finding.

**1. Apple SoftEther has no simulator slice, and no recoverable source.**
`flutter build ios --simulator` fails to link with `Undefined symbol:
_softether_set_reconnect` and eight siblings. The cause is not a missing
search path: `ios/ThirdParty/softether/ios/libsoftether.a` is a **non-fat
arm64 archive whose objects carry `LC_BUILD_VERSION platform IOS`**, i.e.
device-only, and `libssl.a` / `libcrypto.a` are the same. No
`.xcframework` and no `sim/` directory exists anywhere under `ios/`, so a
simulator build has never been possible — every iPhone, iPad and macOS
"Connected" row in this catalog is device-only by construction, not merely
unverified. Rebuilding the slice is not available either: the repo contains
only the API header and its *callers* (`android/app/src/main/cpp/
softether_jni.c` declares `extern softether_client_t softether_create(...)`),
never the implementation, and the upstream cited at `docs/instruction.md:463`
(`devstroop/SoftEtherZig`) now returns **404** while GitHub itself is
reachable from this network — `github.com/ziglang/zig` answers 200 and
`api.github.com/search/repositories?q=softether+language:zig` returns
`total_count: 0`. So the binary that carries the tunnel on all three Apple
platforms has no buildable source and no documented build recipe in this
repository. That is a supply-chain and maintainability exposure, not just a
missing test target.

**2. Android dependency resolution needed a tunnel of its own.** Clearing
`.gradle/caches` made this visible: the build dies at `android/settings.gradle.kts:19` with
`Plugin [id: 'com.android.application', version: '9.0.1', apply: false] was
not found`. That is not a nonexistent version — `dl.google.com` returns 404
for *every* AGP tried (`8.5.2`, `8.7.0`, `8.13.0`, `9.0.0`, `9.0.1`,
`9.0.2`), while `repo1.maven.org` returns 200 and `clients3.google.com/generate_204`
returns 204, so general connectivity is fine and only Google's Maven endpoint
is filtered. A third-party mirror does serve the same artifacts (Aliyun
returns 200 for AGP 9.0.1), but pointing the build at it is a supply-chain
decision this project should make deliberately, not as a side effect of a
build. The chosen path was the app's own protocol instead: `xray-core`
v26.10.31 (sha256 `0a05dca3…c07e9a`, verified before first run) stood up an
HTTP CONNECT listener on `127.0.0.1:10801` fronting a community REALITY relay
with DoH resolution and domain-scoped routing, and a temporary
`~/.gradle/gradle.properties` pointed Gradle at it. Through that path
`dl.google.com` served genuine payloads (a 12 006-byte AGP pom, a
25 267-byte `maven-metadata.xml`) instead of the 1 449-byte injected Google
404, which confirms the block is response injection rather than absence. The
config now sits unused at `~/.gradle/gradle.properties.reality-proxy.bak`; the
machine's own clients were never a fallback — port `7897` was closed and
`HTTPEnable : 0`, and neither Lantern nor Hiddify exposed a listener.

**3. SoftEther is arm64-only on Android too.** `android/app/build.gradle.kts:38`
sets `abiFilters += "arm64-v8a"` and `android/app/src/main/cpp/prebuilt/`
contains only `arm64-v8a`. The booted AVD is `arm64-v8a`, so emulator
testing is viable once dependencies resolve — but no x86_64 emulator and no
32-bit ARM device can run the primary engine anywhere.

**4. A recovery timer was tearing down tunnels it had just proven.** The first
emulator connect looked healthy and then churned: `CONNECTED via
219.100.37.111:443` → `Auto-reconnect 1/10` → `SoftEther dial failed:
connect code -12`. Root cause: the throughput verdict runs
`unawaited(_verifyTunnelThroughput(...))`, so `_connect()` returns while the
claim is still `analyzing` — a live session whose first byte has not been
judged yet — and both the post-dial check and the recovery timer read the
status *before* their awaits and never re-read it, so an unfinished judgement
was counted as a failed press and redialled over. `analyzing` had no owner in
the recovery contract. Fix: `holdsLiveSession()` in
`lib/modules/core/session_liveness.dart` guards all three decision points
(ladder entry, timer body before and after the awaits, post-dial check);
`connected` and `analyzing` are a session, everything else is not. The guard
cannot strand a dead tunnel because both `setAnalyzing()` sites
(`vpn_controller.dart:2155`, `:2297`) are followed by the probe, which always
resolves: `_downloadThroughTunnel` cannot throw, and its zero-byte path
already owns `setDisconnected()` plus `_scheduleRecovery()`.

Evidence on the fixed build, `BulbVpn_Fresh` / android-35 / arm64-v8a, tapped
through the home aperture (2 Nov, all times +0330):

```
16:45:55  CONNECTED via SoftEther 219.100.37.179 (JP)
16:46:04  Throughput after connect: 64 KiB in 6738ms (~9 KiB/s)
16:46:04  Data-plane watchdog armed (20s)
16:46:05  [ExitIp] resolved 219.100.37.244 (JP)   (all three probe hosts agree)
16:46:25  Data plane verified through 219.100.37.179
          Auto-reconnect: 0 lines in the whole session
16:50:27  UI still Connected, uptime 00:04:25, "traffic confirmed just now",
          exit IP shown, tun1 rx 195 223 B / tx 66 450 B
```

The same session then survived a deliberate failure: `iptables -I OUTPUT -d
219.100.37.0/24 -j DROP` blackholed the live relay at 16:50:51, and recovery
behaved exactly as the guard requires it still can —

```
16:51:16  Data-plane probe missed (1/2) on 219.100.37.179
16:51:23  Tunnel dropped unexpectedly; scheduling recovery
16:51:25  Auto-reconnect 1/10
16:51:45  SoftEther probe: 4/7 reachable → dial 217.138.212.62 (RO)
16:51:53  CONNECTED via SoftEther 217.138.212.62 (RO)
16:52:00  Throughput after connect: 64 KiB in 4910ms (~13 KiB/s)
16:52:21  Data plane verified through 217.138.212.62
16:53:xx  UI Connected, uptime 00:02:01, "traffic confirmed 19s ago · Romania",
          tun1 rx 4 379 468 B / 13 132 pkts
```

Two environment notes, because they were the difference between a trustworthy
measurement and a fake one: the AVD booted with `hw.gpu.enabled = no` and a
second emulator was sharing the host, which drove load to 30 and put SystemUI
into repeated ANRs; relaunching with `-gpu host` (MoltenVK/gfxstream) settled
it. And `uiautomator dump` fails outright while those ANR dialogs are up, so
the taps that "did nothing" were landing on a modal relay sheet, not on the
dial.

Emulator evidence is still not mobile-data evidence: nothing here exercises
DNS poisoning or response injection on the path, and §17 of
`connection-solutions.md` remains open until it is run over Iranian LTE.
`flutter test` is green at 169 and `flutter analyze` reports only the
pre-existing `unawaited_return_in_try_block` at
`lib/modules/speed_test/application/services/upload_measurement_service.dart:160`.

---

## Timeline of the worst regressions (short)

1. **IR Android LTE** — Connected with dead tunnel (handshake kill + wrong TUN + protect insufficient).
2. **Apple OpenVPN** — intermittent CONNECTED with TLS 1.0 pin; later passes all `VERIFY OK` then timeout.
3. **Fresh install OpenVPN-first** — only Mac SoftEther connected; iPhone / iPad / Android failed.
4. **Android SoftEther 8s cancel** — `-12` then fdsan; fixed by 28s budget + safe `closeTun`.
5. **Confirmation SoftEther-first** — all four attached devices Connected on `219.100.37.105`.
6. **Emulator, 2 Nov** — recovery redialled over an `analyzing` session and tore down a
   tunnel that had already moved 64 KiB; fixed by `holdsLiveSession()` at every decision point.
6. **Country pick hang (20 Oct)** — SoftEther escape + OpenVPN fail-fast; Android US pick and iPad auto SoftEther Connected.
