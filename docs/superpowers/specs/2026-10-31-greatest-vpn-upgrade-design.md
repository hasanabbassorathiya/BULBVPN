# BULBVPN — "Clear Air" + instant multi-protocol upgrade

**Date:** 2026-10-31
**Status:** Draft for review. No implementation starts until approved.
**Scope:** Full app redesign, protocol engine replacement, instant-connect orchestration, and server supply for iOS + Android.
**Related:** `PRODUCT.md`, `docs/connection-solutions.md`, `docs/lantern-integration-progress.md`

---

## 1. Problem

The TestFlight build did not earn its promise. The app connects through legacy SoftEther relays, spends too long deciding, and leaves the user watching an interface that cannot explain what is happening. The server pool is volunteer infrastructure, so speed and availability are unpredictable. There is no modern censorship-resistant transport.

Lantern's study shows the gap is not a secret protocol. It is preparation: a warm core, background handshakes, cached last-good config, and in-tunnel failover. Those behaviors are reproducible without GPL code.

## 2. Goals

1. **Tap → working internet in seconds.** p50 ≤ 1.5 s on Wi-Fi, ≤ 3 s on Iranian LTE; p95 ≤ 4 s.
2. **No visible disconnect on failure.** In-tunnel outbound switch ≤ 800 ms; network-change recovery ≤ 2 s.
3. **All required protocol families importable and usable:** VLESS+REALITY, XHTTP, VMess, Trojan, Shadowsocks, Hysteria2, WireGuard, plus legacy SoftEther.
4. **A redesigned app that feels calm and instant**, not a dark-neon dashboard.
5. **A sustainable server model:** owned relays, user-owned configs, labeled community pools, and a labeled bootstrap fallback.
6. **Measured, on-device evidence** for every claim in this spec.

## 3. Non-goals

- No new cryptographic protocol. We compose audited cores; we do not invent crypto.
- No Lantern code, no sing-box linking, no Lantern-operated relays.
- No expansion of OpenVPN. It is removed in Phase 2.
- No macOS redesign this cycle; it stays buildable.
- No promise of free, unlimited, fast servers. The product promises a fast *path*, not a free fleet.
- No fabricated testimonials, benchmarks, or user counts.

## 4. Locked product decisions

| Decision | Choice |
|---|---|
| Visual world | **Clear Air** (light-first) with **Night Air** dark variant |
| Build order | App first, then engine |
| Primary user | Iran-first, global-ready |
| Monetization | Free tier + Premium subscription |
| Platforms | iOS + Android first |
| Server supply | Owned + BYOS + **public pools as opt-in labeled source** + VPN Gate bootstrap |
| OpenVPN | Remove |

**Public-pool guardrail.** Community/public relays are never the default, never presented as private, and always carry a visible trust label. The app must not claim "secure" or "private" for traffic that crosses an unvetted relay. The store listing must describe this honestly.

## 5. Legal and licensing boundary

| Component | License | Decision |
|---|---|---|
| libXray wrapper | MIT | Ship; prebuilt AAR + XCFramework |
| Xray-core | MPL-2.0 | Ship with notices; publish modifications to MPL files if any |
| Hysteria2 | MIT | Ship in Phase 5 |
| WireGuard | MIT / Apache-2.0 | Ship via engine outbound first |
| SoftEther | Apache-2.0 | Keep as legacy |
| OpenVPN / OpenVPNAdapter | AGPL-3.0 | Remove in Phase 2 |
| Lantern / radiance / lantern-box / sing-box | GPL-3.0 | Reference only; no code, no servers |

The app remains closed-source. MPL-2.0 obligations are file-level; we will not modify Xray-core source, and we will ship its license and notices in the app's legal screen and repository.

## 6. Architecture

### 6.1 Seams

The current `vpn_controller.dart` is 2,691 lines and owns connection, server selection, memory, and UI state. The upgrade introduces three seams without a big-bang rewrite:

```
UI
 └─ ConnectionState (single source of truth)
     └─ TunnelCoordinator
         ├─ CandidateSelector  (memory + probes + catalog)
         ├─ TunnelEngine       (Xray | SoftEther | Hysteria2)
         ├─ Verifier           (data-path canary)
         └─ ServerCatalog      (owned | byos | community | bootstrap)
```

### 6.2 TunnelEngine contract

```dart
abstract class TunnelEngine {
  String get id;
  Set<VpnProtocol> get supported;
  Future<void> prepare(Candidate c);
  Future<HandshakeResult> race(Candidate c, {required Duration budget});
  Future<void> connect(Candidate c);
  Future<void> switchOutbound(Candidate c);
  Future<void> disconnect();
  Stream<TunnelState> get states;
  Stream<TunnelStats> get stats;
  Future<EngineDiagnostics> diagnostics();
}
```

- **XrayEngine** — libXray, VLESS/REALITY, XHTTP, VMess, Trojan, Shadowsocks, WireGuard outbound. Primary.
- **SoftEtherEngine** — existing native path. Legacy fallback.
- **Hysteria2Engine** — Phase 5, Android first.
- Engines never decide policy; the coordinator does. Engines never report "connected"; the verifier does.

### 6.3 Coordinator state machine

```
idle → preparing → racing → handshaking → verifying → connected
                                      ↘ failed(reason)
connected → degrading → failing_over → verifying → connected
any → network_changed → preparing
```

- Every transition is logged with a timestamp and a reason.
- The UI maps states to plain labels: Preparing, Testing paths, Connecting, Verifying, Connected, Switching, Failed.
- "Connected" is unreachable without a successful canary request through the tunnel.
- A failure always carries one actionable sentence and one retry affordance.

### 6.4 Instant-connect sequence

1. **App launch / foreground.** Hydrate the last network key; load the cached catalog and last-good candidate; start warm probes with real TLS handshakes (already present in `RelayReachability`); rank candidates by network memory, probe result, and trust tier.
2. **Tap.** Take the top three candidates across protocols. Start them staggered at 0 / 150 / 300 ms. First successful handshake wins; cancel the rest. Budget 4 s.
3. **Establish.** Connect the chosen engine, then run the verifier: an HTTPS canary with a 1.5 s budget, through the tunnel, with a response that cannot come from the carrier.
4. **Connected.** Publish state, start stats, and arm the health loop.
5. **Health loop.** Every 20 s, a lightweight through-tunnel check. Two consecutive failures trigger an in-tunnel outbound switch; at most one switch per 30 s.
6. **Network change.** Cancel probes, re-key memory to the new network, reconnect to last-good for that network, verify, publish.
7. **Failure.** Try the next ranked candidate automatically once; then surface a plain-language failure with the last three reasons in diagnostics.

### 6.5 Network memory

Extend `RelayMemory` from relay-only to `(network, protocol, endpoint)` tuples:

- Key: carrier/SSID hash + protocol + endpoint.
- Value: probe latency, handshake success, data-path success, consecutive failures, last success time.
- TTL: 30 days; bounded at 256 entries.
- A cached success still requires a real handshake and canary before "Connected".
- A cached failure demotes, never removes.

### 6.6 Server catalog and trust tiers

| Tier | Source | Label | Default |
|---|---|---|---|
| Fast | Owned relays, signed catalog | "Fast" | Yes for Premium |
| Yours | BYOS import, subscription, QR | "Your server" | Yes if present |
| Community | Public pools | "Community — not private" | No; opt-in |
| Bootstrap | VPN Gate | "Bootstrap — may be slow" | Only when nothing else works |

- The catalog is signed (Ed25519) and cached; refresh every 6 h.
- Each entry carries protocol, transport, endpoint, port set, trust tier, and capability flags.
- The UI never mixes tiers without the label.

### 6.7 Import pipeline

- Parse `vless://`, `vmess://`, `trojan://`, `ss://`, `hysteria2://`, and WireGuard configs.
- Subscription URL fetch with DoH resolution; refresh on demand and every 12 h.
- QR scan and paste.
- Validate before saving; never log credentials; store secrets in secure storage.
- Show a per-entry health check and a one-tap "use this".

### 6.8 Native integration

**Android.** VpnService + libXray AAR. Protect the engine socket; keep the app inside the tunnel; IPv4 default route with IPv6 captured and dropped; split tunneling unchanged.

**iOS.** NEPacketTunnelProvider + libXray XCFramework. Memory budget: steady RSS ≤ 45 MiB. No geo/ruleset loading at startup; trim the config to the active outbound; lazy-load optional features; instrument RSS in diagnostics. If a profile exceeds budget, refuse it and fall back to SoftEther with a logged reason.

### 6.9 Control plane

- Signed catalog mirrored on two domains plus a direct-IP fallback.
- Multi-DoH resolver with a cached IP set; no dependency on domain fronting.
- Catalog fetch is small, signed, and cached; failure never blocks connecting to the last-good candidate.

## 7. Server supply

### 7.1 Owned relays

A provisioning script deploys Xray REALITY (TCP/443), Hysteria2 (UDP), and WireGuard on Oracle Cloud Always Free or a low-cost VPS. It writes a signed catalog entry and a health endpoint. Target: a small number of well-placed exits, not a large fleet. Quality over count.

### 7.2 BYOS

Every user can paste a URI, a subscription URL, or scan a QR. This is the highest-leverage feature for Iranian users and costs no server capacity. Premium can still gate owned fast relays and advanced protocols, but BYOS itself is not paywalled.

### 7.3 Public pools

Opt-in. Fetched from sources that permit client use; filtered by a real handshake and a health check; displayed with a trust label and a first-use warning. No silent default. No "private" claim. No routing of the app's own credentials or payment traffic is special-cased through them; the warning is the contract.

### 7.4 VPN Gate

Remains a labeled bootstrap fallback for the case where nothing else works. It is never marketed as fast.

## 8. Clear Air — design direction

### 8.1 Thesis

The category ships a dark console with a glowing shield and a centered orb. Clear Air refuses that. It is a daylight instrument: the interface is a window whose haze clears when the path opens. The product's promise — censorship feels like nothing — is shown as visibility, not as armor.

### 8.2 World

- **Scene:** a phone at a café window in Tehran at 4 p.m. The screen must stay readable in daylight and calm at night.
- **Ground:** pale atmospheric mist `#E9F0EC`; surface `#F7F4EC`; ink `#0E1B1D`; steel `#5A6A67`.
- **Accent:** horizon teal `#0E7C86` — the only decorative color.
- **Status:** connected emerald `#2E8B6D`; failure coral `#C9553D`; idle graphite `#8A9691`. Status colors never decorate.
- **Night Air:** ground `#0B1416`, surface `#111D1F`, ink `#E9F0EC`, teal `#4FB3BF`, emerald `#59C39A`, coral `#E0715A`.
- **Materials:** a painted haze field, a hairline horizon, a cast sun disc, and matte paper surfaces. No glassmorphism, no neon glow, no gradients used as decoration.
- **Type:** Schibsted Grotesk for display and body; Geist Mono for every number. No Inter, no serif, no system fallback.
- **Icons:** thin-line, 1.5 px stroke, drawn in the same grammar; no emoji flags.

### 8.3 Home composition

- **Top rail (left-aligned):** network name and local time, in mono micro-type. The status word sits directly under it, never centered.
- **Horizon field:** full-bleed, centered at 38% height. A single hairline horizon separates haze above from the data shelf below.
- **The aperture:** a 96 px circular control sitting on the horizon, left of center. It is the only large object. Pressing it clears the haze outward; a teal line sweeps the horizon; when the canary passes, a small sun disc rises 8 px and the line settles.
- **Data shelf:** three real metrics (ping, down, up) in mono, plus the active protocol and server. No fake numbers; a dash when unknown.
- **Destination pill:** above the nav, shows city + protocol + trust tier.
- **Nav:** floating pill with three destinations (Connect, Servers, Speed) and a separate settings action.
- **No centered hero stacks, no three equal cards, no ring/orbit motif.**

### 8.4 Server sheet

An airspace list, not a card grid. Groups: Fast, Your servers, Community, Bootstrap. Each row: country code in mono, city, protocol badge, latency bars, trust label. Selected row: teal left hairline and a pale teal wash. Community rows carry a persistent "not private" label. Pull to refresh re-probes.

### 8.5 Speed test

A horizontal waveform that fills left to right with real readings; ping, download, upload in mono; a small "through the tunnel" note. No machined gauge needle (retired with Filament).

### 8.6 Onboarding, paywall, settings

- **Onboarding:** three frames — what the app does, the VPN permission, and import your own server. One action per frame.
- **Paywall:** free vs Premium side by side, exact prices from the store, no countdown, no fake discount, restore purchases, terms and privacy links.
- **Settings:** calm rows; kill switch, split tunneling, protocol preference, community sources toggle with warning, diagnostics, legal.
- **Diagnostics:** plain-language log with timestamps; copyable support blob; never logs credentials.

### 8.7 Motion

- Spring only; transform and opacity only.
- Signature: haze dissipation (700 ms), horizon sweep (600 ms), sun rise (500 ms).
- Idle: a 3 s breathing opacity on the sun; no constant rotation.
- Reduced motion: cross-fades; no particles; state still readable.

## 9. Delivery plan

### Phase 1 — Clear Air app shell (ship first)

- Direction contract + PRODUCT.md (done) + new theme tokens.
- Rebuild: splash, onboarding, home/connect, server sheet, nav, speed test, settings, routing, logs, legal, paywall.
- Keep the current engine behind the UI; map its states to the new labels honestly.
- Capture iPhone and Android screenshots; verify reduced motion, RTL, and contrast.
- Acceptance: both platforms build; no engine regressions; store screenshots regenerated.

### Phase 2 — Xray engine

- Integrate libXray on Android, then iOS.
- REALITY primary, XHTTP fallback, VMess/Trojan/Shadowsocks import, WireGuard outbound.
- Remove OpenVPN.
- Keep SoftEther as fallback.
- Acceptance: live REALITY handshake on a real device; iOS RSS ≤ 45 MiB; IR LTE connection proven.

### Phase 3 — Instant orchestration

- Candidate racing, verifier, in-tunnel failover, network memory, timing instrumentation.
- Acceptance: the SLOs in §2 measured on the device matrix.

### Phase 4 — Server supply

- BYOS import, subscriptions, QR.
- Owned provisioning script + signed catalog.
- Community pools opt-in with labels; VPN Gate labeled fallback.
- Free/Premium gating.
- Acceptance: import flows work; catalog signature verifies; labels present.

### Phase 5 — Hysteria2 + hardening

- Hysteria2 engine, UDP probe, port hopping.
- iOS memory tuning; store compliance; subscription metadata.
- Acceptance: UDP path works where it survives; no leaks; store-ready.

## 10. Measurement

- **Connection:** tap→first byte p50/p95; success rate over 20 attempts; failure reasons.
- **Failover:** switch time; user-visible disconnect count (target 0).
- **Recovery:** network-change reconnect time.
- **Resources:** iOS RSS; Android memory; 1 h battery drain.
- **Quality:** crash-free sessions; canary failure rate.
- **Devices:** OnePlus (Iran Wi-Fi), Samsung M12 (Irancell LTE), iPhone via TestFlight, plus one non-Iran control.
- **Leaks:** IPv6, DNS, exit IP before/after.
- All evidence recorded in `docs/` with dates and device names. No claim without a measurement.

## 11. Risks

| Risk | Mitigation |
|---|---|
| iOS 50 MiB tunnel limit | Trim config, lazy load, measure, fall back to SoftEther |
| App Review rejects protocol/claims | Honest copy, NE entitlement, no "unblock anything" claims |
| Public relays can read traffic | Opt-in, trust label, first-use warning, never default |
| GPL contamination | No Lantern/sing-box code; license notices for MPL/MIT |
| Owned fleet cost/time | Free-tier VPS first; small number of exits; BYOS carries load |
| Iran whitelisting | REALITY + port agility + per-network memory |
| Store monetization gaps | Fix Play payments and ASC subscription metadata before paid launch |
| UI-first phase feels unchanged | Honest state labels; Phase 2 lands immediately after |

## 12. Open decisions

- Owned-fleet provider and country mix.
- Catalog domain and signing-key custody.
- Persian localization depth (UI only vs full copy).
- Whether the bulb mark survives the identity change.
- Final display typeface licensing.

## 13. Acceptance criteria

1. A user on Iranian LTE can connect and load a page in ≤ 3 s p50, with "Connected" shown only after the canary passes.
2. Every required protocol family is importable, and REALITY connects on a real device.
3. A mid-session relay failure switches in ≤ 800 ms without the UI leaving "Connected".
4. The Clear Air interface ships on iOS and Android with real screenshots and no Filament remnants.
5. No GPL code, no Lantern servers, and no OpenVPN dependency remain.
6. Every performance claim above has an on-device measurement in `docs/`.
