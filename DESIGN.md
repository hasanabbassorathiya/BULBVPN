# Design System: BULBVPN — "Filament"

Enterprise-grade VPN app. Dark, instrument-grade, alive. This document is the single
source of truth for every screen, widget, color, type style, and motion decision.

**Dials:** Creativity `8` · Density `5` · Variance `7` · Motion `7`

---

## 1. Visual Theme & Atmosphere

A night-time mission console lit by a single warm filament. The canvas is deep
blue-charcoal (never black), the only saturated color in the entire interface is
Filament Amber — the light the bulb throws. Everything else is quiet neutral
plumbing: hairlines, dim labels, one clear instrument at the center.

The four ideas drive every screen:

- **BULB** — the connect control is a literal bulb: a filament that warms up,
  flickers during handshake, and breathes when live.
- **INTERNET** — concentric dashed tunnel rings orbit the bulb; packets are
  dots that ride them when connected.
- **LOCATION** — a dim meridian/globe motif behind the console; every server
  row carries its flag + city + latency as a coordinate.
- **SPEED** — the speed test is a machined gauge: spring needle, tabular
  monospace readouts, a faint trail behind the sweep.

Density is balanced (5): one instrument per screen, data in disciplined rails —
not a wall of cards. Variance is high (7): no two sections share a layout.
Motion is cinematic (7): state changes are choreographed, idle states breathe.

## 2. Color Palette & Roles

### Neutrals (the plumbing)
- **Night Canvas** `#0A0D14` — root scaffold background. Blue-charcoal, not black.
- **Console Surface** `#11151F` — sheets, bottom nav, cards.
- **Raised Surface** `#171C29` — inputs, active rows, chips.
- **Ink** `#F2F4F8` — primary text.
- **Steel** `#99A1B3` — secondary text, descriptions, unit labels.
- **Mute** `#5B6478` — tertiary text, disabled, timestamps.
- **Hairline** `rgba(255,255,255,0.08)` — all 1px structural borders.
- **Shadow** `rgba(0,0,0,0.45)` — sheets only, wide blur (24px), low opacity.

### Accent (exactly one)
- **Filament Amber** `#E9A23B` (HSL sat 78%) — the ONLY decorative accent.
  Used for: the bulb filament and its halo, primary buttons, active nav state,
  focus rings, the connected pulse, progress arcs, key metrics.
- **Amber Tint** `rgba(233,162,59,0.12)` — wash backgrounds, chip fills,
  selected-row highlights. Never a full-screen fill.

### Semantic status (state reporting only — never decoration)
- **Live Emerald** `#3FB98A` — connected state, download series.
- **Alert Red** `#E5484D` — failed, no-internet, errors.
- **Standby Graphite** `#3A4152` — idle/disconnected instrument ring.
- **Sky Series** `#56A8E8` (sat 76%) — upload series in speed test only.

State aura (behind the orb, radial, very low opacity): idle = graphite,
connecting = amber, connected = emerald, failed = red. Cross-fade 600ms.

### Banned
Purple/violet neon gradients · pure `#000000` · accents above 80% saturation ·
mixing warm and cool grays · colored body text (text is neutral, always).

## 3. Typography Rules

- **Display:** `Outfit` — weights 500/600/700. Letter-spacing `-0.02em` at
  24px+. Line-height 1.1. Hierarchy comes from weight + color, not size wars.
  Headline sizes: 32 / 24 / 20 (app); section titles 16.
- **Body:** `Outfit` 400/500 — line-height 1.5, sizes 15 / 13. Steel color.
- **Mono / all numbers:** `Geist Mono` (fallback `JetBrains Mono`) — every
  speed, ping, IP, byte counter, timer, percentage. `font-variant-numeric:
  tabular-nums`. Metric readouts: 28–40px mono 500. Micro-labels: 11px mono
  uppercase, tracking `+0.08em`, Mute color.
- **Banned:** `Inter` anywhere. Generic serifs anywhere. System default fonts.
  Centered all-caps paragraphs. Emoji as icons.

## 4. Component Stylings

- **The Bulb (connect control):** 200px orb. Off-state: Standby Graphite ring,
  filament path dim (`#3A4152`). Connecting: filament animates warm-up flicker
  (3–5 opacity steps, 120ms), tunnel rings rotate at opposing speeds. Connected:
  filament at full Amber, soft radial halo (gradient, opacity ≤ 0.25 — NOT a
  box-shadow glow), perpetual breathing scale 1.0→1.025 at 2.4s. Tactile
  `scale(0.96)` on press. The orb is a real button: 44px+ hit target (it is 200px).
- **Buttons:** Height 52px, radius 16px. Primary = Amber fill, `#0A0D14` text,
  weight 600. Secondary = ghost, 1px Hairline border, Ink text. Active press =
  `scale(0.98)` + brightness shift. No glows, ever. Full-width on mobile.
- **Cards / rows:** radius 16px, Console Surface fill, 1px Hairline border,
  NO drop shadows inside the scroll content. Rows in lists use bottom Hairline
  dividers instead of cards. Cards only for genuinely elevated things (server
  picker summary, result tiles).
- **Inputs:** Raised Surface fill, radius 12px, label above (11px mono
  uppercase Mute), focus = 1px Amber border + Amber tint fill. No floating labels.
- **Nav bar (bottom):** floating pill, Console Surface, 1px Hairline, radius
  999. Active item: Amber icon + Amber tint pill behind it (layout-animating
  pill, spring). 44px minimum targets, 3 destinations + separate info action.
- **Loaders:** skeleton shimmer matching final layout dims — never a lone
  circular spinner (a gauge sweep or ring rotation as part of the instrument
  is fine).
- **Log console:** monospace 11px, timestamp Mute, message Steel, errors Alert
  Red, success Live Emerald. Auto-scroll, rows stagger in 40ms apart.
- **Server row:** flag (24px, rounded 6px) + country (Outfit 500 Ink) + city
  (13px Steel) + right-aligned latency in mono with 3-bar signal glyph
  (emerald ≥80ms? no — bars: <100ms 3 bars, <200ms 2, else 1; bar color Steel,
  best-servers Amber). Selected row: Amber tint fill + 2px left Amber rail.

## 5. Layout Principles

- **One instrument per screen.** Main screen: status rail top-left (asymmetric),
  bulb orb off-center on the vertical axis (optical center at 42% height),
  metric rail bottom-left, server pill docked above the nav — the composition
  reads as a console, not a centered toy.
- **Asymmetric hero, always.** Centered stacks are banned. Split the screen
  with a dominant element + a data rail; let one side breathe.
- **No 3-equal-card grids.** Features/stats use a 2-col asymmetric rail
  (e.g. 1.6fr / 1fr) or a horizontal scroll strip of 82%-width tiles.
- **No overlapping content.** Every element owns its zone; the meridian motif
  is background-only (opacity ≤ 0.06), never behind readable text at high
  contrast.
- **Containment:** content max-width 480px centered (phone), side padding 20px.
  Safe-area respected top and bottom.
- **Full height:** `min-h-[100dvh]` equivalent — scroll views, not fixed heights.
- **Touch:** every interactive target ≥ 44×44px, ≥ 8px apart.

## 6. Motion & Interaction

- **Physics:** spring only — `stiffness: 100, damping: 20` (SpringSimulation
  / `SpringTransition`). No linear easing. Durations: micro 180–260ms,
  state change 400–600ms, entrance stagger 60ms per item.
- **Entrances:** lists and rails mount staggered — opacity 0→1 + translateY
  16→0, `delay = index * 60ms`, spring. Never instant mounts.
- **Perpetual micro-loops (idle = alive):** bulb breathes (2.4s); tunnel rings
  counter-rotate (18s / 26s) — speed up to 2s while connecting; status dot
  pulses; gauge needle micro-jitters ±0.5 on live readings; meridian globe
  drifts 60s/rotation; packet dots orbit rings only when connected.
- **State choreography (connect tap):** press squash (0.96, 90ms) → filament
  warm-up flicker (900ms) → rings spin up (600ms) → on success, halo blooms
  once (scale 1→1.15→1, 500ms) and status rail cross-fades to emerald.
- **Transform/opacity only.** Never animate layout metrics. Heavy perpetual
  animations live in leaf widgets (CustomPainter / SingleTickerProviderStateMixin)
  so they never re-render parents.
- **Reduced motion:** respect `disableAnimations` — cross-fade instead of
  spring, stop counter-rotations, keep state colors.

## 7. Anti-Patterns (Banned)

- No emojis anywhere (UI, labels, empty states).
- No `Inter` font; no generic serifs; no system font fallbacks left in place.
- No pure `#000000`; no purple/violet neon; no box-shadow glows (halo =
  radial gradient inside the component, opacity ≤ 0.25).
- No second decorative accent color — status colors are for state only.
- No 3-equal-card grids; no centered symmetric hero compositions.
- No circular spinners as primary loading UI; no bare "No data" empty states.
- No AI copy: "Elevate", "Seamless", "Unleash", "Next-Gen", "Revolutionize",
  "Your gateway to…". Voice: terse, technical, confident. "Connected · Frankfurt".
- No fake round numbers (`99.99%`, `50 Mbps` as decoration) — real readings,
  one decimal (`84.3 Mbps`), real cities, real latencies.
- No emoji-flag glyphs — bundled SVG flags only.
- No overlaps, no z-index layering of content, no instructional filler
  ("Tap to connect" is allowed ONCE as the bulb's micro-label; "Scroll for more"
  is banned).
- No text under 11px; no white-on-amber text (amber fill takes dark text).
