# BULBVPN — Iran resilience & Lantern integration

Branch: `feat/ir-resilience-lantern`
Base: `redesign/production-grade` @ `3c98143`
Started: 2026-10-27
Last updated: 2026-10-28
Status: workstreams 1–20 code complete and build-verified; IR Wi-Fi and Irancell LTE
runs pass on device; Phase L decision pending

## How to read this document

- `[x]` done and verified on this branch; the item names the file and the check
  that proved it.
- `[~]` code written, not yet verified end to end.
- `[ ]` not started.
- The status board below is the single source of truth for what is left. Update
  it in the same change that finishes an item.

## Status board

| # | Workstream | State | Evidence / next check |
| --- | --- | --- | --- |
| 1 | Branch + tracking | done | this document |
| 2 | Network truth and recovery watcher | done | `network_identity.dart`, `VpnController._pollNetworkIdentity` |
| 3 | Per-network relay memory | done | `relay_memory.dart`, `test/relay_memory_test.dart` |
| 4 | Fresh VPN Gate catalog on demand | done | `vpn_controller.dart _freshCandidates` |
| 5 | Apple path monitor + mobile-safe tunnel tuning | done | `SoftEtherSession.swift` (iOS/macOS) |
| 6 | Reachability cache + warm probes | done | `relay_reachability.dart`, `test/relay_reachability_test.dart`, `VpnController._warmRelayProbes` |
| 7 | Persistent per-network relay scoring | done | `relay_memory.dart` stats, `orderByHistory`; tests pass |
| 8 | Catalog source racing + disk cache | done | `vpn_gate_candidates.dart`, `test/vpn_gate_catalog_cache_test.dart` |
| 9 | Recovery budget + Android liveness tolerance | done | `vpn_controller.dart`, `connection_state_provider.dart`, `SoftEtherVpnService.kt` |
| 10 | Apple IPv6 blackhole + packet filter | done | `SoftEtherSession.swift`, `PacketTunnelProvider.swift`; typecheck pass |
| 11 | Region guard + diagnostic + Google-region explanation | done | `home_region.dart`, `logs_screen.dart`, this document |
| 12 | Tests + analyzer/build verification | done | analyze clean (1 pre-existing warning); 15/15 tests pass; debug APK built; Apple typecheck pass |
| 13 | Device verification on an IR SIM / OnePlus | done | IR Wi-Fi run on OnePlus 13R (10.6-min liveness); Irancell LTE run on Samsung SM-M127G (2026-10-28, see "Irancell LTE mobile-data run") |
| 14 | Lantern license/ToS decision (L-A/L-B/L-C) | pending | user decision; see Decision 2 and Phase L |
| 15 | Android fast-path dead data path | done | fast path removed from `SoftEtherVpnService.kt`; same JP relay now cold-connects with HTTP 200 + 0% loss on the OnePlus 13R (IR Wi-Fi) |
| 16 | App inside TUN + true exit measurement | done | `SoftEtherVpnService.kt` default-route branch (D7); AFTER reports the real exit, distinct from the relay address |
| 17 | Manual BEFORE/AFTER refresh + forced lookup | done | `main_screen.dart` `_refreshIps`, `ip_info_provider.dart` `force`; second forced lookup 27 s apart re-resolved |
| 18 | TLS-handshake ping instead of TCP accept | done | `server_ping_provider.dart`; numbers went from 6–8 ms to 600–1400 ms honest RTT |
| 19 | Multi-server / multi-country matrix | done | US no-DHCP, KR code -5, RU/TH/CH no TLS handshake, JP connects and switches; escapes to JP verified |
| 20 | Irancell LTE connect fix (TLS-stall probe + full sweep) | done | `_probeOneSoftEther`/`server_ping_provider` hard handshake cap; warm probe 0/8 in 3 s, sweep 99→2 alive in 6 s, session up on JP `115.179.206.241`, real traffic over tun1; see the LTE section |
| 21 | Fresh on-device catalog (multi-sample union, published list order) | done | `scripts/fetch_vpngate.py` unions 5 API samples (106 rows); `vpngate_source.dart` tries the default-branch list first; hourly Action still not merged to `main` |

## Problem

On Iranian mobile data (and some Wi-Fi networks) the app often never reaches a
working tunnel. When it does connect it can stop carrying traffic, drop during
a Wi-Fi ↔ mobile handover, or show "Connected" over a dead session. The current
stack is VPN Gate + SoftEther SSL-VPN + OpenVPN fallback; the docs describe the
history in `docs/vpn-issues.md`, `docs/connection-solutions.md`, and
`docs/research-vpn-architecture.md`.

Two follow-up requests widened the scope:

1. Study how Lantern (`getlantern/lantern`) connects quickly, survives Iranian
   networks, and stays up for days, and apply those techniques on Android,
   iOS, and macOS.
2. Make Google stop treating the connection as a restricted region. Lantern
   itself is sometimes detected, so this is not only a "which relay" problem.

The license/ToS consequence of using Lantern's code or relays is recorded under
D2 and remains an explicit decision, not an accident.

## Failure taxonomy (confirmed in code and device logs)

1. **Stale relay pool.** `serversProvider` only refreshes the GitHub Actions
   catalog; `VpnGateCandidates.fetchAll()` existed but was never called. On a
   network where GitHub/jsDelivr is blocked the app keeps dialling the catalog
   that was bundled at build time.
2. **One global last-good.** A relay that works on home Wi-Fi is often dead on
   a carrier. The global last-good entry is tried first after every handover.
3. **No network-change recovery before the UI drop.** Android tears the native
   session down on a carrier move; iOS SoftEther had no path monitor, so a dead
   session could look green until the library read timeout.
4. **Liveness is too strict on the UI side.** `SoftEtherStatus.isLive` includes
   `carrierUp`, so the UI could drop on the first transient miss.
5. **Recovery budget is consumed by the old network.** The bounded 2s/8s/20s
   recovery could be exhausted while the phone is between networks, and it gave
   up after three tries, so a multi-minute carrier outage ended recovery for
   the day.
6. **DNS through the tunnel is hardcoded.** Android handed `1.1.1.1` and
   `8.8.8.8` to every tunnel instead of the gateway DNS the DHCP exchange
   returned, so some relays connected but could not resolve names.
7. **No on-device path proof.** The Android app is excluded from its own TUN to
   keep the relay socket out of it, so the Dart exit-IP lookup cannot prove the
   data path. Liveness must come from the native session instead.
8. **Sequential rotation can spend the whole budget on a dead cluster.** The
   candidate list is ranked on-device, but a fresh source is not consulted when
   every probe fails.
9. **Sequential catalog sources.** `fetchAll` awaited the official http and
   https CSV before trying any mirror. On an Iranian carrier the first source
   can time out, and the mirror that would have answered never gets a turn
   inside the connect budget.
10. **No memory of which relays fail.** Every connect re-probed the same dead
    relays in the same catalog order. A relay that failed thirty seconds ago
    on this exact network was still dialled first.
11. **IPv6 escapes the Apple tunnel.** The iOS/macOS tunnel settings install
    only IPv4 routes. On a dual-stack carrier, IPv6 traffic leaves outside the
    tunnel and sites (Google included) see the real Iranian address while the
    UI says "Connected".
12. **Region detection is not only the tunnel IP.** Google can also use the
    account/billing country, device GPS and timezone, and the reputation of
    the public VPN Gate address. A VPN can only change the last one, and public
    VPN Gate addresses are heavily flagged.
13. **Android fast path reports Connected with a dead data path.** The
    remembered-TUN-IP shortcut opened the routed TUN before the handshake and
    reused the previous session's address. On the OnePlus 13R (IR Wi-Fi) it
    authenticated, logged `session up tun=10.239.109.22`, and read nothing from
    the TUN: `libsoftether` DIAG stayed `dl=0.0Mbps(0p) ul=0.0Mbps(4p)
    nread_max=0B`, `curl https://example.com` and `curl https://1.1.1.1`
    timed out, and a second app sat on "Connecting…" while BULBVPN showed
    LIVE. The cold sequence (placeholder TUN → connect → DHCP →
    `softether_replace_tun_fd`) on the same relay carried `example.com` HTTP
    200 in 1.4 s and `ping 8.8.8.8` with 0% loss. **Fixed** on 2026-10-28 by
    removing the fast path.
14. **Success is recorded from session state, not traffic.** `RelayMemory`
    marked the dead fast-path relay "proven" and offered it first on the next
    connect, so the app kept returning to a tunnel that passed nothing until
    the fast path was removed. A traffic-aware success signal (in-service
    data-path probe) is still open — see Phase 4/5.
15. **The TLS probe had no handshake deadline.** `dart:io` implements
    `SecureSocket.connect(timeout:)` as
    `RawSocket.connect(host, port, timeout: timeout).then(secure)`, so the
    timeout covers only the TCP connect; `secure()` — the handshake — is
    unbounded. On Irancell the relay accepts TCP and then stalls TLS forever,
    so the warm probe, the catalog ping sweep, and the pre-connect probe hung
    for minutes with no log line. Confirmed on 2026-10-28: at app start the
    plan was computed at 13:51:53 and neither `[Ping] Measured` nor
    `Warm probe` ever appeared. Fixed by capping the whole future with
    `.timeout()` in both probe sites and destroying sockets that resolve late.
16. **The hourly catalog Action never ran.** `.github/workflows/vpngate-servers.yml`
    exists only on feature branches, so the default-branch published list is
    frozen at 2026-10-18 and `git cat-file -e origin/main:...yml` fails. The
    app tolerates this (bundled catalog + disk cache + live API fallback), but
    the published list cannot be relied on as fresh until the workflow merges.

## Decisions

### D1 — Fix the transport/recovery path before replacing the engine

The current SoftEther path is the only one proven from Iranian carriers in the
device logs. Replacing it with a new engine before the selection, recovery, and
DNS bugs are fixed would remove the known-good path. This branch fixes those
first, then leaves a provider seam for the next engine.

### D2 — Lantern license and server access

Findings from the upstream source and releases:

- Lantern's app and `getlantern/radiance` are **GPL-3.0**. `radiance` embeds
  sing-box, which is also GPL-3.0.
- No prebuilt AAR/xcframework is published; embedding it means a gomobile build.
- `radiance` obtains relays from Lantern's `/config-new` endpoint using an
  anonymous account, device identity, and supported-protocol list. Those relays
  are operated for Lantern's users, not published as a free public pool.
- BULBVPN is currently MIT. Linking GPL code would require distributing the
  combined app under GPL-3.0 and publishing the corresponding source. Calling
  Lantern's backend from a different client raises separate terms-of-service and
  bandwidth-cost issues.

**Decision for this branch:** do not silently relicense the app and do not ship
unauthorized use of Lantern's relay service. Take the architecture/protocol
lessons (config-driven relays, protocol capability negotiation, health-based
ordering), and leave the server integration as an explicit product/legal choice:

- [ ] **L-A — GPL-3.0 fork:** embed `radiance`/sing-box via gomobile, relicense
  the whole app, publish source, and verify on a real IR device.
- [ ] **L-B — user-run Lantern:** run the user's own Lantern daemon and route
  through its local proxy (no GPL embedding, but needs a tun2socks layer).
- [ ] **L-C — written permission/API access:** get explicit permission and a
  supported integration contract from the Lantern project before using relays.

Until one is chosen, Lantern remains a reference implementation, not a hidden
dependency. No GPL source is copied; the code below is an independent
implementation of publicly documented ideas (background URL tests, selection
history, network-change recovery).

### D3 — Measure before the user taps

Lantern's fast connect comes from a background URL test that keeps a current
ranking, not from a faster dial. BULBVPN adopts the same shape with a much
smaller budget:

- a **short-lived per-network probe cache** (`RelayReachability`, 5 min TTL,
  160 entries) that is invalidated on every network change, and warm probes
  that fill it while the user is still on the home screen;
- a **persistent per-network score** (`RelayMemory.recordProbes` /
  `orderByHistory`, 30-day TTL, 128 entries) that reorders targets but never
  removes them, so a wholly blocked country still has an attempt order.

The cache is an optimisation, never a truth: a cached "alive" still has to pass
the real SoftEther dial, and a cached "dead" is re-tested when every other
target fails.

### D4 — Capture IPv6 instead of leaking it

Apple's `NEPacketTunnelProvider` only blocks a family that has no tunnel
settings. The fix is to install an IPv6 ULA with a default route so the traffic
enters the tunnel, then drop non-IPv4 packets in the pump: the SoftEther library
is IPv4-only, so forwarding them would corrupt the session. This makes the
carrier's IPv6 path a black hole instead of a leak.

Android already blocks IPv6: `VpnService` blocks any family without an address,
route, or DNS server, and the service sets `allowFamily(AF_INET)` plus an IPv4
default route only. This is recorded so a future change does not silently open
the leak.

### D5 — A same-country exit is a region signal

Auto mode ranked relays by latency. On an Iranian carrier the lowest-latency
VPN Gate relay is frequently an Iranian exit, so the tunnel was healthy while
every site still saw Iran. `HomeRegion` infers the device country from the
system locale (`fa_IR`), the timezone name, or the unique +03:30 offset, and
auto mode moves same-country exits behind foreign ones without removing them.
A user-picked country is never overridden. The inference is logged at startup
and written into the support blob so a wrong guess is visible, not silent.

### D6 — A TCP connect is not evidence of reachability

The server sheet used to time a plain TCP connect to `ip:443`. On an Iranian
ISP that is fiction: a middlebox terminates the TCP handshake locally, so a
relay in Japan "answered" in 4.5 ms while the TLS handshake that SoftEther
actually needs took 1.76 s. The ping now times a real TLS handshake
(`SecureSocket.connect`, self-signed certificates accepted, 4 s cap, 10
concurrent) and reports "—" when no handshake completes. The same run showed
all six visible Russian relays unreachable, which the old number would have
hidden behind a fast TCP accept.

### D7 — The app lives inside its own tunnel

The default-route TUN used to call `builder.addDisallowedApplication(package)`,
so the app itself bypassed the tunnel. The in-app exit-IP lookup then reported
the carrier address while every other app used the tunnel — a "no leak" claim
the app could not actually verify. The exclusion is gone: the app's traffic
enters the TUN like any other app's, and the SoftEther session socket stays
outside through `protect()` (`nativeSetProtect` → `protectFd`). The BEFORE/AFTER
rows now show the carrier address and the true exit, and the AFTER lookup is
the on-device proof of where traffic egresses.

Two consequences are accepted:

- while connected, "Ping all" probes relays through the tunnel, so its numbers
  include tunnel overhead; the native warm probe remains the planning signal;
- BEFORE may equal the exit for a moment if the exit lookup resolves before the
  TUN is up. The UI labels the exit row "AFTER" only when the exit IP differs
  from BEFORE, so a stale before-address is never presented as the exit.

## Google region: what this branch changes and what it cannot

Fixable in the app (implemented):

- **IPv6 leaks** — an IPv4-only tunnel used to let dual-stack IPv6 bypass the
  VPN on iOS/macOS. It is now captured and dropped (D4). Android already
  blocked it.
- **DNS** — every tunnel installs a DNS server inside the tunnel, and Apple
  sets `matchDomains = [""]`, so name resolution happens at the exit instead of
  at the ISP.
- **Exit country** — same-country exits are deprioritised, so the public IP a
  site sees is more likely to be the foreign country the user chose (D5).
- **Dead exit IPs** — a relay that just failed is demoted by per-network
  history, so the app rotates away from a black-holed exit instead of pinning
  it.

Not fixable by any VPN, and now stated in the in-app diagnostic:

- **Account country / billing profile.** Google reads the country on the
  account, not only the IP.
- **GPS and device location services.** A VPN does not move the device.
- **Device timezone and locale.** Faking them breaks clocks and is not
  attempted.
- **Public relay reputation.** VPN Gate exits are shared, public and heavily
  flagged. A clean-looking IP is a property of the relay pool, not of the
  tunnel implementation; the app can only prefer a reachable alternate.

The honest promise is therefore: no leak, no local exit by default, and a
truthful country label. It is not "every Google service will treat this as a
different country".

## Phases

### Phase 0 — Branch and tracking

- [x] Create `feat/ir-resilience-lantern` without disturbing the existing
  working tree.
- [x] Add this document with checkboxes and a verification log.

### Phase 1 — Network truth and recovery

- [x] Add a plugin-free network identity (interfaces, no `connectivity_plus`;
  it SIGSEGVs on iOS 27 beta). File: `lib/modules/core/network_identity.dart`.
- [x] Add a network-change watcher in `VpnController` that resets the recovery
  budget on a new network and aborts a dial bound to the old one.
- [x] Add a short liveness grace in `ConnectionStateNotifier` so one transient
  native miss does not drop the orb.
- [x] Add an iOS/macOS `NWPathMonitor` that tears down a SoftEther session whose
  underlying interface changed, so the app can redial instead of showing a
  black-holed "Connected".
- [ ] Verify a real Wi-Fi ↔ mobile handover on the OnePlus device and capture
  the log lines from `VpnController` and `SoftEther`.

### Phase 2 — Per-network relay memory

- [x] Persist the relay that actually connected per Wi-Fi / carrier
  fingerprint, bounded and expiring (`relay_memory.dart`; 4 tests pass).
- [x] Prefer network memory ahead of the global last-good in auto mode.
- [x] Forget a remembered relay when its native dial fails, so one dead relay
  cannot poison every reconnect on that network.
- [ ] Confirm on-device that a home Wi-Fi pick and a mobile-data pick differ and
  both survive app restarts.

### Phase 3 — Fresh relay source

- [x] Call the existing on-device VPN Gate fetch (`VpnGateCandidates.fetchAll`)
  when the cached catalog has no reachable endpoint.
- [x] Use the fresh list for both SoftEther and OpenVPN rotation; derive SNI and
  country from the CSV/mirror row.
- [x] Respect the connect budget and cache the result for the current press.
- [ ] Verify from an IR SIM that a fresh fetch can rescue an all-dead bundled
  catalog.
- [x] Race official/mirror sources and keep a disk cache (workstream 8 —
  `VpnGateCatalogCache`, 60 endpoints, 7-day TTL).

### Phase 4 — Native path hardening

- [x] Use the SoftEther DHCP gateway as the first DNS server on Android, with
  public DNS retained as fallback.
- [x] Raise the Android liveness grace from 4 to 8 misses so a library-level
  reconnect is not mistaken for death (workstream 9).
- [x] Remove the Android remembered-TUN fast path; always run placeholder →
  connect → DHCP → routed TUN swap. Verified on the OnePlus 13R: the relay
  that reported Connected with `nread_max=0B` now passes HTTP 200 and ICMP
  after the cold connect (workstream 15).
- [x] Blackhole IPv6 on iOS and macOS and drop non-IPv4 packets before upload
  (workstream 10).
- [ ] Verify DNS resolution through a fresh SoftEther session on the device.
- [ ] Consider an in-extension DNS/data probe that does not depend on the app
  being excluded from the TUN.

### Phase 5 — Next engine (Xray/REALITY)

This is where Lantern's protocol approach becomes useful without their service.

- [ ] Choose a license-compatible engine (Xray-core is MPL-2.0; sing-box is
  GPL-3.0 and would trigger the same relicensing decision as Lantern).
- [ ] Add a `VpnEngine` seam so `VpnController` can select SoftEther, OpenVPN,
  or Xray without changing the UI contract.
- [ ] Add a user-supplied subscription/catalog source and signed catalog
  verification.
- [ ] Add a data-path probe and exit-IP verification that works on Android.
- [ ] Test VLESS+REALITY on TCP 443 from an IR carrier.

### Phase 6 — Lantern-style fast connect (workstreams 6–7)

Mapping from the upstream study to this repo:

| Lantern mechanism | BULBVPN implementation | State |
| --- | --- | --- |
| Background URL test ranks proxies before connect | `RelayReachability` + `_warmRelayProbes` | done |
| Selection history persisted per server | `RelayMemory` stats keyed `network\|dial` | done |
| Exhaustion signal triggers an immediate re-probe | re-probe dead relays when every target fails | done |
| `Restarting` suppresses intermediate states | existing controller keeps the orb on Connecting during rotation | done (pre-existing) |
| Network recovery re-polls interfaces, 3s→30s backoff | `_pollNetworkIdentity` + jittered recovery | done |
| Switch server instead of reconnecting when already up | `_connect` already treats a live session as switchable | done (pre-existing) |

- [x] Add `RelayReachability` (5 min TTL, per-network, bounded at 160 entries).
- [x] Add persistent probe/dial statistics and `orderByHistory` to
  `RelayMemory`.
- [x] Invalidate the cache and schedule warm probes on network change and app
  start (`VpnController._primeNetworkWatcher`, `_pollNetworkIdentity`,
  `_adoptNetwork`, `warmProbes` on app resume).
- [x] Use a fresh cached success to skip the 2 s probe; use a cached failure to
  demote a target.
- [x] Record every probe round and every SoftEther dial failure; mark success on
  connect.
- [x] Reorder auto-mode targets with `RelayMemory.orderByHistory`.
- [x] Re-probe the dead set when all targets fail, instead of ending the dial.

### Phase 7 — Region and leak hardening (workstreams 10–11)

- [x] Apple IPv6 blackhole in `tunnelSettings` (iOS + macOS).
- [x] Filter non-IPv4 packets in the Apple pump before writing to the upload
  descriptor.
- [x] Same-country exits moved behind foreign exits in auto mode
  (`home_region.dart`).
- [x] Diagnostic that reports: device locale/timezone/home country, relay
  country, same-country flag, IPv6 policy, and the Google-region caveat
  (`logs_screen.dart` support blob).
- [x] User-facing explanation that Google can still detect the region from the
  account country, GPS, timezone, and the reputation of public VPN Gate IPs.
- [x] Document which part is fixable in-app (leaks, DNS, relay choice) and
  which is not (account country, GPS) — see the Google-region section above.
- [ ] Confirm on an IPv6-enabled SIM that the diagnostic says
  `captured and dropped` and no IPv6 traffic leaves the tunnel.

### Phase L — Lantern

- [ ] Choose L-A, L-B, or L-C above.
- [ ] Record the license/ToS decision in the repository and in the store listing.
- [ ] Re-run the IR device matrix before shipping any Lantern-derived binary.

## Verification log

| Date | Check | Result |
| --- | --- | --- |
| 2026-10-27 | Branch created from `redesign/production-grade` | pass — working tree preserved; changes not committed yet |
| 2026-10-27 | `dart format` | pass — all touched Dart files formatted |
| 2026-10-27 | `flutter analyze` | pass — 0 errors; one pre-existing unrelated warning in `lib/modules/speed_test/application/services/upload_measurement_service.dart:160` |
| 2026-10-27 | Android debug build | pass — `flutter build apk --debug` (`assembleDebug`, arm64/armv7/x86_64) |
| 2026-10-27 | iOS/macOS extension compile | pass — `swiftc -typecheck` of `SoftEtherSession.swift` (arm64 iOS 16 / macOS 13, SDK 26.5) with the extension bridging header; no diagnostics |
| 2026-10-27 | `test/relay_memory_test.dart` | pass — 4/4 |
| 2026-10-28 | `dart format` (fast-connect layer + region guard) | pass — 11 files, 0 changed |
| 2026-10-28 | `flutter analyze` | pass — 0 errors; same pre-existing warning only |
| 2026-10-28 | Relay memory + reachability + catalog cache tests | pass — 15/15 (`relay_memory`, `relay_reachability`, `vpn_gate_catalog_cache`) |
| 2026-10-28 | Android debug build | pass — `flutter build apk --debug` exit 0, `app-debug.apk` 98 MB |
| 2026-10-28 | iOS/macOS IPv6 blackhole + packet filter compile | pass — `swiftc -typecheck` of `SoftEtherSession.swift` + `PacketTunnelProvider.swift` |
| 2026-10-28 | Real device handover + DNS | pending — needs a physical IR SIM / OnePlus run |
| 2026-10-28 | OnePlus 13R (CPH2691), IR Wi-Fi: startup | pass — `Device region: locale=en_AE tz=+3:30 home=IR`; fingerprint `wifi:wlan0:192.168.0`; warm probe 6/7 relays reachable in ~2 s |
| 2026-10-28 | OnePlus 13R, IR Wi-Fi: connect via remembered-TUN fast path | **fail** — Connected in 10.8 s, `libsoftether` `nread_max=0B`, `curl https://example.com` and `curl https://1.1.1.1` timed out, a second app stuck on "Connecting…" (failure 13) |
| 2026-10-28 | OnePlus 13R, IR Wi-Fi: cold path to JP 219.100.37.95 | pass — DHCP `10.238.61.186/16`, `routed tun fd=228 replaced=222`, `example.com` HTTP 200 in 1.4 s, `ping 8.8.8.8` 0% loss, ~13 s to Connected |
| 2026-10-28 | OnePlus 13R, IR Wi-Fi: per-network memory | pass — after reinstall/restart: `Network-memory relay 219.100.37.95` and the relay was first in the auto plan |
| 2026-10-28 | Fast-connect layer (warm probes, network memory, scoring, recovery) | code complete and build-verified; device behaviour still pending an IR SIM run |
| 2026-10-28 | OnePlus 13R, IR Wi-Fi: app inside TUN + real exit measurement | pass — BEFORE `5.239.173.26` (Qom, IR); AFTER through tunnel `219.100.37.239` (Tokyo, JP), distinct from the relay address (VPN Gate NAT), so app traffic provably traverses the tunnel |
| 2026-10-28 | OnePlus 13R, IR Wi-Fi: manual IP refresh | pass — both taps re-resolved the exit; the second tap 27 s after the first still resolved, so the forced lookup bypasses ipwho.is' one-per-minute window |
| 2026-10-28 | OnePlus 13R, IR Wi-Fi: TLS ping | pass — "Auto · Japan 789 ms", US 616 ms, KR 1370 ms instead of the old 6–8 ms TCP-accept fiction |
| 2026-10-28 | OnePlus 13R, IR Wi-Fi: multi-country dials | US `156.239.242.10` failed `no dhcp address` after 30 s; KR `121.136.113.227` failed `connect code -5` after 24 s; both escaped to JP and connected. RU (6 visible), TH (6), CH (1) show "—": no TLS handshake completed. JP connects in ~10 s; explicit JP switch to `219.100.37.9` connected in 10.8 s with exit `219.100.37.233` |
| 2026-10-28 | OnePlus 13R: screenshots while connected | expected black frame — the app enables FLAG_SECURE only while the tunnel is live (`isSecure=true` in SurfaceFlinger); semantics via uiautomator are unaffected |
| 2026-10-28 | OnePlus 13R, IR Wi-Fi: connected liveness monitor | pass — 24/24 `generate_204` samples returned HTTP 204 over 10.6 min on JP `219.100.37.9` (typical 0.85–1.3 s, one 5.7 s transient); exit `219.100.37.233` unchanged before and after; exactly one dial, no reconnect or recovery event |
| 2026-10-28 | Samsung SM-M127G, Irancell LTE: probe deadline bug | **fail before fix** — plan at 13:51:53, then no `[Ping] Measured`, no `Warm probe`; the TLS handshake future never completed (failure 15) |
| 2026-10-28 | Samsung SM-M127G, Irancell LTE: probe deadline fix | pass — `Warm probe on cell:rmnet0: 0/8 relays reachable` in 3 s; `TLS-sweeping 99 catalog relays in waves of 20`; `TLS sweep: 2 relay(s) alive … JP:106.153.7.87, JP:115.179.206.241` after ~6 s; server sheet then showed "Auto · Japan 780 ms" |
| 2026-10-28 | Samsung SM-M127G, Irancell LTE: connect | pass — tap 13:52:35; network-memory KR `125.129.197.183` failed auth (`-5`) at 13:53:07 and was forgotten; JP `115.179.206.241` session up at 13:53:37 (`tun 10.211.1.140`), 62 s tap-to-session including the wasted relay |
| 2026-10-28 | Samsung SM-M127G, Irancell LTE: data path | pass — Chrome page load moved tun1 RX 196,156 → 622,795 B and TX 30,881 → 56,769 B; UI `Connected · secure tunnel · Japan` |
| 2026-10-28 | Samsung SM-M127G, Irancell LTE: idle liveness | mixed — first session dropped after 96 s (`link_lost`, assigned ok, linked=false, carrier online); recovery redialled at +7 s and was up 18 s later; second session stayed up and carried 3.07 MB before the Wi-Fi handover |
| 2026-10-28 | Samsung SM-M127G: LTE → Wi-Fi handover | pass — Wi-Fi `SORATHIYAS` at 13:58:04 logged `Network changed: cell:rmnet0 -> cell:rmnet0|wifi:wlan0:192.168.0`; clean redial 13:58:09; plan 3/3 reachable in 1.2 s; JP session up 13:58:35 (`tun 10.211.1.144`) |
| 2026-10-28 | Samsung SM-M127G, Wi-Fi: data path + stability | pass — Chrome load moved tun1 RX 582,184 → 862,953 B and TX 89,863 → 168,654 B; session stayed up >4 min with no loss |

The build checks prove the code compiles. They do not prove that a blocked
carrier accepts a relay; that is what the unchecked device items above are for.

## Open risks

- The app now lives inside its own TUN, so in-app "Ping all" results include
  tunnel overhead while connected and must not be read as raw relay latency;
  the native warm probe (session socket, `protect()`ed) is the planning signal.
- Public VPN Gate relays are unstable by design; freshness and per-network
  memory reduce the cost of a dead relay but cannot make a dead relay alive.
- A new engine does not fix a blocked network by itself; protocol, port, and
  relay diversity do. The Phase 5 work must be tested on the target carriers,
  not only on a developer network.
- Lantern integration is blocked on the licensing/ToS decision, not on code.
- A warm probe is a full TLS handshake, not a TCP accept, but it can still
  succeed on a relay that later rejects auth or DHCP; the real dial remains the
  only proof of a working tunnel, which is why the cache demotes but never
  removes targets.
- Google's region signal is partly account-level. Even a perfect tunnel with a
  clean exit IP cannot change the billing country or GPS; the app must say so
  instead of promising a region change it cannot deliver.

## Release staging — BULBVPN 1.1.0 (12), 2026-10-28

The connectivity work above is frozen into a release build. Store upload is
done; store *release* is deliberately not triggered yet.

### What shipped into the binaries

- `google_mobile_ads` 9.1.0 with the bundled UMP consent flow, an adaptive
  anchored banner below the metric card, and a Settings entry for ad privacy
  options (shown only when Google requires it). Verified on the OnePlus over
  the JP tunnel: `[Ads] requesting banner 320x100` then `[Ads] banner loaded`
  in ~5 s. At idle on the IR network the request dies on the poisoned
  `googleads.g.doubleclick.net` → `10.10.34.36`, which is why the banner is
  keyed to the tunnel state and re-requests after connect.
- Release builds intentionally serve **no ads** until live unit IDs exist:
  `AdConfig.canRequestAds` is `isLive || !kReleaseMode`. This avoids shipping
  "Test Ad" creatives; the manifest/Info.plist still carry Google's sample app
  IDs, which is legal because no ad request runs.
- First-run clickwrap `Ground rules` gate (versioned SharedPreferences,
  `2026-10-28`) with links to the full Terms and Privacy Policy; declining
  exits the app. The documents disclaim warranty/liability and require lawful,
  non-abusive use. They do not claim legal immunity — nothing can waive
  criminal or non-waivable liability.
- Public legal pages redeployed to Firebase Hosting on 2026-10-28; both live
  pages show `Effective · 28 October 2026`. Terms now covers eligibility,
  acceptable use, assumption of risk, indemnity, community endpoints, ads, and
  limitation of liability; Privacy adds the AdMob section and UMP controls.

### Artifacts and store state

| Item | State |
| --- | --- |
| Android AAB | built signed, versionName `1.1.0`, versionCode 12 |
| Google Play | production **draft** `1.1.0 (12)` committed; internal track still `1.0.0 (8)`; listing no longer claims "No ads" |
| iOS IPA | built, uploaded, processed `VALID` (build 12) |
| App Store Connect | rejected 1.0 renamed in place to `1.1.0` (a never-released app cannot get a second version). Build 12 attached. Draft review submission `353049b0-4a38-473f-8acc-5bad1e1b6cd7` holds the version item. |
| Age rating | `socialMedia` patched through the official API (asc's schema lacks it); `asc review items-add` now accepts the version where it previously answered "This resource cannot be reviewed" |
| Validation | `asc validate --version 1.1.0` → 0 errors, 1 warning (WhatsApp-style `whatsNew` blocked for a first release), 1 info (App Privacy publish state not API-visible) |

### Why release was not triggered

- The App Store 1.0 rejection text lives only in the ASC web UI / email; the
  cached web session expired and no Apple login is available here. 1.1.0 is
  submission-ready, but the original rejection reason has not been read.
- Live AdMob IDs do not exist yet. Creating them needs the owner's Google
  login (AdMob API rejected the gcloud token for missing scope, and the
  automation browser only reached the sign-in page). A release built today
  would be ad-free by design.
- Google Play rollout also needs the Play Console declarations (content
  rating, data safety, ads declaration) confirmed in the web UI. A draft
  release is uploaded but not reviewed or published.

## Launch video — brag run 2026-10-28-033538

- Output: `brag-output-2026-10-28-033538/brag.mp4` — 20.0 s, 1080x1920,
  30 fps, H.264 + AAC, 1.5 MB. Poster `brag.jpg` (10.5 s, real connected UI
  with JP exit IP) baked as frame 0. Caption in `share-copy.txt`.
- Story: hook "Some networks kill the tunnel." → four-candidate relay plan
  (JP reachable, US/KR/CH failed) → "Dead relay? Next." → one-tap connect
  → BEFORE/AFTER exit IP (185.143.72.19 IR → 219.100.37.244 JP) → wordmark
  on the music cue at 17.02 s.
- Every number and IP on screen is real, taken from the device run. No
  speed claims, no stock footage; the only UI shown is the app itself.
- Gate: `npx hyperframes check` → 0 errors, 31/31 contrast, 0 layout and
  motion issues. Re-running needs `npx hyperframes@0.8.174 render` inside
  `brag-output-2026-10-28-033538/composition/`.

## Live device-state refresh and grouped relay sheet — 2026-10-28

User-reported: on iOS the DOWN gauge froze, latency/ping and BEFORE IP never
updated when the device changed networks, and the relay picker was one flat
ping list. Changes:

- Apple byte counters. A SoftEther dial never touches `vpnAdapter`, so its
  `interfaceStatistics` stayed at zero for the whole session and
  `OPENVPN_STATS` reported no traffic. `SoftEtherSession` now counts bytes in
  and out on the tunnel sockets (`statistics()`), and both iOS and macOS
  `PacketTunnelProvider.handleAppMessage("OPENVPN_STATS")` report those
  counters, falling back to the adapter stats for the OpenVPN path.
  Verified with `xcodebuild ... -destination 'generic/platform=iOS'` →
  BUILD SUCCEEDED. The macOS extension still fails to link its Pods (Flutter
  symbols undefined in `PacketTunnel.debug.dylib`); Swift compiles, the link
  step is a pre-existing project configuration problem, not this change.
  Simulator builds cannot link the device-only `libsoftether.a`.
- Network watch. `networkFingerprintProvider` (new, `network_watch.dart`)
  polls the same `NetworkIdentity` fingerprint every 5 s and emits only on
  change. It drives: BEFORE-IP refresh (Cloudflare trace first, ipwho.is
  enrichment second), latency re-measurement on the main screen, and relay
  memory already keyed on the same fingerprint. App resume also refreshes
  stale pings and the BEFORE IP.
- Ping freshness. `ServerPingNotifier` tracks `_finishedAt`; `ensureFresh`
  re-sweeps only after 2 minutes. Tab rebuilds and sheet opens no longer wipe
  good numbers back to `…`; a mid-sweep network change queues one rerun.
- Country grouping. `server_grouping.dart` groups by `displayCountry`
  (locale suffix stripped), sorts countries by their fastest successful
  probe (unreachable countries alphabetically last) and relays inside a
  country by measured ping. The sheet renders country headers (flag, name,
  relay count, best ms) with numbered relay rows; the header subtitle reports
  relay and country counts.
- Logs are debug-only: the Settings diagnostics card (and the only entry to
  `LogsScreen`) is behind `kDebugMode`. Release builds still send status
  events to Crashlytics; nothing on-device exposes them.
- Tests: `test/server_grouping_test.dart` (ordering, locale suffix,
  timeout handling), `test/server_sheet_test.dart` (360 dp render, ordering,
  no overflow). `flutter analyze` clean apart from one pre-existing
  `unawaited_return_in_try_block` warning in the speed test service;
  `flutter test` 19/19.

Lantern relay reuse was requested again and remains out of scope: Lantern's
client code is GPL-3.0 and its relays are not ours to use without permission.
Speed work stays on the VPN Gate catalog plus this device's own TLS-handshake
measurements.

## Ads behind Firebase Remote Config (default off) — 2026-10-28

Ads now have two switches in series, and both must be true before a single
ad request leaves the device.

- Remote switch. `firebase_remote_config 6.7.1` is initialized for the named
  `bulbvpn` Firebase app (the app registers its own instance, so
  `FirebaseRemoteConfig.instanceFor(app:)` is used instead of the default
  app). Key `ads_enabled`, default `false`, set via `setDefaults` so a cold
  first launch or a failed fetch keeps ads collapsed. Fetch timeout 10 s;
  minimum fetch interval is 30 minutes in release and zero in debug. A failed
  fetch keeps the last activated value.
- Compile switch. `AdConfig.enabled` plus the live-ID requirement remain:
  a release build only requests inventory when `useTestAds` is false and
  both live AdMob unit IDs are filled, so turning the remote flag on in a
  build that still ships test IDs does nothing in release.
- Wiring. `adsEnabledProvider` (`AdsRemoteConfigNotifier`) is watched by the
  main screen (which also boots the fetch), the Settings SPONSORED card and
  its privacy-options link, and `AdBanner` itself. The banner listens for the
  flag flipping to true and loads then; with the flag false it stays zero
  height. Debug builds that turn the flag on get Google test creatives only.
- Verification. `flutter pub add firebase_remote_config` bumped 12 transitive
  packages (firebase_core 4.15.2). CocoaPods needed a full
  `pod update Firebase FirebaseAnalytics FirebaseCrashlytics` to lift
  FirebaseAnalytics 12.4.0 to ~12.19 before `pod install` would resolve; both
  iOS and macOS Podfile.locks now list `firebase_remote_config (6.7.1)`.
  iOS device build (`-destination generic/platform=iOS`) succeeded, Android
  `flutter build apk --debug` succeeded, `flutter test` 19/19, analyzer
  clean apart from the known speed-test warning.
- Enabling later: create boolean `ads_enabled = true` in the Firebase
  Remote Config console, fill the live AdMob IDs in `ad_config.dart`, set
  `useTestAds = false`, and publish a release build. The flag is read from
  the last activated config on launch and can be flipped from the console
  without an app update after that.
- Observation, not changed: Crashlytics and Analytics are initialized against
  the default Firebase app while only the named `bulbvpn` instance exists, so
  those SDKs may not be collecting. Remote Config avoids that trap; the rest
  was left alone because the legal docs do not promise crash reporting.

## Store submission 1.1.0 (13) — 2026-10-28

Built signed artifacts from this branch and submitted both stores.

- iOS: build 13 uploaded and VALID, attached to 1.1.0; the vertical brag
  video (1080x1920, 20 s) was accepted into the IPHONE_55 preview slot;
  submission `353049b0…` is WAITING_FOR_REVIEW with AFTER_APPROVAL release,
  so it goes live when Apple approves. Version validation had no errors.
- Android: AAB 13 uploaded and a production draft `1.1.0 (13)` committed.
  Play classifies the app as a draft app, and its API only accepts draft
  releases in that state, so the first production release needs one Play
  Console action (Production → 1.1.0 (13) → Send for review). Every upload
  before that approval is API-staged only.
- The Play promo video can only be a YouTube URL, so the brag asset is kept
  at `store/video/brag-1.1.0.mp4` and attached on the App Store side.
- Release mechanics, IDs, and tool gotchas: `docs/store-release-runbook.md`.
  Forward-looking work: `plan/roadmap.md`; release record:
  `plan/release-1.1.0.md`.

## Irancell LTE mobile-data run — 2026-10-28

User report: "on mobile data the VPN app fails to connect." Reproduced on a
Samsung SM-M127G with an Irancell LTE SIM (`rmnet0`, carrier address
`26.61.251.158`) and a debug build from this branch.

### What the carrier does

Raw probes pushed to `/data/local/tmp` (ClientHello to relay IPs, plus
`toybox nc`) showed the same picture for every VPN Gate address tested:

- the TCP handshake completes and `ESTABLISHED` appears in `/proc/net/tcp`;
- the TLS ClientHello is queued (`tx_queue` ~1556 B) and retransmitted;
- nothing ever comes back, for any SNI and on 443 or other ports;
- Cloudflare `1.1.1.1:443` completes TLS in the same second, so the SIM is
  online and TLS itself is not blocked.

Only 2–3 of ~100 catalog relays complete a TLS handshake on this SIM. That is
the network, not the app: a relay whose IP is black-holed cannot be rescued by
SNI choice or packet fragmentation.

### Why the app never got that far

Two independent bugs stacked up:

1. Probes trusted a TCP accept. The warm cache, the pre-connect probe, and the
   server sheet were moved to full TLS handshakes earlier on this branch, so
   this part was already correct on LTE — the shortlist of 8 relays was simply
   all censored (0/8).
2. The handshake deadline did not exist. As documented in failure 15,
   `SecureSocket.connect(timeout:)` only bounds the TCP connect, so each
   censored relay left its future pending for minutes. The warm probe never
   returned, the catalog sweep never started (it is triggered from the warm
   probe), and the server-sheet sweep never logged `[Ping] Measured`. The orb
   then dialled the eight known-dead relays from the catalog order.

### The fix

- `VpnController._probeOneSoftEther` and `ServerPingNotifier._probeOne` wrap
  the whole `SecureSocket.connect` future in `.timeout()` (3 s planning probe,
  4 s sheet probe) and destroy a socket that resolves after the deadline.
- The shortlist being censored triggers the full-catalog TLS sweep
  (`_sweepSoftEther`, waves of 20, stops at two survivors), shared between the
  warm probe and the connect path so the tap does not repeat it.
- Survivors are ordered by handshake RTT, and the sweep result is recorded in
  both `RelayReachability` (5 min, per network) and persistent `RelayMemory`.
- The bundled catalog was regenerated from five VPN Gate API samples (106
  rows, deduped by IP) and the published-list order now tries the
  default-branch list first; the missing hourly Action is recorded as
  failure 16 rather than assumed to work.

### Result on the device

- Launch → warm probe: `0/8 relays reachable` in 3 s.
- Sweep: 99 relays in waves of 20 → `2 relay(s) alive`, exactly the two relays
  that manual TLS probes had found on this SIM: `106.153.7.87` and
  `115.179.206.241` (both JP).
- Tap → first relay was a stale network-memory KR entry that answered auth
  `-5` after ~30 s (and was then forgotten); the second relay connected:
  `session up tun=10.211.1.140 effective=115.179.206.241` — 62 s end to end.
- Real traffic: a Chrome page load moved `tun1` RX +426 KB / TX +26 KB; the
  UI showed `Connected · secure tunnel · Japan`.
- First idle session died at 96 s with `assigned ok, linked=false, carrier
  online`; auto-recovery redialled in 7 s and the new session was up 18 s
  later and carried 3.07 MB.
- Enabling Wi-Fi triggered a clean handover: `cell:rmnet0 ->
  cell:rmnet0|wifi:wlan0:192.168.0`, redial at +5 s, session up at +31 s, and
  a page load moved `tun1` RX +281 KB / TX +79 KB. No manual action was
  needed.

### Remaining gaps on this carrier

- A relay that will reject auth can still burn its full 28 s dial because the
  plain-password retry requires a rejection in under 15 s. Candidate change:
  retry `-5` on the same client regardless of elapsed time, or mark auth
  failures as instant skips in `RelayMemory`.
- The first idle session dropped at 96 s. The hub or the carrier's CGNAT may
  be dropping idle flows even with a 15 s SoftEther keepalive; the recovery
  path handled it, but a real keep-alive probe (small in-tunnel HTTP request)
  would prevent the drop instead of reconnecting after it.
- The exit-IP row shows "measuring through tunnel…" on this SIM because the
  Cloudflare trace host is blocked; the lookup is honest about not knowing.
  Adding a second trace endpoint reachable from Iran would close it.
- The hourly catalog workflow still only exists on feature branches; until it
  is merged, the published list (and `data/vpngate.json` after each release
  build) is the only refresh path.
