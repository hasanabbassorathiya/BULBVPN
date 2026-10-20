# Connection Solutions Log

Living record of the fixes being tried for BULBVPN, why they were needed, and
what the device evidence showed. Newest work is at the top of the attempt table.

Last updated: 2026-10-20

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
| Next-gen architecture research | **Complete** | `docs/research-vpn-architecture.md`: REALITY TCP/443 primary, Xray-core via `flutter_vless` |
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

## Useful verification commands

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

## Files touched by these solutions

- `android/app/src/main/kotlin/app/bulbvpn/com/SoftEtherVpnService.kt`
- `android/app/src/main/kotlin/app/bulbvpn/com/MainActivity.kt`
- `android/app/src/main/cpp/softether_jni.c`
- `lib/modules/core/softether_vpn.dart`
- `lib/modules/core/vpn_controller.dart`
- `lib/modules/core/vpn_session_store.dart`
- `lib/shared/providers/connection_state_provider.dart`
- `lib/modules/main/presentation/screens/main_screen.dart`
- `lib/modules/settings/presentation/screens/settings_screen.dart`
- `lib/core/utils/screen_security.dart`
- `ios/PacketTunnel/SoftEtherSession.swift`
- `macos/PacketTunnel/SoftEtherSession.swift`
- `docs/research-vpn-architecture.md` (next-generation protocol/client/control-plane research)
- `docs/connection-solutions.md` (this log)
