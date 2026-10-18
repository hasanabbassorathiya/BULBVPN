# Connecting BULBVPN on Iranian mobile data

Release builds hide the in-app log. The traces below are from a debug
session on the device, not from the Play or TestFlight UI.

This is the method that made the tunnel carry traffic on Irancell LTE
(Samsung SM-M127G, Android 11). The same failure showed up on Hamrah Aval:
Wi-Fi connected, mobile data either killed the app or sat on "connecting"
and then failed. The radio was fine. The tunnel was not.

The confirmed result on that phone: the app reached **Connected**, download
moved (about 6 KB/s of real traffic), and an HTTP request to `1.1.1.1`
returned a Cloudflare answer whose ray id ended in `NRT` (Tokyo). The exit
address on screen was `27.92.236.186` in Japan. That request went through
the VPN, not through the carrier.

## What was actually broken

Three separate bugs stacked. Fixing only the first one produces a green
"Connected" screen with a dead tunnel.

1. **Stopping the handshake when the network flickers.** Bringing the TUN
   interface up makes Android report a new network (`wifi` or `cellular`
   plus `vpn`). The old code treated that as "the tunnel dropped" and
   called disconnect while `nativeConnect` was still inside the SoftEther
   library. That is a `SIGSEGV` in `libsoftether_jni.so`. On mobile the
   flicker happens immediately, so the app died or showed failure at once.
   On Wi-Fi the handshake often finished before the callback fired.

2. **The data loop kept the wrong TUN file descriptor.** SoftEther learns
   the client address from DHCP (`10.211.1.x/16` on VPN Gate). The first
   TUN is created *before* that address is known, with no default route,
   only so the handshake has a file descriptor. After DHCP, the service
   called `VpnService.Builder.establish()` again and
   `softether_replace_tun_fd()`. The library keeps polling the descriptor
   it was given *before* `softether_connect()` returns. The new interface
   (`tun1`) received packets from the phone and nobody read them.
   `ip route show table all` showed `default dev tun1`, and
   `toybox nc 1.1.1.1 443` timed out. The library diag line stayed at
   `nread_max=0B`.

3. **The session socket fell into its own tunnel.** Once the TUN has
   `0.0.0.0/0`, it is the default network. A second handshake started
   *after* that route exists will send its own TLS into the TUN unless
   the socket is excluded. `VpnService.protect()` did run (`protect fd=…
   ok=true`) and was still not enough on this Android 11 build: the
   routed retry returned connect code `-4` with no second "TLS connected"
   line. Excluding the VPN app itself from the routed interface keeps
   that process on the carrier (`rmnet0`). Every other app still uses
   the TUN.

OpenVPN over UDP was already known to stall on this network. SoftEther
over TLS on TCP 443 is the first attempt. OpenVPN is the fallback when
every SoftEther relay fails. On the Irancell test, SoftEther authenticated
to `150.40.105.5` and received `10.211.1.4`, then the routed retry failed,
other relays returned `-4`, `-5`, `-12`, or `-100`, and the OpenVPN
fallback connected to `27.92.236.186:1654` and forwarded traffic.

## Method, end to end

### A. Confirm you are on the mobile network

```sh
adb shell dumpsys telephony.registry | grep 'mDataConnectionState\|mServiceState'
adb shell su -c 'ip -4 addr show rmnet0'
```

Irancell shows `extra: mtnirancell` and an address on `rmnet0`. The
public "BEFORE" address is not a reliable carrier check. Irancell CGNAT
(`26.54.x`) has been geolocated as Baku / Delta Telecom by the IP
database. Trust the radio, not the city name.

### B. Do not tear the native handshake down from another thread

`SoftEtherVpnService.connectWithDeadline()` runs `nativeConnect` on a
thread named `softether-connect` and joins for 28 seconds. If the thread
is still alive, it calls `nativeRequestStop` only, then joins another
8 seconds. `nativeStop` (which also calls `softether_disconnect`) runs
only when `connectInFlight` is false. Disconnect during `nativeConnect`
crashes the process.

A fast auth reject (the call returns in under 15 seconds with a non-zero
code) retries once with the plain `vpn` / `vpn` password. A 28-second
black hole does not. `softether_set_connect_timeout` is 12 seconds.
`softether_set_ip_version` is IPv4. Reconnect inside the library is
enabled for 3 attempts so a carrier reset can recover without the UI
calling disconnect.

The Dart side only reconnects on a connectivity change when the status
is already `connected` and the tunnel is actually down. A `connecting`
status is not a dropped tunnel. `busy` from the method channel is not a
failed attempt.

### C. Dial an IP, present the VPN Gate name as SNI

Carrier DNS can black-hole `*.opengw.net`. The controller pings
`ip:443` from the phone, sorts lowest latency first, and keeps one host
per `/24`. The last relay that completed a session is tried first
(`bulbvpn_last_ssl_v1`, or the saved session host). The socket connects
to the IP. The TLS name is the host, for example
`vpn648581557.opengw.net`.

### D. Pin the carrier before any default route

`watchDefaultNetwork()` listens for the non-VPN network that has
`NET_CAPABILITY_INTERNET` and stores it. `pinCarrier()` calls
`setUnderlyingNetworks()` with that network at the start of
`connectBlocking`, again immediately before the routed `establish()`,
and on every later `onAvailable`. Ignore `onAvailable` for the VPN
network itself. Do not wait until `tunnelUp` to pin: by then the
callback has already fired once and will not fire again on a stable
radio.

### E. Learn the address on an unrouted TUN

```text
openTun("10.211.254.2", 24, defaultRoute = false)
nativeSetTun(client, tunFd)
nativeConnect()
wait until nativeAssignedIp() != 0   # up to 20s
```

No `0.0.0.0/0` yet, so DHCP inside the SSL session is not captured by
the TUN. VPN Gate answers with something like `10.211.1.8/16`, gateway
`10.211.254.254`. If the address stays 0, return `no dhcp address` and
try the next relay. Do not sit on that relay.

### F. Start a new session on the routed descriptor

Do not call `softether_replace_tun_fd()` after connect returns. The data
loop will not switch.

```text
retireClient()          # stop + destroy the probe client, close its TUN
openTun(assignedIp, prefix, defaultRoute = true)
nativeCreate + nativeConfigure
nativeSetTun(newClient, routedFd)   # before connect
nativeConnect()
```

`openTun` for the routed interface:

- `addAddress(assignedIp, prefix)`
- `addRoute("0.0.0.0", 0)`
- `addDnsServer("1.1.1.1")` and `8.8.8.8`
- `setMtu(1200)`
- `allowFamily(AF_INET)` only, so IPv6 on the carrier is not black-holed
  into a v4 tunnel
- `addDisallowedApplication(packageName)` so this process's sockets stay
  on `rmnet0`

If DHCP on the second session returns a different address, retire and
repeat once with that address. The descriptor has to match the address
the server will send replies to.

`tunnelUp = true` only after that second connect returns 0. The UI
stays on "opening tunnel" until then. That is one extra handshake
(about 15–25 seconds) and it is the handshake whose file descriptor
actually carries packets.

### G. Notice when the server drops the pipe

After the session is up, the service checks `nativeAssignedIp()` once a
second. Three misses and it clears `tunnelUp` and shuts down. Dart polls
`SoftEtherVpn.status()` while it believes it is connected. If the native
side is gone, the notifier goes back to disconnected instead of leaving
a timer running on a dead pipe. VPN Gate has closed a live session with
`Server closed connection: BrokenPipe` about 50 seconds after DHCP when
the data loop was wedged.

### H. Fall back to OpenVPN when SoftEther cannot

If all eight SoftEther relays fail, `holdEngineEvents(false)` and the
existing OpenVPN rotation runs: last-good config, then the on-device
catalog, TCP 443 preferred, one endpoint per `/24`. On success call
`setConnected()` yourself. The engine event can be dropped while
SoftEther was holding events, and the screen will sit on "Connecting"
even though `getStatus()` is already connected. Point the on-screen
relay label at `ip:port` of the candidate that succeeded.

Resuming the activity calls `_restoreLiveTunnel()`. That reads SoftEther
status and the OpenVPN engine status. If either is up, it adopts the
session from `VpnSessionStore` (`bulb_vpn_session_v1`). The clock keeps
its original start only when the host is the same. A different relay
starts a new clock.

### I. Do not report the carrier address as the exit

The VPN process is excluded from the TUN, so an HTTP call made *by the
app* can still see the carrier. The home screen hides an exit address
that equals the BEFORE address. A real exit is a different IP, with a
location such as `JP`. Confirm from outside the app (step K). The
in-app speed test also runs in this process, so it measures the carrier
while the exclusion is in place. Traffic from Chrome, the shell, and
other apps is what the tunnel is for.

### J. Session restore when the UI dies

`VpnSessionStore.save(label, host)` runs when either engine connects.
`SoftEtherVpnService` is `START_STICKY`, `stopWithTask=false`, foreground
type `specialUse` with subtype `vpn`. Leaving the activity does not
disconnect. Disconnect only from the user action, which calls
`forgetRelay()` and `shutdown()`.

## How to prove the tunnel, not the icon

Screenshots are empty while the VPN is up. `ScreenSecurity` sets
`FLAG_SECURE`. Use the accessibility tree:

```sh
adb shell uiautomator dump /sdcard/ui.xml
adb exec-out cat /sdcard/ui.xml
```

You want `Connected`, `secure tunnel · …`, a non-zero `DOWN` value, and
an AFTER address that is not the BEFORE address.

Packet proof, from the shell (uid 2000 goes through the TUN; the app
uid does not):

```sh
adb shell "printf 'GET /cdn-cgi/trace HTTP/1.0\r\nHost: 1.1.1.1\r\n\r\n' | toybox nc -w 12 1.1.1.1 80"
```

A 301 from Cloudflare with `CF-RAY: …-NRT` (or another airport code that
is not your city) means the packet left through the relay. `toybox nc`
is enough. `curl` is not on this phone. `ping` is not proof: the relay
drops ICMP even when TCP works.

Routing proof, on a rooted phone:

```sh
adb shell su -c 'ip rule; ip route show table all'
```

You want `default dev tun1 table tun1` and the app uid *not* forced onto
`rmnet0`. `unreachable default` in the same table is normal. What is
not normal is `nread_max=0B` in `libsoftether` diag while `nc` times out:
that is the unread-descriptor bug in step F.

Useful log tags: `BulbSoftEther`, `libsoftether`, `flutter`.

```text
pinned underlying 602
assigned 10.211.1.4/16
routed session 10.211.1.4/16
result ok=true detail=10.211.1.4
```

or, when SoftEther relays refuse and OpenVPN wins:

```text
[VpnController] CONNECTED via 27.92.236.186:1654
```

## What not to do

- Do not call `softether_disconnect` from a second thread while
  `nativeConnect` is running.
- Do not `setUnderlyingNetworks` only after `tunnelUp`. The interesting
  `onAvailable` already happened.
- Do not treat `replace_tun_fd` as a live swap. Set the descriptor, then
  connect.
- Do not add `0.0.0.0/0` on the probe interface. DHCP then has to cross
  a tunnel that is not up yet.
- Do not delete user media to free install space. The debug APK is about
  98 MB. Leftover installer sessions live in `/data/app-staging`.
- Do not trust a geolocation city as evidence that the phone left
  Irancell.

## Files

| Piece | File |
|---|---|
| Handshake, pin, routed session, app exclusion | `android/app/src/main/kotlin/app/bulbvpn/com/SoftEtherVpnService.kt` |
| Connect timeout, IPv4, reconnect, `request_stop` | `android/app/src/main/cpp/softether_jni.c` |
| Relay order, last-good, OpenVPN fallback, `setConnected` | `lib/modules/core/vpn_controller.dart` |
| Session clock | `lib/modules/core/vpn_session_store.dart` |
| Status when the native tunnel disappears | `lib/shared/providers/connection_state_provider.dart` |
| Hide a carrier address shown as the exit | `lib/modules/main/presentation/screens/main_screen.dart` |

## One profile, two engines

VPN Gate is SoftEther OpenVPN. The engines in this app are not the same
binary, so one profile text cannot be sent to all of them.

| Devices | Engine | What finishes the handshake |
|---|---|---|
| Android, Windows | OpenVPN 2.6 (`ics-openvpn` on Android, bundled `openvpn.exe` on Windows) | `compat-mode 2.4.0`, `data-ciphers AES-128-CBC`, `provider legacy default`, plus inline `vpn` / `vpn`. Without those, 2.6 ignores `cipher AES-128-CBC` and sits in AUTH. |
| iPhone, iPad, macOS | OpenVPN 3.5.6 / mbed TLS (OpenVPNAdapter 0.7) | TLS 1.0 as both minimum and maximum, AES-CBC suites (`forceCiphersuitesAESCBC`), tls-auth `key-direction 1`, no dummy client certificate. The 2.6 lines above are rejected by this engine and must be stripped. |

Verified on the iPhone: with the TLS 1.0 pin the log was
`SSL Handshake: TLSv1.0/TLS-DHE-RSA-WITH-AES-256-CBC-SHA` and then
`CONNECTED` (`219.100.37.196:443`, tun `10.245.15.209`). `sslDebug` only
controls how much of that line is printed. Level 3 also jetsams the
iOS 16 iPad extension, so the providers stay at level 1.

The pin lives in `patches/openvpn_adapter/` and is reapplied by
`scripts/patch_openvpn_adapter.sh` after `pod install` on iOS and macOS.
Windows receives the OpenVPN 2.6 lines from `configForCurrentEngine`.

## Device pass, 19 Oct 2026

Same release tree on three machines. Autoconnect used `--bulb-connect`.
None of the three reached CONNECTED in this pass. The last iPhone
success is still `connected_on` **2026-10-18 19:56:44Z**.

### iPhone 16 (iOS 27.0, wireless)

Installed `build/ios/iphoneos/Runner.app` and launched with
`--bulb-connect`. The extension log line was
`sslDebug=1`. Every dial did this:

1. TCP connected (`Contacting … via TCPv4`).
2. `VERIFY OK` through `CN=opengw.net`.
3. No `SSL Handshake`, no PUSH, no CONNECTED.
4. `startTunnel timed out waiting for CONNECTED` at 22 seconds.

Hosts tried included `156.239.242.10:443`, `219.100.37.11:443`,
`121.136.113.227:443`, `223.204.92.196:1467`, and
`126.227.98.230:1527`. The app log ended
`All` attempts failed. `connected_on` did not move.

The earlier success on this phone used `sslDebug=3` and logged
`SSL Handshake: TLSv1.0/TLS-DHE-RSA-WITH-AES-256-CBC-SHA`, then
`CONNECTED` on `219.100.37.196:443` (tun `10.245.15.209`).
`sslDebug=0` and `sslDebug=1` both stall after the certificate.
The providers are set back to `sslDebug=3`. That binary was not
the one installed for this pass.

### iPad (iPad 2017, iPad6,11, iOS 16.7.16, USB)

`devicectl` does not see this iPad. `flutter devices` and `ios-deploy`
do. Install of the same Runner.app succeeded
(container `36D99A19-6FD0-42AD-B48F-56A324F08428`). Launch with
`--bulb-connect` returned success from ios-deploy. A 25 second
`idevicesyslog` capture did not contain `VPNExtension` or `CONNECTED`
lines, only older system notices, so there is no tunnel proof.
The installed binary is the same `sslDebug=1` build that stalled on
the iPhone. The appex `CFBundleVersion` must be a non-empty string
matching the app (build 9); an empty version makes installd reject
the extension with `MissingBundleVersion`.

### macOS (this Mac, macOS 26.3.1)

`flutter build macos --release` produced
`build/macos/Build/Products/Release/bulbvpn.app`.
`open` with `--bulb-connect` started the UI and a `PacketTunnel`
process. App-group log
`~/Library/Group Containers/group.com.bulbvpn.app/bulb-tunnel.log`:

- `Contacting 121.136.113.227:443` and `156.239.242.10:443` via TCPv4
- `VERIFY OK` depth 0
- `event DISCONNECTED` or `startTunnel timed out waiting for CONNECTED`

No CONNECTED line. The running appex was the DerivedData copy whose
log line does not say `sslDebug=3`. An older `bulbvpn` process from
9:23 PM was still in the process list and could not be killed
(uninterruptible).

### Retest, 19 Oct 2026 01:00

Current release tree on every device that was plugged in. No Windows
machine was attached.

- **Android (CPH2691, Android 16).** Release APK installed. Connect
  toggle reached **Connected** through the SoftEther fallback
  (`150.40.105.6`), session clock running, about 20 KB/s down. OpenVPN
  candidates before that fallback failed.
- **iPhone 16.** Autoconnect ran six TCP attempts (`156.239.242.10:443`,
  `219.100.37.11:443`, `121.136.113.227:443`, `223.204.92.196:1467`,
  `126.227.98.230:1527`, `164.70.137.225:1220`). Each died after
  `VERIFY OK` / the 22s timeout. Log line: `All 6 attempts failed`.
  `connected_on` stayed 19:56:44Z.
- **iPad (iOS 16.7.16).** Same Runner.app installed and launched with
  `--bulb-connect`. `idevicesyslog` showed no `VPNExtension` lines, so
  there is still no tunnel result from that device.
- **macOS.** `bulbvpn.app` launched with `--bulb-connect` and a
  `PacketTunnel` process started. The app-group log did not gain a new
  CONNECTED line; the previous session on this Mac had ended in
  `Network is unreachable` and `startTunnel timed out`.

### Dial order after that retest

Every platform now dials OpenVPN as TCP 443 only. Hosts in
`219.100.37.0/24` (the subnet that has reached CONNECTED) are tried
before any other relay, up to eight attempts. Random ports such as
1220 and 1467 are not used for OpenVPN. Android still falls back to
SoftEther and now tries three relays instead of one. The Android
OpenVPN watchdog is 18s so a live handshake is not cut off at 10s.
