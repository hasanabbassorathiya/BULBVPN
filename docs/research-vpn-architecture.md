# BULBVPN Next-Generation Connection Architecture

**Status:** research complete; decision proposed
**Date:** 2026-10-20
**Scope:** Iran first (Irancell / Hamrah Aval mobile data + Wi‑Fi), then global
**Companion docs:** [`connection-solutions.md`](connection-solutions.md) (what we tried and what happened), [`vpn-issues.md`](vpn-issues.md) (defect log)

---

## 0. Executive decision

Build the next connection layer on **Xray-core** through **`flutter_vless`** (MIT plugin, MPL‑2.0 core), with this order of preference:

1. **VLESS + REALITY over TCP/443** — primary everywhere, especially Iran.
2. **VLESS + XHTTP over TCP/443** — when REALITY connects but is cut, or when a CDN path is useful.
3. **Hysteria2 over UDP/443** — only when a UDP probe succeeds; speed option on lossy mobile links.
4. **SoftEther TLS/443** — existing fallback, kept behind the same supervisor.
5. **OpenVPN TCP/443** — legacy fallback only.

Do **not** build the product on public VPN Gate relays. They are a demo/fallback data source with no SLA, no capacity guarantee, and a high dead/blocked rate. A paid product needs owned or contracted relays, a signed catalog, and a control plane that learns from Iranian clients.

The app should present one truthful state machine, one active tunnel, and one authoritative "connected relay". Protocol switching must be an implementation detail, not a user-visible lie.

**What this does not promise:** immunity to a total national shutdown, a captive portal, or a corporate TLS-inspecting proxy. The promise is: try the path most likely to survive, fail over automatically, and tell the truth when nothing works.

---

## 1. What changed in Iran (2025–2026)

This is the constraint set the architecture must survive.

| Period | What happened | Consequence for us |
|---|---|---|
| June 2025 (12-day war) | "Stealth" shutdown: BGP routes stayed up, but a centralized border filter combined DNS poisoning, HTTP injection, TLS/SNI filtering, protocol allowlisting, and heavy throttling. International traffic dropped ~90%. | A server being "up" means nothing. The client must validate a full data path, not just TCP. |
| Jan 8–18, 2026 | Nationwide total shutdown; IPv6 routes withdrawn; traffic near zero. | No client-side trick works during a total cut. Cache state, stop retrying, and recover cleanly when connectivity returns. |
| Jan 26 – Feb 2026 | "New normal" allowlist: only privileged Iranian source IPs reach the outside; domestic services stay up. | Per-carrier/per-ASN behavior matters. A relay that works on Wi‑Fi may fail on mobile. |
| Feb 28 – May 26, 2026 | Second nationwide shutdown, nearly three months. | Long outages are a product requirement: no battery-burning retry loops, no stale "Connected". |
| May 26, 2026 onward | Partial restoration. Outbound from Iranian residential IPs improved to ~86% in measurements; inbound to Iran remains heavily restricted (~2.8% of global /24s). SNI filtering persists on allowlisted IPs; sensitive domains can trigger TCP RST. | Outbound TCP/443 to a foreign relay is the realistic path. Inbound-hosted Iranian relays are not a general solution. SNI must be benign and believable. |
| 2026 | UDP/QUIC is selectively filtered; protocol-level anomalies appear before full shutdowns. | UDP is an optimization, never the only plan. Hysteria2 must be probed, not assumed. |

### 1.1 The important conclusions

- **TCP/443 with a real TLS handshake is the most survivable transport.** During the harshest periods the allowlist has been described as DNS/HTTP/HTTPS; TCP/443 is the common denominator.
- **SNI is a filter input.** A relay hostname that is already banned is a liability. REALITY avoids this by presenting a benign camouflage SNI, not the relay's own domain.
- **IP reputation matters.** Cloud-provider and known-VPN IP ranges are more likely to be blocked or throttled. Residential/regional hosting is better; rotate IPs.
- **The network is not uniform.** Irancell, Hamrah Aval, fixed-line ISPs, and corporate Wi‑Fi behave differently. Ordering must be learned per network, not hard-coded globally.
- **UDP may work on one carrier and fail on another.** Probe before committing.
- **A total shutdown is unrecoverable from the app.** The correct behavior is to stop, show "Network unavailable", and resume when the OS reports connectivity.

### 1.2 Sources for this section

- arXiv 2507.14183, *Iran's Stealth Internet Blackout: A New Model of Censorship* (July 2025): DNS poisoning, HTTP injection, TLS interception, protocol whitelisting, ~707% rise in VPN demand.
- arXiv 2603.28753, *Iran's January 2026 Internet Shutdown: Public Data, Censorship Methods, and Circumvention Techniques* (March 2026): total shutdown timeline, allowlist, DNS/HTTP/HTTPS/UDP filtering.
- net4people/bbs issue #630, *A Swift Look into the Internet Allowlist in Iran* (June 2026): 2.8% inbound reachability, 86% outbound post-restoration, SNI filtering on allowlisted IPs, TCP RST behavior.
- Cloudflare Radar blog, *Iran's Internet is partially restored* (May 27, 2026): 87-day second shutdown, traffic recovery starting May 26.
- Industry field reports (ProofKit and others) consistently put REALITY first, XHTTP second, and warn that UDP/QUIC is often degraded. Treat these as field reports, not peer-reviewed measurements.

---

## 2. Requirements and threat model

### 2.1 Product requirements

1. **Iran mobile data works** on Irancell and Hamrah Aval, not just Wi‑Fi.
2. **Global reliability**: the same client works on restrictive and open networks.
3. **Fast**: tap-to-connected target ≤ 3 s on a healthy network; ≤ 8 s on a bad one; never a fake success.
4. **Truthful**: connected state, relay, country, and exit IP must match reality.
5. **Graceful degradation**: one blocked protocol must not require the user to understand protocols.
6. **Battery and data sane**: no busy reconnect loops, bounded probes, no background traffic when disconnected.
7. **Pixel-perfect UI**: the state machine must be simple enough to render honestly.

### 2.2 Adversary capabilities to assume

- DNS poisoning and injected block pages.
- SNI-based TCP RST / silent drop.
- IP blocklists for hosting/VPN ranges.
- Protocol fingerprinting (OpenVPN, WireGuard, SoftEther handshakes).
- UDP/QUIC throttling or blocking.
- Active probing of suspected proxy servers.
- Total shutdown (out of scope for bypass; in scope for clean failure).
- Corporate TLS inspection (out of scope for stealth; in scope for a clear error).

### 2.3 Non-goals

- Guaranteed access during a nationwide blackout.
- Bypassing a corporate TLS-intercepting proxy without detection.
- Anonymity against a global adversary. This is a VPN, not Tor.
- Reselling public VPN Gate capacity as a paid service.

---

## 3. Protocol evaluation

Ratings are for the Iran-first use case. "DPI" means resistance to fingerprinting and active probing; "UDP" means dependence on UDP passing.

| Protocol / transport | Port | DPI / probing resistance | UDP needed | Speed on lossy mobile | Client maturity | License | Verdict |
|---|---|---|---|---|---|---|---|
| **VLESS + REALITY (RAW)** | TCP/443 | **Excellent.** TLS 1.3 handshake to a real site; unauthenticated probes see the camouflage site; no own certificate/domain. | No | Good | Xray-core, mature | MPL‑2.0 | **Primary** |
| **VLESS + XHTTP** | TCP/443 | **Very good.** Looks like HTTP/2 or HTTP/3 traffic; can ride a CDN. More moving parts; memory cost on iOS. | No (H2) / Yes (H3) | Good | Xray-core, newer | MPL‑2.0 | **Secondary** |
| **Hysteria2** | UDP/443 | Good obfuscation (Salamander), but UDP is a filter target; active probing needs correct auth. | **Yes** | **Excellent** (BBR/Brutal) | Xray-core now has hysteria outbound/transport; official core also mature | MIT | **Opportunistic** |
| **Trojan** | TCP/443 | Good; looks like HTTPS with a real cert. Needs a domain and cert; SNI can be blocked. | No | Good | Xray-core | MPL‑2.0 | Fallback |
| **NaiveProxy** | TCP/443 | Excellent HTTP/2 CONNECT mimicry; needs Caddy + domain; Chromium network stack. | No | Good | Mature but heavier integration | BSD-style | Fallback if REALITY is blocked |
| **WireGuard / AmneziaWG** | UDP | Vanilla WG is fingerprinted and blocked; Amnezia obfuscation helps but is not invisible. | **Yes** | Excellent when it passes | Mature | MIT / GPL (Amnezia) | Optional, not primary |
| **SoftEther TLS** | TCP/443 | Moderate. TLS wrapper helps, but the protocol has recognizable patterns; public relays are often dead/blocked. | No | Moderate | Existing in app | Apache‑2.0 | **Legacy fallback** |
| **OpenVPN TCP** | TCP/443 | Weak against modern DPI; TCP-over-TCP meltdown on loss. | No | Poor on loss | Existing in app | GPL | **Last resort** |
| **Shadowsocks** | TCP/UDP | Weak against active probing unless AEAD + obfs; not a primary. | Optional | Good | Mature | Apache‑2.0 | Import-only |
| **VMess** | TCP/WS | Older; more fingerprintable than VLESS. | No | Good | Mature | MPL‑2.0 | Import-only |
| **Domain fronting** | TCP/443 | **Not reliable.** Major CDNs have largely disabled it; SNI/Host mismatch is detectable. | No | n/a | n/a | n/a | **Do not build on it** |
| **ECH** | TCP/443 | Hides SNI to an ECH-capable CDN. Not a full bypass; the outer SNI/IP can still be blocked; client and CDN support required. | No | n/a | Growing | n/a | Optional hardening, not a strategy |

### 3.1 Why REALITY is first

- The client's SNI is a **benign camouflage site**, not the relay's domain. A banned relay domain is irrelevant.
- The server has **no own certificate** to leak or rotate. It borrows the target site's TLS identity.
- Unauthenticated probes are proxied to the real target, so the server looks like a normal website.
- It is **TCP/443**, the path that survives the harshest Iranian filtering described in the literature.
- XTLS Vision reduces overhead and improves throughput on long-lived connections.

### 3.2 Why Hysteria2 is not first

- It is UDP. Iran selectively filters UDP/QUIC; a protocol that depends on UDP cannot be the only plan.
- It is excellent on lossy mobile links when UDP passes; use it as an opportunistic upgrade, chosen after a successful UDP probe.
- It can be faster than TCP but can also be the first thing a carrier blocks. Never make it the default without evidence.

### 3.3 Why public VPN Gate is not a product

- No SLA, no capacity guarantee, no privacy guarantee, and a high rate of dead or blocked relays (we observed `Hello response status: 404`, `-5`, `-4` in a single session).
- The relay operator can observe traffic; a paid product cannot put users on unknown volunteers' servers by default.
- It is useful as a bootstrap/demo fallback, not as the core.

---

## 4. Client core evaluation

| Option | What it is | Pros | Cons | License | Decision |
|---|---|---|---|---|---|
| **`flutter_vless` + Xray-core** | Flutter plugin wrapping Xray-core on Android/iOS/macOS/Windows | One core for VLESS REALITY, XHTTP, Hysteria2, Trojan, SS, WireGuard import; Dart API; VPN and proxy modes; active project | Own VpnService / Network Extension target; iOS 50 MB extension limit; Hysteria2 artifact must be validated; must unify with existing SoftEther service | MIT plugin / MPL‑2.0 core | **Primary** |
| **sing-box + `libbox`** | Universal proxy core | One core, many protocols, active | **GPL‑2.0/3.0** (copyleft risk for a closed-source paid app); iOS memory also tight | GPL | Avoid unless open-sourcing |
| **mihomo / Clash.Meta** | Proxy core | Many protocols, rules | GPL; heavier; less ideal for a VPN product | GPL | Avoid |
| **libXray / gomobile** | Xray-core as a library | Same core, more control | More native integration work; still need packet tunnel plumbing | MPL‑2.0 | Fallback if plugin limits us |
| **NEAXCE** | Swift/C network extension proxy | Low memory, native | Alpha; partial REALITY support; not production-ready | Apache‑2.0 | Watch, not now |
| **Existing SoftEther + OpenVPN** | Current stack | Already works on Android | Two protocols, public relays, poor IR reliability, no seamless failover | Apache/GPL | **Legacy fallback** |

### 4.1 Licensing notes

- **Xray-core is MPL‑2.0.** MPL is file-level copyleft: if we modify MPL-covered files, we must publish those modified files. Shipping an unmodified binary/library is compatible with a closed-source app, provided we include the license and notices and make the source available. Do not strip notices.
- **`flutter_vless` is MIT.** Keep the copyright notice.
- **Hysteria2 official is MIT.** Xray's Hysteria implementation is MPL‑2.0.
- **sing-box is GPL.** Linking it into a closed-source app triggers copyleft obligations. This is why it is not the primary choice.

### 4.2 Why not keep building on SoftEther

SoftEther got us a working Android data path, and it stays as a fallback. But:

- It is a full VPN protocol with its own handshake and recognizable traffic patterns.
- The public relay pool is unreliable and not a business.
- It has no in-tunnel multi-outbound failover. Switching relays means tearing down the tunnel.
- It cannot present a benign SNI the way REALITY can.

Keep it, wrap it behind the same `TunnelEngine` interface, and stop making it the primary.

---

## 5. Recommended architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Flutter UI (one truthful state machine)                     │
│  status: idle | preparing | connecting | connected |         │
│          switching | reconnecting | blocked | error          │
│  connectedRelay: id, country, protocol, exitIp, latency      │
└───────────────────────────┬─────────────────────────────────┘
                            │ intents / state
┌───────────────────────────▼─────────────────────────────────┐
│ TunnelSupervisor (Dart)                                      │
│  - owns the active engine + epoch/generation                 │
│  - pre-connect race + health cache                           │
│  - bounded reconnect, offline refund, manual-disconnect guard│
│  - never infers country from the picker                      │
└───────────────┬───────────────────────────────┬──────────────┘
                │                               │
┌───────────────▼──────────────┐  ┌─────────────▼──────────────┐
│ XrayEngine (primary)         │  │ SoftEtherEngine (fallback) │
│  - Xray-core via flutter_vless│  │  - existing VpnService /   │
│  - VLESS REALITY / XHTTP     │  │    PacketTunnel            │
│  - Hysteria2 (opportunistic) │  │  - OpenVPN TCP fallback    │
│  - in-tunnel observatory +   │  │                            │
│    balancer (leastPing)      │  │                            │
└───────────────┬──────────────┘  └─────────────┬──────────────┘
                │                               │
┌───────────────▼───────────────────────────────▼──────────────┐
│ OS tunnel: Android VpnService / iOS+macOS NEPacketTunnel     │
│  one active tunnel; switching engines = stop old, start new  │
└──────────────────────────────────────────────────────────────┘
```

### 5.1 The supervisor contract

The supervisor is the only place that decides "connected". The UI never reads engine status directly.

```
Idle
  └─ user taps Connect
Preparing
  ├─ no network → Blocked(offline), retry on connectivity
  ├─ choose candidate order (last-good → measured → default)
  └─ start engine
Connecting
  ├─ engine reports handshake OK → DataPathProbe
  ├─ timeout / error → next candidate (bounded)
  └─ user cancels / manual disconnect → Idle
DataPathProbe
  ├─ HTTP 204 through tunnel OK → Connected(relay, latency, exitIp)
  └─ fail → Reconnecting (bounded)
Connected
  ├─ liveness OK → stay
  ├─ relay dies → Switching (in-tunnel) or Reconnecting (cross-engine)
  └─ OS revoke / manual disconnect → Idle
Switching
  ├─ Xray balancer selects a healthy outbound → Connected(new relay)
  └─ no healthy outbound → Reconnecting
Reconnecting
  ├─ attempt 1 @ 2 s, 2 @ 8 s, 3 @ 20 s
  ├─ offline → postpone + refund attempt, recheck every 5 s
  └─ exhausted → Error with a copyable diagnostic
```

Rules:

- `connected` requires a **data-path probe**, not just a handshake.
- `connectedRelay` comes from the engine's active outbound, reconciled against the catalog. Unknown IP → "Private relay", no country.
- Country is never inferred from the server picker.
- A manual disconnect cancels all in-flight work. Late successes are torn down.
- A manual relay switch during a dial is queued and runs after the current attempt unwinds.
- iOS/Android network changes are handled by the OS callback; do not add a third-party connectivity plugin that crashes on iOS 27 beta.

### 5.2 Fast path: make it feel instant

1. **Pre-connect race.** On app launch and network change, race the top 5–8 candidates in parallel with a 700–900 ms budget:
   - TCP connect to port 443, then a TLS ClientHello with the configured camouflage SNI (REALITY).
   - QUIC Initial / Hysteria2 handshake only if a UDP probe says UDP passes.
   Cache the winner per `(network, carrier, protocol)`.
2. **Start the core with a known-good outbound.** Do not let the core do DNS or sequential fallback on the critical path.
3. **Keep the TUN up across Xray outbound changes.** The balancer/observatory switches outbounds inside the same tunnel; no VpnService restart.
4. **Warm the engine UI.** Show "Connecting" only after the user intent; show the candidate name and a progress stage ("Handshake · Japan") without claiming success.
5. **Cache the last-good relay per network** and verify it before use. A stale last-good is worse than a fresh race.

Target numbers (healthy network, nearby relay):

| Stage | Target |
|---|---|
| Engine start (Xray) | 150–400 ms |
| TCP + TLS REALITY handshake | 150–600 ms |
| TUN setup | 50–150 ms |
| Data-path probe (204) | 100–300 ms |
| **Tap → Connected** | **≤ 1.5–3 s** |
| In-tunnel failover | ≤ 1–2 s (no user action) |

SoftEther's current ~10 s dial is a fallback path, not the target.

### 5.3 In-tunnel failover with Xray

Xray supports `observatory` / `burstObservatory` plus a `balancer`:

```json
{
  "observatory": {
    "subjectSelector": ["relay-"],
    "probeUrl": "https://www.gstatic.com/generate_204",
    "probeInterval": "30s",
    "enableConcurrency": true
  },
  "routing": {
    "balancers": [
      {
        "tag": "auto",
        "selector": ["relay-"],
        "fallbackTag": "relay-last-good",
        "strategy": { "type": "leastPing" }
      }
    ],
    "rules": [
      { "type": "field", "network": "tcp,udp", "balancerTag": "auto" }
    ]
  }
}
```

Notes:

- `leastPing` requires the observatory; nodes not covered are excluded. Always set `fallbackTag`.
- `leastLoad` supports `expected`, `maxRTT`, `tolerance`, and cost weights; use it later if ping alone is too noisy.
- The observatory's fixed-interval probes can be fingerprinted. Use mux or randomized intervals where possible; do not probe too aggressively.
- If the plugin does not expose per-outbound stats, add a small native stats query or infer the active outbound from byte counters. The UI's "connected relay" must be based on the active outbound, not the desired one.

### 5.4 Truthful exit IP

- Measure the exit IP **through the tunnel** with an HTTPS endpoint that returns the client IP (e.g., `https://api.ipify.org?format=json` or a self-hosted endpoint).
- On Android, the in-app lookup must be **excluded from the TUN** (`addDisallowedApplication`) or performed by the native service with `protect()`; otherwise it may report the carrier IP. If it cannot be measured reliably, hide the value and say "not measured on this device" — never show the carrier IP as the exit.
- On iOS/macOS, the lookup goes through the tunnel by default; verify.
- Cache the exit IP with the relay identity; clear it on disconnect/relay change.
- If the effective relay IP returned by the native layer differs from the dialed IP, reconcile it against the catalog; unknown → "Private relay", no country.

### 5.5 Engine unification

`flutter_vless` has its own Android `VpnService` and iOS `XrayTunnel` extension. The app already has `SoftEtherVpnService` and `PacketTunnel`. There can be only one active VPN tunnel per device.

Rules:

- Add a `TunnelCoordinator` mutex. Only one engine may be started or stopped at a time.
- Switching engines: stop the old engine, wait for its teardown callback, then start the new one. Do not race two `VpnService`s.
- On iOS, either:
  - **A. Two providers** (`PacketTunnel` for SoftEther, `XrayTunnel` for Xray) selected by `NETunnelProviderManager`; simpler to integrate, two targets to sign and review; or
  - **B. One provider** that embeds both cores; best UX, most maintenance. Start with A, plan B only if review/UX demands it.
- On Android, two services are fine as long as the coordinator serializes them. The system deactivates the old VPN when a new one starts, so an explicit stop + wait is safer.
- Do not remove `addDisallowedApplication` for the exit-IP lookup; it is an IR reliability feature, not a hack.

---

## 6. Control plane and domain-to-IP

### 6.1 What GitHub Actions can and cannot do

GitHub Actions is excellent for **build, test, sign, and publish**. It is not a relay and should not be a general-purpose scraper.

The GitHub Additional Product Terms say Actions should not be used for, among other things:

- "Any activity that places a burden on our servers, where that burden is disproportionate to the benefits provided to users (for example, don't use Actions as a content delivery network or as part of a serverless application...)"
- "If using GitHub-hosted runners, any other activity unrelated to the production, testing, deployment, or publication of the software project associated with the repository."

The current hourly VPN Gate scraper is therefore a **ToS risk**. It is also a single point of failure.

**Recommendation:**

| Job | Where |
|---|---|
| Build, test, analyze, sign, release APK/IPA | GitHub Actions (allowed, intended) |
| Generate a signed catalog from committed data | GitHub Actions (allowed) |
| Scrape public relay lists every hour | Cloudflare Worker Cron or a small VPS (migrate) |
| Health-check REALITY/Hysteria2 endpoints (raw TCP/TLS/QUIC) | Small VPS or canary devices; Workers cannot do full raw TLS/QUIC health checks |
| Serve the signed catalog | GitHub Pages / jsDelivr / Cloudflare R2 (multiple mirrors) |
| Collect anonymous client telemetry | Cloudflare Worker + D1/KV (control plane only; not a proxy) |
| Publish per-carrier recommendations | Worker cron + signed JSON |

Do not use Actions as a VPN relay. It is ephemeral, monitored, and against the terms. Do not use Cloudflare Workers to proxy user traffic; use them for API/KV/cron only.

### 6.2 Signed catalog

The app must never trust an unsigned server list. A compromised catalog can redirect users to an attacker's relay.

```json
{
  "version": 3,
  "generated_at": "2026-10-20T12:00:00Z",
  "expires_at": "2026-10-21T12:00:00Z",
  "servers": [
    {
      "id": "tr-ist-01",
      "protocol": "vless",
      "address": "203.0.113.10",
      "port": 443,
      "sni": "www.microsoft.com",
      "host": "www.microsoft.com",
      "network": "tcp",
      "security": "reality",
      "flow": "xtls-rprx-vision",
      "public_key": "BASE64_X25519_PUBLIC_KEY",
      "short_id": "0123456789abcdef",
      "fingerprint": "chrome",
      "country": "TR",
      "city": "Istanbul",
      "asn": 9121,
      "resolved_ips": ["203.0.113.10", "203.0.113.11"],
      "resolved_at": "2026-10-20T10:00:00Z",
      "tags": ["ir-mobile", "low-latency"]
    }
  ],
  "recommendations": {
    "IR|Irancell|mobile": ["tr-ist-01", "tr-ist-02", "de-fra-01"],
    "IR|HamrahAval|mobile": ["tr-ist-02", "ae-dxb-01", "de-fra-01"],
    "default": ["tr-ist-01", "de-fra-01"]
  },
  "signature": "BASE64_ED25519_SIGNATURE"
}
```

Rules:

- Sign the canonical JSON (sorted keys, no whitespace) with Ed25519. Embed the public key in the app.
- Reject expired, unsigned, or malformed catalogs. Keep the last valid catalog.
- `resolved_ips` are hints, not truth. Re-probe on the device.
- `recommendations` are hints from telemetry, not a contract. The device's own probes win.

### 6.3 Domain-to-IP: what it can and cannot fix

**It can fix:**

- DNS poisoning of a relay domain (resolve via multiple DoH resolvers, compare answers, use the IP).
- A banned relay **domain** when the IP is still reachable (connect by IP, keep the correct SNI for TLS).
- Slow or hijacked system DNS (bypass it with DoH to known IPs).
- A dead CDN edge (rotate IPs).

**It cannot fix:**

- A blocked **IP** (rotate to another IP/relay).
- A blocked **SNI** (use REALITY's benign camouflage SNI, or rotate the domain).
- A total shutdown.
- A corporate TLS-inspecting proxy that breaks end-to-end TLS.

**Implementation:**

1. At import/refresh, resolve the domain with at least three DoH endpoints, addressed by **IP literal** to avoid the poisoned system DNS:
   - `https://1.1.1.1/dns-query` (Cloudflare; cert includes the IP)
   - `https://8.8.8.8/resolve` (Google; cert includes the IP)
   - `https://9.9.9.9/dns-query` (Quad9)
   - Optional: `https://94.140.14.14/dns-query` (AdGuard)
2. Compare A/AAAA answers. Reject private, loopback, link-local, `0.0.0.0`, and known Iranian block-page ranges (e.g., `10.10.34.34/35`). Use majority consensus; if no majority, keep the previous IPs and mark them "unverified".
3. Cache with TTL (respect the DNS TTL, min 5 min, max 6 h). Store `resolved_at`.
4. At connect, race the cached IPs plus any fresh ones. Pick the fastest that completes the protocol handshake.
5. Never resolve on the critical path if a cached IP exists and is fresh.
6. If all IPs fail, mark the relay unhealthy and move on. Do not spin.

**REALITY-specific:** the relay's own domain can be banned and it does not matter; the client's SNI is the camouflage site. The server IP is the only address that must be reachable. This is the cleanest answer to "banned free server domains".

**CDN/XHTTP-specific:** the SNI is the CDN hostname. If it is banned, use a different CDN domain or a new subdomain. Domain fronting is not a reliable fallback; ECH is optional hardening, not a guarantee.

### 6.4 Telemetry that actually helps

Collect only what improves routing, and make it opt-in:

```
{
  "app_version": "1.0.0+10",
  "platform": "android",
  "network": "mobile",
  "carrier": "Irancell",
  "asn": 44244,
  "protocol": "vless-reality",
  "server_id": "tr-ist-01",
  "result": "success|timeout|tls_rst|auth_fail|udp_blocked",
  "handshake_ms": 420,
  "ttfb_ms": 610,
  "throughput_kbps": 8400,
  "ts_bucket": "2026-10-20T12"
}
```

- No IP address, no precise location, no device ID, no browsing history, no persistent identifier.
- Rate-limit and validate server-side; never log raw IPs.
- Aggregate by `(country, carrier/ASN, network_type, protocol, server_id)`.
- Publish signed recommendations hourly; the app uses them only as a hint.
- Iran-specific ground truth comes from consented canary devices and client reports, not from GitHub runners outside Iran.

---

## 7. Server fleet and operations

### 7.1 Locations

Prioritize low RTT and diverse transit to Iran:

- **Turkey (Istanbul)** — lowest RTT for many Iranian networks; good for REALITY.
- **UAE (Dubai)** — low RTT; check regional filtering/regulatory risk.
- **Armenia / Georgia** — short paths, less common VPN ranges.
- **Germany / Netherlands / Finland** — stable, good capacity; higher RTT.
- **France / UK** — global fallback.
- Avoid placing all relays in one ASN or one cloud provider; a single IP-range block should not take the product down.

### 7.2 REALITY server recipe

- Xray-core, TCP/443, TLS 1.3, H2/HTTP1.1.
- `dest`/`target` = a benign site in the same region/ASN, TLS 1.3 + H2, not blocked in Iran, stable, with a valid cert. Test with `openssl s_client -connect target:443 -tls1_3 -alpn h2`.
- `serverNames` = the camouflage site's names; `privateKey`/`publicKey` from `xray x25519`; several `shortIds`.
- `flow: xtls-rprx-vision` on the client and server.
- Do not use Cloudflare as the camouflage target if Cloudflare is blocked/throttled in Iran.
- Keep the target's certificate chain plausible; do not use a self-signed cert.
- Monitor: TCP accept, TLS handshake success, authenticated request success, throughput. A server that accepts TCP but never authenticates is not healthy.

### 7.3 Hysteria2 recipe

- UDP/443 (or a high port with port hopping), Salamander obfs, strong password.
- BBR congestion by default; Brutal only if you control the path and accept unfairness.
- Masquerade as a normal HTTP/3 site.
- Health: QUIC handshake + authenticated request + throughput. Do not mark healthy on a UDP port-open test alone.
- Deploy only in regions where a UDP probe from Iranian carriers succeeds; otherwise it is wasted.

### 7.4 SoftEther/OpenVPN

- Keep the existing code as a fallback, but stop adding new features.
- Do not depend on public VPN Gate for paid users.
- If kept, pin known-good relays and health-check them; the current `Hello response status: 404` / `-5` / `-4` failures are exactly the dead-relay problem.

---

## 8. Platform constraints

### 8.1 Android

- Only one `VpnService` tunnel at a time; starting a new one deactivates the old.
- `addDisallowedApplication` is required for the in-app exit-IP lookup and for protecting the carrier path; keep it.
- `setUnderlyingNetworks` + `ConnectivityManager` callbacks for network changes.
- Always-on VPN / "Block connections without VPN" is a user/system setting; the app cannot silently enable it. Document it as a recommendation, not a guarantee.
- Android 14+ foreground service rules; the existing `SoftEtherVpnService` already handles the notification. The Xray engine needs an equivalent foreground notification if it uses its own service.
- `FLAG_SECURE` is a privacy feature; do not treat black screenshots as a UI bug. Add a debug-only bypass for QA.

### 8.2 iOS / macOS

- `NEPacketTunnelProvider`; App Store guideline 5.4 requires `NEVPNManager`, organization enrollment, a clear data-collection declaration, no selling user data, and compliance with local law.
- **Memory limit: 50 MiB for a packet tunnel provider** (Xray issue #4422). This is the hardest platform constraint.
- Xray with large `geosite`/`geoip` files can fail to start or be jetsam-killed. XHTTP upload buffers can also spike memory.
- Mitigations:
  - Prefer **VLESS REALITY RAW** on iOS; defer XHTTP.
  - Do not load full `geosite`/`geoip`. Use a minimal rule set or route everything through the proxy except private/local.
  - Cap H2/XHTTP buffers (the plugin has patches; verify the version).
  - Measure with `Instruments` / `os_proc_available_memory`; add a memory watchdog that restarts the core gracefully.
  - If REALITY + minimal rules still exceeds the budget, evaluate a lighter core for iOS only (NEAXCE is not production-ready yet) or reduce features.
- macOS packet tunnel has more memory headroom but the same provider model.
- Two providers (SoftEther + Xray) are possible; only one active. Keep the App Group/keychain consistent.

### 8.3 Windows / desktop

- Not currently shipped. `flutter_vless` supports Windows with a local `xray.exe`; a future desktop build can reuse the same catalog and supervisor. Do not block the architecture on it.

---

## 9. Legal, sanctions, and store risk (not legal advice)

- **U.S. sanctions:** 31 CFR § 560.540 authorizes certain services, software, and hardware incident to communications over the internet with Iran, subject to conditions and exclusions (e.g., the Government of Iran). Iran General License D‑2 has covered certain VPN client software/services. The exact scope changes; **retain counsel and document your compliance position** before selling to Iranian users. Do not rely on this summary.
- **Payments:** Iranian payment rails are restricted; a paid product needs a lawful billing path and a clear refund policy. Do not build a business model that depends on circumventing sanctions.
- **Iran domestic law:** VPN use/distribution may be illegal or restricted; users and the operator face risk. The app should not encourage illegal activity; present itself as a privacy/security tool and comply with applicable law.
- **Apple 5.4:** organization account, `NEVPNManager`, data declaration, no data sale, local-law compliance. A VPN app that violates local law can be removed. This is a real distribution risk in Iran.
- **Google Play:** VPN apps must use `VpnService`, disclose data collection, and not use the permission for ad fraud or unrelated purposes. Check the current Developer Program Policy before shipping.
- **Export controls:** encryption software may require classification/notification; answer App Store export-compliance questions accurately.
- **GitHub/Cloudflare ToS:** see §6.1. Do not turn either into a relay.

---

## 10. Roadmap

### Phase 0 — Instrument and verify (3–5 days)

- Add the research doc and update `connection-solutions.md`.
- Fix/verify the effective relay IP byte order (done; see §11).
- Add a debug-only screenshot bypass and capture the connected/error UI.
- Verify copied diagnostics: header + native service log + full Dart log.
- Add a protocol/health probe interface and a per-network candidate cache.

**Exit:** logs and diagnostics are trustworthy; no stale state.

### Phase 1 — Xray engine + REALITY (1–2 weeks)

- Add `flutter_vless`; wire the Android/iOS/macOS targets.
- Implement `XrayEngine` behind `TunnelEngine`; one active outbound for the first cut.
- Import a REALITY profile; connect; measure tap→connected; verify exit IP.
- Keep SoftEther as fallback; serialize with `TunnelCoordinator`.
- iOS: REALITY RAW, minimal rules, memory measurement.

**Exit:** REALITY connects on Android (Wi‑Fi + one IR carrier if available), iOS simulator/device, macOS; SoftEther still works; no fake connected state.

### Phase 2 — Fast path + truthful failover (1–2 weeks)

- Pre-connect race (top 5–8, 700–900 ms).
- Last-good per network + verification.
- Xray observatory + balancer + `fallbackTag`.
- Active outbound → `connectedRelay`; exit IP through tunnel.
- Bounded reconnect; offline refund; manual-disconnect cancellation.

**Exit:** tap→connected ≤ 3 s on a healthy network; relay death switches in ≤ 2 s; UI never shows the wrong country.

### Phase 3 — Control plane (1–2 weeks)

- Move the scraper off GitHub Actions to a Worker/VPS.
- Signed catalog (Ed25519) + multiple mirrors.
- Multi-DoH resolver with IP literals and consensus.
- Opt-in telemetry + signed per-carrier recommendations.
- Canary device(s) in Iran.

**Exit:** a poisoned/blocked catalog cannot redirect users; the app gets useful ordering hints; the scraper is ToS-safe.

### Phase 4 — Hysteria2 + polish (1–2 weeks)

- UDP probe; Hysteria2 only when it passes.
- Per-carrier ordering; protocol badge; "Switching relay…" state.
- iOS memory hardening; XHTTP only if it fits.
- Pixel-perfect connected/error/switching screens; copyable diagnostics.

**Exit:** Hysteria2 improves speed where UDP works without hurting reliability; UI is truthful and polished on all devices.

---

## 11. Current verified state (2026-10-20)

- Android SoftEther data path works: `tun1`, default route, `ping 1.1.1.1` ~600 ms.
- Latest dial: `219.100.37.195` → effective relay `219.100.37.11` (JP), connect ~10.2 s.
- **Effective relay IP byte-order bug fixed:** native returns `in_addr.s_addr` in network byte order; `formatEffectiveIp()` reverses bytes before formatting. Verified on device: `effective=219.100.37.11`, country `JP`.
- Last-good now stores `219.100.37.11` and `public-vpn-47.opengw.net`; the old byte-swapped `195.37.100.219` is gone.
- Notification is truthful; `no_screenshot` is a privacy feature, not a UI failure.
- Remaining known issues: public relay dead/404/-5/-4 rate; Android in-app exit IP cannot be measured while excluded from the TUN (UI hides it); iOS/macOS runtime not yet fully tested; iPad Developer Mode off.

---

## 12. Risks and open questions

| Risk | Impact | Mitigation |
|---|---|---|
| Public relays die/block | Users cannot connect | Own relays; signed catalog; health checks; fallback |
| REALITY blocked on a carrier | Primary fails | XHTTP/CDN fallback; Hysteria2 if UDP; SoftEther last |
| UDP blocked | Hysteria2 unusable | Probe first; never default to UDP |
| iOS 50 MB limit | Extension killed | REALITY RAW; minimal rules; memory watchdog; measure |
| Two VPN services/targets | Races, review complexity | `TunnelCoordinator`; one active; consider one provider long-term |
| Catalog compromise | Traffic redirection | Ed25519 signature; pinned key; expiry; multiple mirrors |
| GitHub Actions ToS | Account/repo risk | Move scraping/health to Worker/VPS; Actions only for CI |
| Sanctions/store law | Business/distribution risk | Counsel; organization account; clear privacy/data policy |
| Corporate TLS inspection | Cannot connect | Clear error; do not promise; suggest another network |
| Total shutdown | No service | Clean failure; no battery burn; resume on connectivity |

**Open questions:**

1. Which Iranian carriers/ASNs allow REALITY on TCP/443 today? Need canary measurements.
2. Does the packaged Xray-core in `flutter_vless` include the Hysteria2 outbound/transport? Validate with `xray run -test` and a live handshake.
3. Can we deploy one owned relay (Turkey/Armenia) for real end-to-end testing? Without it, we are testing against public relays.
4. iOS 50 MB: does REALITY RAW + minimal rules fit reliably on iOS 16/17/18? Measure before promising.
5. Do we keep two iOS providers or unify into one? Decide after the first Xray build.
6. What is the lawful billing/distribution path? Counsel before launch.

---

## 13. Sources

### Primary measurements / research

- Aryapour, A. *Iran's Stealth Internet Blackout: A New Model of Censorship.* arXiv:2507.14183, July 2025. <https://arxiv.org/abs/2507.14183>
- *Iran's January 2026 Internet Shutdown: Public Data, Censorship Methods, and Circumvention Techniques.* arXiv:2603.28753, March 2026. <https://arxiv.org/abs/2603.28753>
- net4people/bbs issue #630, *A Swift Look into the Internet Allowlist in Iran*, June 2026. <https://github.com/net4people/bbs/issues/630>
- Cloudflare Radar, *Iran's Internet is partially restored*, May 27, 2026. <https://blog.cloudflare.com/iran-internet-partially-restored-may-2026/>

### Protocol / client documentation

- Xray-core, REALITY transport. <https://xtls.github.io/en/config/transports/reality.html>
- Xray-core, XHTTP transport. <https://xtls.github.io/en/config/transports/xhttp.html>
- Xray-core, Hysteria outbound. <https://xtls.github.io/en/config/outbounds/hysteria.html>
- Xray-core, Hysteria transport. <https://xtls.github.io/en/config/transports/hysteria.html>
- Xray-core, Observatory. <https://xtls.github.io/en/config/observatory.html>
- Xray-core, Routing / Balancer. <https://xtls.github.io/en/config/routing.html>
- `flutter_vless` documentation (platform guides, compatibility, security). <https://github.com/XIIIFOX/flutter_vless>
- `flutter_vless` protocol roadmap. <https://github.com/XIIIFOX/flutter_vless/blob/main/doc/protocol_support_roadmap.md>
- Xray-core issue #4422, *iOS packet tunnel provider limit* (50 MiB). <https://github.com/XTLS/Xray-core/issues/4422>
- Hysteria2 official docs. <https://v2.hysteria.network/>

### Platform / policy

- Android `VpnService` reference (one active VPN, user consent, system notification). <https://developer.android.com/reference/android/net/VpnService>
- Apple App Store Review Guidelines, §5.4 VPN Apps. <https://developer.apple.com/app-store/review/guidelines/>
- GitHub Terms for Additional Products and Features (Actions limitations). <https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features>
- 31 CFR § 560.540, *Certain services, software, and hardware incident to communications.* <https://www.ecfr.gov/current/title-31/part-560/section-560.540>
- OFAC, Iranian Transactions and Sanctions Regulations (current general licenses). <https://ofac.treasury.gov/>

### Licensing

- Xray-core: MPL‑2.0. <https://github.com/XTLS/Xray-core/blob/main/LICENSE>
- `flutter_vless`: MIT. <https://github.com/XIIIFOX/flutter_vless/blob/main/LICENSE>
- Hysteria2: MIT. <https://github.com/apernet/hysteria>
- sing-box: GPL‑3.0 (not selected). <https://github.com/SagerNet/sing-box>

---

## Appendix A — Xray REALITY client sketch

```json
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "tun-in",
      "protocol": "tun",
      "settings": { "mtu": 1500, "stack": "gvisor" },
      "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
    }
  ],
  "outbounds": [
    {
      "tag": "relay-tr-ist-01",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "203.0.113.10",
            "port": 443,
            "users": [
              {
                "id": "UUID",
                "encryption": "none",
                "flow": "xtls-rprx-vision"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "serverName": "www.microsoft.com",
          "fingerprint": "chrome",
          "publicKey": "BASE64_X25519_PUBLIC_KEY",
          "shortId": "0123456789abcdef",
          "spiderX": "/"
        }
      }
    },
    { "tag": "direct", "protocol": "freedom" },
    { "tag": "block", "protocol": "blackhole" }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      { "type": "field", "ip": ["geoip:private"], "outboundTag": "direct" },
      { "type": "field", "network": "tcp,udp", "balancerTag": "auto" }
    ],
    "balancers": [
      {
        "tag": "auto",
        "selector": ["relay-"],
        "fallbackTag": "relay-tr-ist-01",
        "strategy": { "type": "leastPing" }
      }
    ]
  },
  "observatory": {
    "subjectSelector": ["relay-"],
    "probeUrl": "https://www.gstatic.com/generate_204",
    "probeInterval": "30s",
    "enableConcurrency": true
  }
}
```

Notes:

- Replace the UUID, public key, short ID, address, and camouflage SNI with real values.
- On iOS, avoid full `geosite`/`geoip`; the `geoip:private` rule is small and safe. If memory is tight, remove even that and route all traffic through the proxy.
- The `tun` inbound is platform-specific; `flutter_vless` generates it. Use its raw JSON import path rather than hand-editing the TUN section.

## Appendix B — Hysteria2 client sketch

```json
{
  "tag": "relay-nyc-hy2",
  "protocol": "hysteria",
  "settings": {
    "version": 2,
    "address": "203.0.113.20",
    "port": 443,
    "auth": "STRONG_PASSWORD"
  },
  "streamSettings": {
    "network": "hysteria",
    "security": "tls",
    "tlsSettings": {
      "serverName": "hy2.example.com",
      "allowInsecure": false,
      "alpn": ["h3"]
    },
    "hysteriaSettings": {
      "version": 2,
      "udpIdleTimeout": 60
    }
  }
}
```

Notes:

- Hysteria2 is UDP; probe UDP first.
- Use Salamander obfs on the server if the network fingerprints QUIC.
- Validate the packaged core supports the `hysteria` protocol/transport before shipping.

## Appendix C — Test matrix

| Device / network | Engine | Protocol | Expected |
|---|---|---|---|
| Android (CPH2691), IR Wi‑Fi | Xray | REALITY TCP/443 | Connect ≤ 3 s, exit IP = relay country |
| Android, Irancell mobile | Xray | REALITY TCP/443 | Connect ≤ 8 s, no fake state |
| Android, Hamrah Aval mobile | Xray | REALITY / XHTTP / Hysteria2 | Best of the three; honest failure |
| Android, IR Wi‑Fi ↔ mobile | Xray | REALITY | Tunnel survives or reconnects ≤ 2 s |
| Android, corporate Wi‑Fi | Xray | REALITY / XHTTP | Clear error if TLS inspection |
| iOS (physical), Wi‑Fi | Xray | REALITY RAW | Extension stays under 50 MiB |
| macOS, Wi‑Fi | Xray | REALITY | Connect and exit IP correct |
| All | SoftEther fallback | TLS/443 | Works when Xray is unavailable; truthful relay |
| All | Offline / total shutdown | n/a | "Network unavailable"; no retry storm |
| All | Manual disconnect during dial | n/a | No late connected state |
| All | Relay dies mid-session | n/a | Switch or reconnect; UI never lies |
