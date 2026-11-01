# Design System: BULBVPN — "Clear Air"

Source of truth for every screen, color, type style, and motion decision in
the 1.2 redesign. When code and this document disagree, this document wins or
it gets amended first.

**Dials:** Creativity `7` · Density `4` · Variance `5` · Motion `4`

---

## 1. What it is

A daylit instrument, not a night-time console. The screen is sky above a
horizon and warm ground below it. One aperture opens as the tunnel comes up;
three figures sit on a single hairline; every relay states who runs it. The
app says less, and what it says is true.

Five rules:

- **One control.** The aperture is the only primary action on the connect
  surface. No card grid, no secondary connect buttons.
- **Honest instruments.** Numbers are measured or shown as `—`. Never a
  plausible-looking sample, never "connecting…" for a state that is not
  connecting.
- **The trust contract is visible.** Every relay names its operator. Public
  relays say `NOT PRIVATE` wherever they appear — never in small print.
- **Quiet by default.** Hairlines instead of cards, one accent instead of a
  gradient, motion only where it explains a state change.
- **Two lights, one world.** Day is the default. Night Air is the same world
  after dark, not a different product.

## 2. Color

`AirColors` is a `ThemeExtension` on `ThemeData`; read it as `context.air`.
Both palettes are asserted at WCAG AA in `test/air_theme_test.dart`.

| Role | Day | Night | Used for |
|---|---|---|---|
| ground | `#E9F0EC` | `#0B1416` | Scaffold base |
| surface | `#F7F4EC` | `#111D1F` | Sheets, nav bar, aperture face |
| raised | `#FCFAF3` | `#162426` | Inputs, snackbars |
| sunken | `#E1E9E4` | `#091113` | Closed aperture well, inert tracks |
| ink | `#0E1B1D` | `#E9F0EC` | Primary text, primary button fill |
| steel | `#5A6A67` | `#A9B8B3` | Secondary text, units, labels |
| mute | `#5B6B67` | `#8FA09B` | Chevrons, disabled glyphs |
| hairline | `ink @ 10%` | `white @ 10%` | Every structural 1 px line |
| hairlineStrong | `ink @ 20%` | `white @ 20%` | Input borders, control rims |
| accent | `#0E7C86` | `#4FB3BF` | Busy state, focus, nav mark |
| accentInk | `#0B656D` | `#7BD1D9` | Accent-colored text |
| accentWash | `#D8E9E8` | `#143B3E` | Private trust pill, selected row |
| connected | `#2E8B6D` | `#59C39A` | Connected state, download figure |
| connectedInk | `#246B55` | `#8ADBB9` | Connected title, done waveform |
| alert | `#C9553D` | `#E0715A` | Public trust wash, error rims |
| alertInk | `#9E3B28` | `#F0A08D` | Blocked title, NOT PRIVATE text |
| sun | `#F3E3C4` | `#E8D6AE` | The sun disc; appears only when connected |
| shadow | `ink @ 8%` | `black @ 40%` | Aperture lift, sheets |
| skyTop → skyHorizon | `#DFEBE7` → `#E9F0EC` | `#0D1A1C` → `#0B1416` | Sky gradient |
| groundHorizon → groundBottom | `#E6EBE3` → `#F4F1E8` | `#0A1213` → `#0B1416` | Ground gradient |
| haze | `#F7F4EC` | `#162426` | Drifting horizon bands while busy |

Rules: text is ink, steel, or a semantic ink — never a saturated accent body
color. Public trust always uses `alert` + `alertInk`; private trust uses
`accentWash` + `accentInk`. No pure black, no purple, no multi-stop decorative
gradients.

## 3. Type

Two families, both variable fonts registered in `pubspec.yaml`:

- **Schibsted Grotesk** (`AppTextStyles.sans`) — display, title, body.
- **Geist Mono** (`AppTextStyles.mono`) — every number, label, log line.

| Style | Size / height | Weight | Tracking | Use |
|---|---|---|---|---|
| display | 34 / 1.06 | 600 | −0.8 | The state word (`Connected`) |
| title | 21 / 1.18 | 600 | −0.3 | Sheet titles, section headers in dialogs |
| body | 15 / 1.42 | 400 | 0 | Row titles, paragraphs (12.5–14 for secondary) |
| label | 10.5 / 1.2 mono | 500 | +0.8 | Kickers, units, table labels, nav labels |
| metric | 26 / 1.0 mono | 500 | −0.6 | Shelf figures; 44 for the speed headline |
| monoValue | 12 / 1.25 mono | 500 | 0 | IPs, timers, protocol, detail lines |
| logLine | 11 / 1.5 mono | 400 | 0 | Logs only |

Colors are always explicit arguments; there is no palette bridge. Numeric
styles use tabular figures. Never center a paragraph; never set body copy in
mono; never use weight below 400.

## 4. Layout

- Rails: `AirLayout.rail = 560` for connect, servers, speed;
  `AirLayout.wideRail = 720` for settings, legal, paywall.
- Gutter 20, section gap 28. One rail per screen, centered; no per-screen
  drift.
- Rows: 56 high (48 dense); tap targets never below 44×44.
- Nav bar: 64 high plus safe area, three destinations (Connect, Servers,
  Speed) and one 44 px Settings action.
- The shell draws the body behind the nav bar (`extendBody`), so every
  scrollable surface pads its bottom by 120 — nav bar, home indicator, and
  one gutter — and its last line stays readable at rest.
- Sheets: top radius 24, `surface` fill, barrier `ink @ 28%`.
- Buttons: 50 high, radius 12. Primary is `ink` fill with `surface` text;
  secondary is a transparent fill with `hairlineStrong` border.
- The connect surface's horizon sits at 38% of the available height; the
  aperture is centred on it at 30% of the rail width. Below 740 px of height
  the column becomes scrollable and the aperture moves into a 250 px band.

## 5. Components

**HorizonField** — full-bleed sky/ground gradient with a 1 px horizon line.
Owns the atmosphere: haze bands drift only while busy; the clear sweep opens
a hole around the aperture when the path is proven; a sun disc appears only
in `connected`. Wraps every top-level screen body. List surfaces (Settings,
Routing, Speed) keep the gradient and drop the line, so it never crosses a
row.

**ApertureControl** — 96 px circular instrument with six blade ticks and a
120 px hit area. The opening radius is the state: 0.30 idle, 0.38 preparing,
0.56 connecting, 0.76 verifying, 1.0 connected, 0.14 fault. Busy states draw
a 1.6 px accent arc sweeping one revolution per 4.9 s; connected fills with
the sky gradient, adds the sun, and drifts thin flow lines. At rest the
radius breathes ±1.4% over 5.2 s — enough to read as ready, not as another
loading indicator. Press scales to 0.97 / release overshoots to 1.0. Caption
under the control: "Tap to connect", "opening tunnel", "Tap to disconnect",
"Tap to retry".

**ConnectTrace** — the busy detail line, 300 px wide max. Three stops
(`wake`, `dial`, `verify`) sit on one hairline; the accent fill advances
between stops over 420 ms, done stops are ink, the active stop pulses a
10 px dot inside an 18 px ring on a 2.2 s sine. Under it, one mono witness
line reports only what the controller knows: `REALITY · path 2 of 3 ·
Germany`, then `REALITY · first bytes · Germany` during the data gate. The
trace replaces the mono detail line only while `preparing`, `connecting`, or
`verifying`; it never shows a percentage and never invents a stage.

**DataShelf** — a top hairline, three figures (Ping / Down / Up) with mono
labels and units, then a meta line. Meta is `Wrap`-based so the protocol and
trust pill reflow instead of clipping at large text sizes. Dashes (`—`) are
steel, never colored.

**Exit row** — exit IP in mono over `City, Region · Country`, with 44 px copy
and refresh actions while live. While live or in flight without an IP it reads
`Exit · measuring`; with the tunnel closed it reads `Exit · closed` and offers
no actions.

**Destination row** — 48 px hairline-bordered row: flag, `Relay · Protocol`,
trust pill, chevron. Its Semantics label is "Choose relay. {relay}.
{protocol}."

**TrustBadge** — 24 px pill, mono 9.5, radius 6. Private tiers: `OWNED`,
`YOURS` in accent. Public tiers: `NOT PRIVATE` (compact) or
`BOOTSTRAP · NOT PRIVATE` (full) in alert. Full disclosure is always in the
Semantics label. The compact pill must not stretch; it is intrinsic width.

**AirSection / AirRow** — settings grammar: an uppercase mono title, a top
hairline, hairline-separated rows, a closing hairline, optional note. No
cards and no shadows.

**AirButton** — sheet actions only. Primary ink fill, secondary hairline.

**Nav bar** — `surface` fill with a top hairline; icon + 2 px accent mark +
label. The mark animates width over 180 ms. Settings is an icon action, not
a destination.

**Server sheet** — Auto row (`Fastest measured relay`), country sections, and
per-relay rows, each carrying its trust pill. Once pings land, a `Fastest
now` shortlist repeats the three best relays under the same `Relay N` names
their country sections use. Search filters by country and host. A notice
explains what a community relay can see. Empty and unavailable states are
written, not blank.

**Speed surface** — kicker (`READY` / `TESTING` / `LAST RESULT`), a 44 px
mono headline in Mbps, a 96 px waveform painted on a log scale with ticks at
0 / 1 / 10 / 100 / 1000, then DOWNLOAD / UPLOAD / PING and one action. A
note states whether the reading was `Through the tunnel` or `Direct
measurement — tunnel is off`. Samples are real; the waveform never invents
data.

**Paywall** — wide rail, back title `Premium`, one display line, sectioned
feature list, plan rows, and a code-redeem row. Purchase errors state what
happened and that nothing was charged; an unconfigured build says purchases
are off rather than pretending the store failed.

**Launch surfaces** — the native launch window and the Dart splash use the
same ground: `#E9F0EC` by day, `#0B1416` at night, so startup is one surface
rather than a flash between two. The Dart splash draws `BULB` + `VPN` and one
rule that draws itself in 600 ms; the app holds it at most two seconds.

## 6. State and copy

`AirPhase` has eight states, and exactly one of them is on screen.

| Phase | Word | Detail line | Aperture caption |
|---|---|---|---|
| idle | Standby | `path closed · {relay}` | Tap to connect |
| preparing | Preparing | `waking the engine` | waking the engine |
| connecting | Connecting | `opening tunnel · {relay}` | opening tunnel |
| verifying | Verifying | `checking the first byte` | checking the first byte |
| connected | Connected | `traffic confirmed · {relay}` | Tap to disconnect |
| closing | Closing | `closing the tunnel` | closing the tunnel |
| failed | Blocked | `no working path on this network` | Tap to retry |
| offline | No internet | `this network is offline` | Tap to retry |

The word is the display line. The detail is mono, one line, ellipsized. While
a dial is in flight the detail is replaced by ConnectTrace, whose witness line
names the engine, the attempt (`path 2 of 3`), and the relay the controller is
actually dialling; idle shows `prepared · {last good relay on this network}`
when memory has one. Never show two state words at once; never show a
percentage; never show a stage the controller has not reached. While live, the
relay label comes from the native session (`connectedRelay`), not from the
picker.

**Perceived wait.** A censored network can spend 20–40 s rotating paths
before one carries data. The surface is built against that reality: the
state word changes on the first tap (labor begins immediately), the trace
names the work actually happening (labor illusion), the witness line changes
with each real attempt (goal gradient without a fake bar), and idle already
states what is prepared (preparedness). Motion is evidence of work, not
decoration.

## 7. Motion

| Element | Duration | Curve |
|---|---|---|
| Clear sweep on connect | 700 ms | easeOutCubic |
| Haze return on disconnect | 500 ms | easeInOut |
| Ambient drift / breath | 9 s loop | sine |
| Aperture open | distance ÷ 4 units/s | easeOutCubic |
| Aperture idle breath | 5.2 s alternate | sine |
| Busy arc | 4.906 s per revolution | linear |
| Trace fill between stops | 420 ms | easeOutCubic |
| Trace active pulse | 2.2 s loop | sine |
| State word swap | 260 ms | easeOutCubic |
| Detail ↔ trace resize | 240 ms | easeOutCubic |
| Press / release | 140 ms / 220 ms | easeOut / easeOutBack |
| Nav active mark | 180 ms | easeOut |

Reduced motion (`MediaQuery.disableAnimationsOf`) stops the ambient loop and
the idle breath, drops the arc, flow lines, trace fill and pulse (the trace
renders its final state at once), pins the aperture to its target radius, and
shows the static sun while connected. State changes still happen; they stop
being decorative.

## 8. Accessibility and privacy

- Contrast: both palettes asserted at WCAG AA in `test/air_theme_test.dart`.
- Text scale: verified at 1.3× on home and settings; the shelf meta wraps and
  rows grow rather than clip.
- Semantics: aperture is a button with a Connect/Disconnect label and the
  phase as its value; the trust badge exposes the full disclosure; the
  destination row names relay and protocol.
- Screen security: screenshots are blocked while the tunnel is live in
  release builds (`ScreenSecurity`), and debug builds stay capturable for QA.
- Public relays are opt-in, labeled `NOT PRIVATE`, and never described as
  secure or private anywhere in the interface or the store listing.

## 9. Don't

- Don't add cards, drop shadows to rows, or a second accent.
- Don't put a spinner where a state word belongs.
- Don't show a public relay without its badge, even on marketing surfaces.
- Don't invent numbers, "typical" speeds, or unverified claims.
- Don't reintroduce the Filament palette, the bulb orb, Outfit, or
  `AppColors`; they are deleted.

## 10. Evidence

Device captures and renders live in `docs/design/evidence/phase1/`:

- Day: `home-day`, `servers-day`, `speed-idle-day`, `speed-results-day`,
  `settings-day`, `settings-about-day`, `logs-day`, `routing-day`,
  `routing-apps-day`, `paywall-day`, `onboarding-1..3`, `legal-privacy-day`.
- Night: `home-night`, `servers-night`, `settings-night-scale13`,
  `home-night-scale13`, `home-night-reduced-motion`.
- Renders: `renders/connected-*.png`, `renders/connecting-*.png`,
  `renders/verifying-*.png`.

Captures are 1080×2400 Android frames. Connected and Connecting cannot be
captured on this build network (every relay dial ends in Blocked), so
`tool/screenshots/store_shots_test.dart` renders them from the production
widget tree. The fixture's exit identity is the verified 2026-10-28 Japan
session — exit `115.179.206.241` (Ota, Gunma · ARTERIA) and the 789 ms TLS
ping recorded on IR Wi-Fi; the session clock, live rates, and protocol are
representative sampler values, not measurements. Store art is composed by
`scripts/make_store_screenshots.py`.
