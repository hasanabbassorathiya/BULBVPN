# Connection Solutions Log

Living record of the fixes being tried for BULBVPN, why they were needed, and
what the device evidence showed. Newest work is at the top of the attempt table.

Last updated: 2026-11-01

---

## Current status (short)

| Area | Status | Evidence |
|---|---|---|
| Android data path (SoftEther) | **Working** | `tun1` has RX/TX, `ping 1.1.1.1` ~600 ms; connect 10.2 s; `effective=219.100.37.11`, country `JP` |
| Android notification text | **Fixed and verified on device** | `Connected · encrypted tunnel`; removed on shutdown |
| Truthful connected/country state | **Working** | UI reads `connectedRelayProvider`, not the picker |
| Effective relay IP byte order | **Fixed and verified** | native network-order IP reversed before display; last-good now `219.100.37.11` |
| Stale black screen after restart | **Fixed** | `no_screenshot` flag cleared on startup |
| Last-good relay poisoning | **Fixed** | old `195.37.100.219` replaced by `219.100.37.11`; guarded on load |
| Auto relay ordering on IR carriers | **Open** | some public relays answer HTTP 404 / `-5` / `-4`; next-gen research says move off public relays |
| Relay port agility (992 / 1194) | **Fixed and verified on device** | 443 filtered → `217.138.212.62:992` connected in 12.6 s with live traffic; default 443 regression re-checked |
| REALITY relay fleet + real-data gate | **Working; fleet throttled on this network** | 512 KiB transfer required through the live TUN (128 KiB in 10 s floor); dead relays rejected with DNS/TLS/timeout reasons; exit IP read from `1.1.1.1/cdn-cgi/trace` |
| Per-network engine health (REALITY cooldown) | **Fixed and verified on device** | 3 dead sessions → `REALITY skipped: recent sessions on this network carried no data` → SoftEther connected in 10.7 s |
| End-to-end browsing over the chosen session | **Verified on device** | Chrome rendered `en.wikipedia.org` through the SoftEther tunnel; `tun1` moved 380,608 B in 25 s |
| Next-gen architecture research | **Complete** | `docs/research-vpn-architecture.md`: REALITY TCP/443 primary, Xray-core via `flutter_vless` |
| App crash during failing connect (native) | **Fixed and verified** | 5-minute AHS loop; crash buffer empty; stale client is no longer freed under a newer handshake |
| App killed by ANR during connect/cancel | **Fixed and verified on device** | ANR stack showed `nativeStop` on `main`; teardown is now off-thread; 6-minute AHS soak, same pid, no new ANR |
| AHS (censored Wi-Fi) reachability | **Open — transport problem** | 160 VPN Gate relays probed on AHS, 2 reachable, both rejected; public relay transport is filtered, see §12 |
| iOS / iPad runtime test | **Blocked** | iPad developer mode off; Blitz only lists simulators |
| macOS app runtime test | **Not yet run** | needs a signed/built macOS target and a real tunnel |
| IR mobile data (Irancell / Hamrah Aval) | **Waiting on device** | Wi-Fi path verified first |

---

## Attempt log

| # | Symptom | Hypothesis | Change | Result |
|---|---|---|---|---|
| 1 | UI showed “Connected” after the tunnel was gone | Persisted status / engine replay | Engine status reconciled, terminal state clears relay, liveness watchdog | Fixed |
| 2 | Picker said one country, exit was another | UI inferred country from picker | `RelayTarget` + `connectedRelayProvider`; effective IP reconciled against catalog | Fixed |
| 3 | App black after force-stop / restart | `no_screenshot` persists `FLAG_SECURE` in prefs and re-applies it on activity attach | Disable screen security in notifier constructor; enable only for a live tunnel | Fixed |
| 4 | `nread_max=0B`, `tun0` RX stayed 0 | `softether_set_tunnel_fd()` called **before** connect, so the loop kept the pre-DHCP fd | Moved the fd attach after connect | Did not fix; `-9` adapter error when no fd |
| 5 | `SIGSEGV` in `softether_connect+972` | Second client created while the first client’s data loop was being torn down | Remove the second client | Crash avoided |
| 6 | Connect authenticated but returned `-9` (`SOFTETHER_ERR_ADAPTER`) | Adapter is built inside `connect()` from the fd configured at that moment | Create a placeholder TUN and set the fd **before** connect | Adapter initializes |
| 7 | Still `nread_max=0B` with the placeholder fd | After DHCP Android re-creates the VpnService interface; the placeholder fd is stale | Create the routed TUN after DHCP and call `softether_replace_tun_fd()` on the **same** client | **Traffic works** |
| 8 | Notification stayed on “Opening SSL tunnel” | Notification created once in `onStartCommand` and never updated | `updateNotification()` after `holdSession`; initial text `Connecting…` | Fixed in code, pending install |
| 9 | Every auto connect burned 30 s on `83.37.100.219` | Legacy last-good record had an IP but no country and was not in the catalog | Skip unverifiable last-good records; log and continue | Fixed in code |
| 10 | Manual relay `vpn132949429` returned HTTP 404 then `47.152.39.125` returned `-4` | Dead / wrong-protocol relays are still in the candidate list | Needs relay health filtering / proven-first ordering on IR | Open |
| 11 | Connected to `219.100.37.195` but UI/service showed `195.37.100.219` | Native returns `in_addr.s_addr` in network byte order; Kotlin formatted the integer as-is | `formatEffectiveIp(networkOrder) = formatIp(Integer.reverseBytes(networkOrder))` | **Fixed**; logcat `effective=219.100.37.11`, prefs updated |
| 12 | On a network that blocks TCP/443, every relay probes dead and the app never leaves Standby | VPN Gate relays serve the same SoftEther TLS handshake on 992 and 1194, so a 443-only probe throws away reachable relays | Probe 992/1194 for the shortlist when 443 is empty; thread `port` through target → probe → reachability cache → MethodChannel → `nativeCreate` → prefs/memory | **Fixed**; with `iptables REJECT tcp/443`: 0/3 on 443 → 2/6 alternates → `217.138.212.62:992` connected in 12.6 s, RX 1.2 MB, `ping 1.1.1.1` 0% loss |
| 13 | Native `SIGSEGV` in `softether_connect+972`; app died with no Java exception during failing AHS connects | A previous attempt's timeout/shutdown freed the shared `client` field after a newer attempt had already assigned its own handle | Stale-handle-scoped release (`client == stale`), claim `connectInFlight` in the same lock that assigns `client`, never destroy while a handshake is on the stack | **Fixed**; 5-minute AHS loop, crash buffer empty |
| 14 | App vanished during connect/cancel on AHS; `exit-info` showed `reason=6 (ANR)` | `MainActivity` ran `SoftEtherVpnService.shutdown()` on the UI thread, and `shutdown()` held `sessionLock` through `nativeStop` | Run disconnect / engage-lockdown / kill-switch work on a background executor; detach the client under the lock and tear down outside it; `requestStop` offloads main-thread callers | **Fixed**; 6 rapid cycles + 6-minute soak, pid stable, 0 new ANRs |
| 15 | REALITY service reported CONNECTED, then carried no usable traffic | Readiness probe only echoes a token through the local TUN→tun2socks→Xray loop; it never touches the Internet | Add a live-TUN transfer gate: 512 KiB request, **128 KiB required within 10 s**; reject and penalise the relay when it fails | **Fixed**; PR/DE/EE/HK/US/UA rejected as dead; IT accepted 33 KB then stalled and was rejected |
| 16 | A fleet that cannot pass the gate burns 3 × 30–45 s before SoftEther runs | Failure state was per-relay only, so every connect re-explored the same dead fleet | Session-level engine health per network: 3 dead sessions → 20-minute REALITY skip; success resets; network change resets; a pinned relay bypasses | **Fixed**; cycle 4 logged the skip and SoftEther connected in 10.7 s |
| 17 | Only one relay was remembered per network | A single last-good entry cannot express a fleet with different censorship exposure | Per-network scored fleet: pinned first, then `RelayMemory.orderByHistory` (probe history, dial failures, RTT), up to 3 dials per session | **Implemented and exercised in logs** |

---

## 1. Android dead data path (`nread_max=0B`)

### What was observed

```
tun0: RX 0   TX 151736 -> 192840
libsoftether: nread_max=0B nwrite_max=0B
Chrome: DNS_PROBE_FINISHED_NO_INTERNET
toybox nc -w 12 1.1.1.1 80 -> timeout
```

Android showed a perfect VPN interface and the SoftEther control channel was
authenticated. Only the packet path was dead.

### Root cause

The native API builds its packet adapter inside `softether_connect()` from the
fd that is configured at that moment.

- No fd before `connect()` → authentication succeeds, then
  `SOFTETHER_ERR_ADAPTER (-9)`.
- Placeholder fd before `connect()` → adapter succeeds, but the packet loop
  keeps the pre-DHCP interface. Android later replaces that interface with the
  server-assigned one, so the loop polls a stale fd forever.
- Creating a second client to “move” to the routed interface races the first
  client’s teardown and crashes inside `softether_connect()`.

`softether_set_tunnel_fd()` is documented as “call after connect()”; what the
header means is that the **final** fd must be attached after connect. The
adapter still needs a real fd at connect time. The correct sequence is therefore
placeholder → connect → DHCP → routed interface → `softether_replace_tun_fd()`.

### Implemented sequence

1. `openTun("10.211.254.2", 24, defaultRoute=false)` (placeholder).
2. `nativeSetTun(client, placeholder)`.
3. `nativeConnect()` (TLS 443 → VPN Gate auth → session).
4. Read the server-assigned IP/mask.
5. `openTun(assignedIp, prefix, defaultRoute=true)` (routed interface).
6. `nativeReplaceTun(client, routedFd)` on the **same** client.
7. Retire the old fd after 1.5 s (the packet thread may hold it for one poll).
8. `holdSession()` → liveness loop.

Source: `android/app/src/main/kotlin/app/bulbvpn/com/SoftEtherVpnService.kt`.

### Evidence that it works

```
tun1: 256589 bytes RX, 154485 bytes TX
ping 1.1.1.1: 64 bytes, ttl=56, 485 ms
Cloudflare CF-RAY: a4d839db7b18d55e-NRT
```

### Rules that stay

- Never create a second native client to change interfaces.
- Only retry plain-password auth on a real `-5` (`SOFTETHER_ERR_AUTH_FAILED`),
  on the same client. `-9` is an adapter error, not auth.
- Keep the 28 s SoftEther connect budget; an 8 s budget caused
  `-12 SOFTETHER_ERR_CANCELLED` followed by an fdsan abort.

---

## 2. Notification always said “Opening SSL tunnel”

### Cause

The foreground notification was built once in `onStartCommand` and never
updated. `holdSession()` changed the service state but not the notification.

### Fix

- Initial text: `Connecting…`
- After `holdSession()`: `Connected · encrypted tunnel`
- `shutdown()` already calls `stopForeground(STOP_FOREGROUND_REMOVE)`, so a
  disconnected tunnel cannot leave a stale “Connected” notification.

### Verify

```bash
adb -s 75cecce0 shell dumpsys notification --noredact \
  | grep -A 3 'pkg=app.bulbvpn.com' | grep -E 'android.title|android.text'
```

Expected while connected:

```
android.text=String (Connected · encrypted tunnel)
```

---

## 3. Stale / poisoned last-good relay

### Cause

`bulbvpn_last_ssl_v1` contained:

```json
{"dial":"83.37.100.219","sni":"public-vpn-97.opengw.net","code":"","name":""}
```

The IP was not in the catalog and had no country metadata. It led the auto plan,
so every connect spent a full timeout on a dead endpoint, and the UI could not
name the country.

### Fix

A remembered relay is only placed first when it is verifiable:

- it exists in the current catalog, **or**
- it has country metadata from a modern save.

Otherwise the controller logs and skips it, and the measured / proven list
leads. Source: `lib/modules/core/vpn_controller.dart` (`_softEtherTargets`).

---

## 4. Screen security (black screenshots)

`no_screenshot` stores `FLAG_SECURE` in `screenshot_pref.xml` and re-applies it
on every activity attach. A previous connected session therefore blacked out
the app even after the tunnel was gone.

Fix: `ConnectionStateNotifier` disables screen security at construction, enables
it only when the app-level status is `connected`, and disables it on
`disconnected` / `error` / `noInternet`.

Black `adb screencap` while genuinely connected is expected privacy behavior,
not a UI failure.

---

## 5. Relay health / manual attempt on the OnePlus

Observed at 16:43 while testing manually:

```
TLS connected with TLSv1.2
Hello response status: 404
result ok=false detail=connect code -5
...
service start host=47.152.39.125 sni=vpn132949429.opengw.net
result ok=false detail=connect code -4
```

`Hello response status: 404` means the endpoint answered HTTP, not the
SoftEther protocol. `-5` is an auth/protocol rejection and `-4` is a connection
failure. The tunnel implementation is not the problem in that attempt; the
selected relays are.

Open work:

1. Add a cheap protocol/health probe before a full SoftEther dial.
2. On Iranian carriers (ICMP filtered), put the proven JP relays
   (`219.100.37.105`, `219.100.37.179`) immediately after a verified last-good.
3. Keep bounded attempts so a dead relay cannot stall the whole connect.

---

## 6. iPad / Blitz

- Xcode sees the physical iPad: `f889c978da68960d60383775ae438215fd746301`
  (iPad6,11, iOS 16.7.16).
- Blitz’s simulator list contains only simulators (`iPhone 16 Pro`); it does not
  stream this physical iPad.
- `blitz-iphone` uses `simctl`, which rejects a physical UDID.
- iPad `developerModeEnabled` is `false` and WDA is not installed, so device
  automation/screenshot is unavailable.

To test the iPad end-to-end we need:

1. Developer Mode enabled on the iPad (Settings → Privacy & Security →
   Developer Mode, then reboot).
2. A signed development build installed on the iPad.
3. The SoftEther static library is device-arm64 only; simulator linking is not
   expected to work.

---

## 7. Effective relay IP was byte-swapped (fixed)

### What was observed

The service dialled `219.100.37.195`, but the UI/session reported
`195.37.100.219` — the same four octets in reverse order. The byte-swapped
address looked like a legitimately different relay, which made the
"connected relay" and country logic untrustworthy.

```
session label: JAPAN · 195.37.100.219
prefs:         {"dial":"195.37.100.219", ...}
```

### Root cause

`softether_get_effective_server_ip()` returns the IPv4 address as
`in_addr.s_addr`, which is in **network byte order** on the wire. Kotlin was
formatting that 32-bit integer as if it were host order:

```kotlin
// wrong: 219.100.37.195 -> 195.37.100.219
"${(ip ushr 24) and 0xFF}.${(ip ushr 16) and 0xFF}..."
```

The old code therefore reversed every octet. It only became visible once the
effective IP was read and displayed; previously the UI used the dialled host and
the bug was hidden.

### Fix

Reverse the bytes once, at the boundary:

```kotlin
private fun formatEffectiveIp(networkOrder: Int): String =
    formatIp(Integer.reverseBytes(networkOrder))

// ...
val effective = nativeEffectiveServerIp(handle)
if (effective != 0) formatEffectiveIp(effective) else ""
```

The raw native value stays network-order; only the display string is converted.
`formatIp()` remains a plain host-order formatter.

### Evidence

After installing the new APK and connecting:

```
[SoftEtherVpnService] effective relay 219.100.37.11 (dialed 219.100.37.195)
[SoftEtherVpnService] session up tun=10.245.51.105 effective=219.100.37.11
TLS 948 ms, auth 541 ms, total 10164 ms
```

Prefs after the successful connect:

```xml
<string name="flutter.bulbvpn_last_ssl_v1">
  {"dial":"219.100.37.11","sni":"public-vpn-47.opengw.net","code":"JP","name":"Japan"}
</string>
```

`219.100.37.11` is `public-vpn-47.opengw.net` in `data/vpngate.json`, so the
effective relay is a real, catalogued JP relay — not a byte-swapped ghost. The
old `195.37.100.219` record is gone.

### Why the effective relay is not always the dialled relay

VPN Gate can terminate a dialled IP on a different relay inside the same
operation. That is why the controller re-resolves the effective IP against the
catalog:

- Effective IP == dialled IP → keep the dialled target.
- Effective IP is a catalogued relay → use its hostname/country.
- Effective IP is unknown → clear country and show **Private relay**.
- Never show the dialled country when the effective relay is somewhere else.

### Verify

```bash
adb -s 75cecce0 logcat -d -v time -s 'BulbSoftEther:*' | grep -E 'effective relay|session up'
adb -s 75cecce0 shell "run-as app.bulbvpn.com cat shared_prefs/FlutterSharedPreferences.xml" \
  | tr '>' '>\n' | grep -A1 'bulbvpn_last_ssl_v1'
python3 - <<'PY'
import json
d=json.load(open('data/vpngate.json'))
rows=d if isinstance(d,list) else d.get('servers',[])
for r in rows:
    if (r.get('IP') or r.get('ip')) == '219.100.37.11':
        print(r.get('#HostName'), r.get('CountryShort'))
PY
```

---

## 8. Research outcome: next connection architecture

Full research, sources, decision matrix, config sketches, and phased plan:
**[`docs/research-vpn-architecture.md`](research-vpn-architecture.md)**.

### Decision in one paragraph

Move the primary path to **Xray-core via `flutter_vless`**, with **VLESS +
REALITY over TCP/443** first. Keep **XHTTP** as the "REALITY connects but gets
cut" fallback, **Hysteria2** as an opportunistic UDP upgrade, and
**SoftEther/OpenVPN** as legacy fallbacks behind the same supervisor. A paid
product cannot be built on public VPN Gate relays; they stay as a bootstrap
fallback until owned relays and a signed catalog exist.

### Why

- Iran's 2025–2026 filtering is layered: DNS poisoning, SNI filtering, TCP RST,
  IP allowlists, UDP/QUIC filtering, and protocol whitelisting. TCP/443 with a
  believable TLS handshake is the most survivable path.
- REALITY's client SNI is a benign camouflage site, not the relay's domain, so
  a banned free relay domain is not the problem. The server IP is what must be
  reachable.
- One Xray core covers REALITY, XHTTP, Hysteria2, Trojan, Shadowsocks, and
  WireGuard import. That removes the need to maintain three separate protocol
  stacks for the primary path.
- Xray's observatory + balancer can switch outbounds **inside the tunnel**,
  which is the only way to make failover feel instant without a new VpnService.
- The iOS packet tunnel has a **50 MiB** memory limit; REALITY RAW with minimal
  rules is the safe first target. XHTTP and large geo files are deferred until
  measured.

### What we will not do

- Use GitHub Actions as a VPN relay. It is ephemeral, monitored, and the
  Additional Product Terms prohibit unrelated workloads. Actions stays for
  build/test/sign/publish; scraping and health checks move to a Worker/VPS.
- Use sing-box in a closed-source paid app without accepting GPL obligations.
- Depend on domain fronting. Major CDNs have largely disabled it; ECH is
  optional hardening, not a bypass.
- Default to Hysteria2/WireGuard/UDP. Probe UDP first; fall back to TCP.
- Show a country or "Connected" before a data-path probe succeeds.

### Immediate next actions

1. Add `flutter_vless` and a `TunnelEngine`/`TunnelCoordinator` abstraction;
   keep SoftEther as the fallback.
2. Validate the packaged Xray-core with a REALITY profile (`xray run -test`,
   then a live handshake) on Android, iOS, and macOS.
3. Implement the pre-connect race and per-network last-good verification.
4. Wire Xray observatory + balancer + `fallbackTag`; expose the active outbound
   as `connectedRelay`.
5. Add a signed catalog and a multi-DoH resolver; move the hourly scraper off
   GitHub Actions.
6. Test Android Wi‑Fi ↔ mobile recovery, then IR mobile data on the second
   device; test iOS and macOS.

---

## 9. Relay port agility: 992 / 1194 when 443 is blocked

### What was observed

A network that drops TCP/443 makes the app look broken: every candidate fails
the TLS probe, the shortlist is empty, and the UI sits in Standby with no error.
The pre-probe code only knew port 443, so it could not distinguish "relay is
dead" from "this port is filtered".

Measured against the VPN Gate fleet, the same servers complete the SoftEther
TLS handshake on three listeners:

| Port | Result |
|---|---|
| 443 | TLS handshake, SoftEther session (primary) |
| 992 | TLS handshake, SoftEther session |
| 1194 | TLS handshake, SoftEther session |
| 995 | TCP accept, then EOF — a POP3S listener, not SoftEther |

The certificate is the same `CN=opengw.net` on every listener, so the SNI used
for 443 stays valid on the alternates. Port agility is therefore a genuine
evasion lever that needs no new dependency, no new server, and no protocol
change.

### Implemented

- `RelayTarget` carries `port` (default 443); `endpoint` renders `ip:port` only
  when the port is not the primary, keeping logs and the home screen quiet.
- `alternatePortTargets()` (`lib/modules/core/relay_port_agility.dart`) builds
  the 992/1194 list from the same shortlist, capped per port and deduped on
  `ip:port` so a relay already dialled on 992 is not re-added from its 443 twin.
- The controller probes the alternates **only when the 443 probe leaves the
  shortlist empty**, so the normal path pays no extra latency.
- Reachability is cached per listener (`ip:port`). A 992 success cannot mark the
  same IP warm on 443, and vice versa.
- `port` is threaded through the MethodChannel, `SoftEtherVpnService`
  (`EXTRA_PORT` / `PREF_PORT`), `nativeCreate(host, port, ...)`, the last-good
  relay record, and `RelayMemory`, so a reconnect after a restart dials the
  listener that actually worked.

### Evidence

Default port still works after the change:

```
service start host=115.179.206.241 port=443
CONNECTED via SoftEther 115.179.206.241 (JP) in 8.8 s
```

Forced alternate listener:

```
am start-foreground-service ... --ei port 992
service start host=217.138.212.62 port=992
native ret 0; tun1 RX 1.4 MB; ping 1.1.1.1 0% packet loss
```

Same for 1194, and `PREF_PORT=1194` persisted across a service restart.

Simulated 443 filtering with root `iptables`:

```
iptables -I OUTPUT -p tcp --dport 443 -j REJECT

[VpnController] SoftEther: 0/3 reachable on 443
[VpnController] SoftEther alternate ports: 2/6 reachable after 443 failed
  (217.138.212.62:992, 217.138.212.62:1194)
CONNECTED via SoftEther 217.138.212.62:992 in 12.6 s
tun1 RX 1.2 MB; ping 1.1.1.1 0% packet loss
```

Removing the rule restored the default 443 dial.

### Limits of this evidence

The block was simulated locally with `iptables REJECT`, not by Iranian DPI.
Real filtering may reset the connection after the handshake, filter UDP, or
block the relay IPs entirely; port agility covers only the "port blocked"
case. No exit-IP or IPv6 check was repeated in this pass.

### Verify

```bash
adb -s emulator-5554 logcat -d -v time | grep -E 'alternate ports|service start host'
adb -s emulator-5554 shell "run-as app.bulbvpn.com \
  cat shared_prefs/bulb_vpn_relay.xml" | grep PREF_PORT -i
```

---

## 10. Native crash while a relay kept failing (fixed)

### What was observed

On AHS, every connect attempt reached the native SoftEther handshake and then
failed. After one of those attempts the whole process disappeared with no Java
exception. `tombstone` showed two different native faults:

```
#1  softether_get_assigned_ip+16  <- JNI <- connectWithDeadline      (thread "softether")
#2  softether_connect+972                                            (thread "softether-connect")
```

`#1` was the connect loop polling the DHCP address while `softether_connect`
was still building the session on another thread. `#2` was the real killer: a
timed-out attempt's `releaseAfterHandshake()` destroyed the shared `client`
field, which by then held a **newer** attempt's handle. The newer handshake
then ran on freed memory, and the `-5 auth` results just before the crash were
corruption symptoms.

### Fix

- Never call state getters while a handshake is in flight; the assigned address
  is read only after `connect` returns.
- Claim `connectInFlight = true` inside the same `sessionLock` block that
  assigns `client`, so a shutdown can never destroy a handle between assignment
  and use.
- `releaseAfterHandshake(stale)` only frees when `client == stale` and no
  handshake is on the stack; otherwise it leaks one client. Leaking is cheaper
  than aborting the process.
- A raw native poll was removed from `connectWithDeadline`.

### Evidence

Five minutes of continuous failing connects on AHS: `logcat -b crash` stayed
empty and the process pid never changed. The subsequent ANR investigation
(§11) is a different failure, not a native crash.

### Verify

```bash
adb -s 75cecce0 logcat -d -b crash | grep -E 'softether|SIGSEGV'
adb -s 75cecce0 shell dumpsys activity exit-info app.bulbvpn.com \
  | grep -E 'reason=5|reason=2'
```

---

## 11. App killed by ANR during connect/cancel (fixed)

### What was observed

After the native crash was fixed, Android still killed the app twice on AHS:

```
process=app.bulbvpn.com reason=6 (ANR)
Subject: Input dispatching timed out (MainActivity is not responding.
         Waited 5001ms for MotionEvent ...)
```

The dropbox ANR trace named the exact frame:

```
"main" prio=5 tid=1 Native
  at app.bulbvpn.com.SoftEtherVpnService.nativeStop(Native method)
  at app.bulbvpn.com.SoftEtherVpnService.shutdown(SoftEtherVpnService.kt:911)
  at ...Companion.requestStop(SoftEtherVpnService.kt:1181)
  at app.bulbvpn.com.MainActivity.configureFlutterEngine$lambda$0(MainActivity.kt:45)
```

A second trace showed `main` **Blocked** on `sessionLock` while the "softether"
thread was inside the same `nativeStop` under that lock (`shutdown` line 907 →
911). `softether_request_stop + disconnect + destroy` can join library threads;
running it on the input thread is an ANR by construction, and holding
`sessionLock` across it makes the UI thread wait even when teardown starts
elsewhere.

### Fix

- `MainActivity` dispatches `disconnect`, `engageLockdown`, and `setKillSwitch`
  to a single background executor and replies to Dart on the main thread only
  after the work finishes (so disconnect-then-connect cannot race the old
  session).
- `SoftEtherVpnService.shutdown()` and `onDestroy()` detach the client under
  `sessionLock`, then call `nativeStop`/`nativeDestroy` outside the lock.
- `requestStop` routes main-thread callers through a dedicated
  `softether-stop` executor; `onRevoke` does the same.
- `releaseAfterHandshake()` also tears down outside the lock.

### Evidence

Six rapid connect/cancel cycles plus a six-minute failing-connect soak on AHS:
same pid for the whole run, `uiautomator dump` answered in ~3 s throughout, and
`exit-info` gained no new `reason=6` entries.

### Verify

```bash
adb -s 75cecce0 shell dumpsys activity exit-info app.bulbvpn.com \
  | grep -E 'reason=6|ANR'
adb -s 75cecce0 shell dumpsys dropbox data_app_anr --print \
  | grep -A 8 '"main" prio' | grep -E 'nativeStop|shutdown|requestStop'
```

---

## 12. Why AHS never connects (network evidence)

This is a transport problem, not a bug in the tunnel code.

- On AHS, 160 VPN Gate relays were TLS-probed; **2** completed a handshake
  (`106.153.7.87`, `115.179.206.241`) and both were rejected by the session
  layer (`-100` timeout, `-5` auth). The OpenVPN fallback also failed.
- The same build connects from SORATHIYA and from Iranian mobile data, so the
  client stack is not the variable.
- OONI's 2026-10-31 measurement on an Iranian carrier shows TCP connect to a
  VPN Gate relay succeeding and then an RST **after ClientHello with SNI
  `www.vpngate.net`**. That is SNI filtering on a known relay domain, plus IP
  range filtering for hosting/VPN ranges and protocol fingerprinting.
- Lantern works on the same network because it does not depend on one
  third-party relay fleet or one protocol: it rotates its own transports
  (fronted HTTPS, Snowflake/WebRTC, obfuscated proxies) that survive when raw
  relay IPs die. Public VPN Gate is the worst possible transport to judge the
  network by.

The fix is the architecture already chosen in
[`research-vpn-architecture.md`](research-vpn-architecture.md): an Xray-core
engine with **VLESS + REALITY over TCP/443** first, XHTTP over CDN as the
"REALITY connects but is cut" fallback, and SoftEther/OpenVPN as legacy
fallbacks. That needs a relay we control (or a CDN path we control) — public
VPN Gate relays cannot carry it.

---

```bash
# VPN interface and counters
adb -s 75cecce0 shell cat /proc/net/dev | grep -E 'tun|wlan0|rmnet'
adb -s 75cecce0 shell dumpsys connectivity | grep 'VPN CONNECTED'

# End-to-end traffic
adb -s 75cecce0 shell "ping -c 2 -W 3 1.1.1.1"
adb -s 75cecce0 shell \
  "printf 'GET /cdn-cgi/trace HTTP/1.0\r\nHost: 1.1.1.1\r\n\r\n' | toybox nc -w 8 1.1.1.1 80"

# Native/service log lines
adb -s 75cecce0 logcat -d -v time | grep -E 'BulbSoftEther|libsoftether'

# Notification truth
adb -s 75cecce0 shell dumpsys notification --noredact \
  | grep -A 3 'pkg=app.bulbvpn.com' | grep -E 'android.title|android.text'
```

---

## 13. REALITY relay fleet: multiple relays, real-data gate, engine health

### What was observed

One relay per network is not enough. The community REALITY fleet behaves very
differently on the same Wi-Fi, and several relays complete a TLS handshake
that a censor then throttles:

| Relay path | Direct probe | After native CONNECTED |
|---|---|---|
| PL, EE | DNS lookup fails, and the DNS-free `1.1.1.1` trace fails too | never reached |
| DE, HK, US, UA | TLS completes | transfer never reaches the gate |
| IT | TLS completes | ~33 KB (one flow reached ~70–100 KB), then stalls |
| SoftEther (VPN Gate JP) | TLS completes | 380,608 B in 25 s (15.2 KB/s) during the final check |

The old contract accepted a relay as soon as the native service reported
CONNECTED. The plugin's readiness probe (`SessionReadinessProbe.kt`) only
echoes a token through the local TUN → tun2socks → Xray → freedom loop; it
proves plumbing, not Internet data. So the app could show **Connected** on a
session that could not load one web page. Chrome on the IT relay stalled on a
blank `en.wikipedia.org` load, which is what "connected but useless" looks
like to a user.

### Implemented

**Candidate fleet (`_tryReality`, `lib/modules/core/vpn_controller.dart`)**

1. A pinned relay goes first; the rest of the catalog follows in
   `RelayMemory.orderByHistory` order for the **current network** — relays with
   recent probe/dial failures sink, recent successes and low RTT rise.
2. At most `_maxRealityAttempts = 3` dials per session, so a dead fleet cannot
   consume the whole connect budget.
3. The loop stops when less than 35 s of the 100 s Android connect budget
   remains, reserving the rest for the SoftEther fallback.

**Real-data gate (`RealityEngine.probeTunnel`)**

- Requests `https://speed.cloudflare.com/__down?bytes=524288` (512 KiB) and
  requires **128 KiB within 10 s** (~13 KB/s floor) through the live TUN.
- In parallel, fetches `https://1.1.1.1/cdn-cgi/trace` (plus the
  `cloudflare.com` trace as a second path) to read the real exit `ip=`/`loc=`.
  The exit IP is logged on success, so "which relay carried this session" is
  evidence rather than an inference.
- Failures carry a stage reason — `dns …`, `http <code>`, or
  `timeout after Ns` with partial bytes — instead of a bare `0B in 0ms`.
- A relay that natively connects but fails the gate is stopped, recorded as a
  failed probe, and the loop dials the next candidate.

**Engine health (`RelayMemory.recordEngineOutcome` / `engineRecentlyFailing`)**

- A whole session that ends with no working REALITY tunnel increments a
  per-network `reality` streak; a success resets it to 0.
- 3 consecutive dead sessions close REALITY for that network for 20 minutes.
  Auto mode then skips the fleet immediately and SoftEther gets the budget;
  the cooldown expiring, a network fingerprint change, or an explicitly pinned
  relay re-enables REALITY.
- This is deliberately network-scoped: a fleet that fails on a censored
  carrier is retried as soon as the device joins a different network.

### Evidence

```
[VpnController] REALITY dial … attempt 1/3
[VpnController] REALITY … up but the tunnel did not carry data
  (33456B in 10001ms, rtt 812ms, timeout after 10s); trying the next relay
[VpnController] REALITY skipped: recent sessions on this network carried no data
[VpnController] CONNECTED via SoftEther 115.179.206.241 (JP)
```

- After the skip, the next connect reached SoftEther in **10.7 s** instead of
  burning ~40 s on dead REALITY dials.
- `dumpsys connectivity` shows `NetworkAgentInfo{… VPN CONNECTED …}` with
  `tun1`, `0.0.0.0/0 → tun1`, and all app UIDs routed into the tunnel.
- Chrome loaded `https://en.wikipedia.org/wiki/Internet_censorship_in_Iran`
  fully through that session (screenshot on file), the check that failed over
  the IT REALITY relay.
- A direct download through the tunnel measured
  `code=200 bytes=380608 time=25.0s speed=15223 B/s`.

### Limits of this evidence

- On SORATHIYA the whole public REALITY fleet is throttled after the handshake.
  The app now detects that quickly and falls back; it does not make those
  relays usable.
- AHS could not be re-tested in this round (the network moved); its transport
  finding in §12 still stands.
- The gate costs up to 10 s per rejected relay. With the 3-dial cap and the
  per-network cooldown, a censored network pays that once and then goes
  straight to SoftEther for 20 minutes.

### Verify

```bash
# Fleet decisions and gate reasons
adb -s 75cecce0 logcat -d -v time | grep -E \
  'REALITY dial|did not carry data|REALITY skipped|CONNECTED via REALITY'

# Exit evidence on a REALITY session
adb -s 75cecce0 logcat -d -v time | grep -E 'CONNECTED via REALITY.*exit'

# Per-network engine health
adb -s 75cecce0 shell "run-as app.bulbvpn.com \
  cat shared_prefs/FlutterSharedPreferences.xml" \
  | tr '>' '>\n' | grep -A1 'bulb_engine_health_v1'

# Real transfer through the live tunnel
adb -s 75cecce0 shell "curl -s --interface tun1 --max-time 25 -o /dev/null \
  -w 'code=%{http_code} bytes=%{size_download} time=%{time_total}\n' \
  'https://speed.cloudflare.com/__down?bytes=1048576'"
```

---

## Files touched by these solutions

- `android/app/src/main/kotlin/app/bulbvpn/com/SoftEtherVpnService.kt`
- `android/app/src/main/kotlin/app/bulbvpn/com/MainActivity.kt`
- `android/app/src/main/cpp/softether_jni.c`
- `lib/modules/core/softether_vpn.dart`
- `lib/modules/core/vpn_controller.dart`
- `lib/modules/core/reality/reality_engine.dart`
- `lib/modules/core/relay_target.dart`
- `lib/modules/core/relay_port_agility.dart`
- `lib/modules/core/relay_memory.dart`
- `lib/modules/core/relay_reachability.dart`
- `test/relay_port_agility_test.dart`
- `test/relay_memory_test.dart`
- `test/relay_reachability_test.dart`
- `lib/modules/core/vpn_session_store.dart`
- `lib/shared/providers/connection_state_provider.dart`
- `lib/modules/main/presentation/screens/main_screen.dart`
- `lib/modules/settings/presentation/screens/settings_screen.dart`
- `lib/core/utils/screen_security.dart`
- `ios/PacketTunnel/SoftEtherSession.swift`
- `macos/PacketTunnel/SoftEtherSession.swift`
- `docs/research-vpn-architecture.md` (next-generation protocol/client/control-plane research)
- `docs/connection-solutions.md` (this log)
