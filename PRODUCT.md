# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

**Primary — Iran-first, global-ready.** People whose everyday internet is filtered: students, remote workers, families, and small businesses on Iranian mobile carriers (MCI, Irancell) and home Wi-Fi. Their job is not "configure a VPN"; it is "get me to the site or app I need, now, without explaining why it failed." They have low tolerance for waiting, limited data, and no interest in protocol names.

**Secondary — global.** Users in other restrictive networks who want one fast, quiet VPN that works without setup.

**Tertiary — users with their own infrastructure.** People who already own a VPS or a purchased config (VLESS, VMess, Trojan, Shadowsocks, Hysteria2, WireGuard) and want one app that runs it well.

## Product Purpose

BULBVPN makes censorship feel like nothing: tap once, and the fastest path that actually works on this network is already chosen. Success means the user reaches the open internet in seconds, stays connected across network changes and carrier filtering, and never has to diagnose a protocol.

## Positioning

The app prepares before the user taps. It remembers, per network, which protocol and relay actually carried traffic; races the top candidates with real handshakes; and switches inside the tunnel when the censor changes tactics, without tearing down the VPN. Competing apps ask the user to pick a protocol or a country; BULBVPN picks the working path.

The claim is client intelligence and user-owned server support, not fleet size. BULBVPN does not operate a fleet comparable to Lantern's, and must not imply it does.

## Operating Context

- Use happens on Iranian mobile data and home/office Wi-Fi, often under active DNS poisoning, SNI filtering, TCP reset, and UDP throttling.
- Users may already hold working configs or subscription URLs from providers; importing them must be a first-class path, not a hidden setting.
- App Store and Google Play are the distribution channels; both require honest encryption, privacy, and subscription disclosures.
- The app is monetized as a free tier plus Premium subscription through RevenueCat; ads are remote-gated and off by default.
- Battery and data economy matter: the tunnel is expected to run for hours on a phone.

## Capabilities and Constraints

**Protocols required.** VLESS with REALITY (TCP/443), XHTTP fallback, VMess, Trojan, Shadowsocks, Hysteria2, WireGuard, and legacy SoftEther. OpenVPN is being removed, not expanded: the existing dependency is AGPL-3.0 and conflicts with closed-source App Store distribution.

**Engines and licenses (verified 2026-10-31).** libXray wrapper MIT; Xray-core MPL-2.0 (file-level copyleft, notices required); Hysteria2 MIT; WireGuard MIT/Apache-2.0; SoftEther Apache-2.0. Lantern, radiance, lantern-box, and sing-box are GPL-3.0: reference only, no copied code, no use of Lantern-operated relays.

**Server supply.** Owned relays provisioned on free-tier or low-cost VPS (Oracle Cloud Always Free, Hetzner-class), BYOS import (URI, subscription URL, QR), community/public pools as an explicitly labeled opt-in source, and VPN Gate as a labeled bootstrap fallback. VPN Gate is never sold as the fast tier. Community relays may read unencrypted traffic and must never be presented as private.

**Platform constraints.** iOS packet tunnel memory budget is roughly 50 MiB; the engine and ruleset must fit with headroom. Android uses VpnService with a single TUN. Both platforms must keep IPv6 and DNS inside the tunnel, and keep the app's own traffic inside the tunnel except the tunnel socket.

**Existing capabilities to preserve.** Split tunneling with per-app routing, kill switch, relay port agility (443/992/1194), per-network relay memory, honest pre-connect probing (TLS handshake, not TCP connect), same-country exit deprioritization, and the rule that "Connected" is shown only after a data-path probe succeeds.

**Store state at time of writing.** iOS 1.1.0 in review, Android 1.1.0 live; 1.2.0 builds on TestFlight and Play internal. Premium subscriptions exist in both stores but are incomplete (ASC: 1 of 175 territories priced, missing Terms of Use link and review screenshot; Play: zero subscription products). Play has an unresolved payments-account notification.

**Explicitly undecided.** Owned-fleet provider and country mix; the public domain and signing key for the relay catalog; depth of Persian localization; whether the bulb mark survives the identity change; final typeface licensing.

## Brand Commitments

- The name **BULBVPN** stays.
- The user pinned the replacement visual world as **"Clear Air"**: light-first, atmospheric, with a **"Night Air"** dark variant. The old dark "Filament" world is retired and must not be revived as a compromise.
- No dark-neon VPN cliché, no purple, no fake precision, no gamified streaks.
- Voice: terse, technical, confident. Real readings only ("Connected · Frankfurt", "84.3 Mbps"), never decorative round numbers.

## Evidence on Hand

- On-device connection logs and measurements from OnePlus (Iran Wi-Fi) and Samsung M12 (Irancell LTE) in `docs/connection-solutions.md` and `docs/lantern-integration-progress.md`.
- Lantern mechanism study (clean-room) recorded in this conversation and the docs above.
- Live store data: Play production 1.1.0 (16) at 100%, internal 1.2.0 (17); ASC 1.1.0 waiting for review, build 17 valid; TestFlight testers and subscription metadata gaps.
- No testimonials, press, benchmarks, or user-count claims exist. Do not fabricate them.

## Product Principles

1. **Proof before "Connected."** The label appears only after traffic actually crosses the tunnel.
2. **Instant means prepared, not rushed.** Warm probes, cached last-good, and pre-ranked candidates do the waiting before the user taps.
3. **Every network is different, and the app remembers.** Scores are keyed by network and protocol, not global.
4. **Own the edge or say so.** Public and community relays are labeled, opt-in, and never disguised as private infrastructure.
5. **Calm surface, loud engineering.** The interface stays quiet while the system races, verifies, and fails over underneath.

## Accessibility & Inclusion

- Persian and RTL layouts are first-class, not an afterthought.
- Minimum 44×44 pt touch targets; WCAG AA contrast in both Clear Air and Night Air.
- Connection state is never communicated by color alone; it carries a label and icon.
- Motion respects the OS reduced-motion setting; haze and horizon effects degrade to cross-fades.
- Screen-reader labels for the connect control, server rows, and live metrics.
