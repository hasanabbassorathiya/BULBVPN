# BULBVPN — VPN issues log

Every connection problem hit while shipping SoftEther / OpenVPN over
VPN Gate. Grouped by network, then by platform. Status is as of
**20 Oct 2026** (country-pick SoftEther escape verified on Android;
iPad SoftEther Connected after VPN profile Allow).

The step-by-step Android IR method lives in
[`instruction.md`](instruction.md). This file is the issue catalog.

---

## Working path (what finally stuck)

| Layer | Choice |
|---|---|
| First dial | SoftEther TLS on TCP 443 (hub `VPNGATE`, user/pass `vpn`/`vpn`) |
| Fallback | OpenVPN TCP 443 only (up to 8 attempts) |
| Preferred SoftEther hosts | `219.100.37.105` / `public-vpn-139.opengw.net`, `.179` / `187` (`.192` is not in the catalog and was dropped) |
| Apple profile marker | `# bulb-host` / `# bulb-sni` — extension never starts OpenVPNAdapter for that profile |
| Android SoftEther budget | Full 28s (not an 8s cap) |

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

## What is still open

1. **Windows** — no device verification or store upload.
2. **Play production “completed”** — blocked while the Play app itself is draft.
3. **Mac App Store** — no `3rd Party Mac Developer Installer` identity on the build Mac.
4. **Picked country may exit elsewhere** — SoftEther escape prefers a live tunnel over hanging; the UI shows the connected relay, not the picker.
5. **iPad / Mac full-screen responsive layout** — product UI work, not tunnel.
6. **Automated Connected screenshots** — screen security + wireless iPhone capture limits.

---

## Timeline of the worst regressions (short)

1. **IR Android LTE** — Connected with dead tunnel (handshake kill + wrong TUN + protect insufficient).
2. **Apple OpenVPN** — intermittent CONNECTED with TLS 1.0 pin; later passes all `VERIFY OK` then timeout.
3. **Fresh install OpenVPN-first** — only Mac SoftEther connected; iPhone / iPad / Android failed.
4. **Android SoftEther 8s cancel** — `-12` then fdsan; fixed by 28s budget + safe `closeTun`.
5. **Confirmation SoftEther-first** — all four attached devices Connected on `219.100.37.105`.
6. **Country pick hang (20 Oct)** — SoftEther escape + OpenVPN fail-fast; Android US pick and iPad auto SoftEther Connected.
