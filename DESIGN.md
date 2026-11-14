# Design System: BULBVPN — "Simple VPN"

Source of truth for every screen, color, type style, and motion decision in
the 1.2 redesign. When code and this document disagree, this document wins or
it gets amended first.

Dark mode only — OLED-safe ground (#0F172A), navy primary (#1E3A5F), connected
green (#22C55E) accent that means "bytes are crossing", white foreground. The
app is dark everywhere: it runs in the background and only surfaces when it has
something to say.

---

## 1. What it is

**Operate mode.** The visitor completes a task: connect, check a reading, pick a
relay, change a setting. Scanability, consistency, and the real usage scene
outrank expression. Brand lives in precise details.

**Thesis:** a single card per screen, one primary action, measured figures only.
No glow orb, no map, no punch slot, no foil scratch, no tear strip. The
interface is quiet by default — hairlines instead of borders, one accent color,
motion only where it explains a state change.

Five rules:

- **One primary action per screen.** The green key button is the only emphasized
  control; every other action is subordinate text or a tinted icon.
- **Honest instruments.** Numbers are measured or shown as `—`. Never a
  plausible-looking sample, never "connecting…" for a state that is not
  connecting.
- **The trust contract is visible.** Public relays say `NOT PRIVATE` wherever
  they appear — never in small print.
- **Quiet by default.** Hairlines instead of cards, one accent instead of a
  gradient, motion only where it explains a state change.
- **No feature cut.** Connect, server picker, settings, speed test, paywall,
  i18n/RTL, splash, onboarding, legal — all kept, only the visual layer changed.

---

## 2. Color

`SimpleColors` is a `ThemeExtension` read as `context.simple`. Dark mode only;
there is no day/night split and no palette bridge — every color is explicit at
the call site.

| Role | Value | Used for |
|---|---|---|
| primary | `#1E3A5F` | Navy brand; non-emphasis key button fill |
| background | `#0F172A` | OLED-safe screen ground |
| surface | `#1E293B` | Card surface print |
| surfaceVariant | `#334155` | Subtle grouping surface |
| ink | `#FFFFFF` | White foreground — primary print |
| inkSoft | `#CBD5E1` | Secondary print |
| inkFaint | `#64748B` | Tertiary print, small text |
| hairline | `#33FFFFFF` | Subtle 1px dividers and borders |
| connected | `#22C55E` | Emphasis key button fill; "bytes crossing" |
| connectedInk | `#065F46` | Text printed on connected green |
| error | `#EF4444` | Failed states |
| errorInk | `#FEE2E2` | Text printed on error red |

Rules:

- Text is ink, inkSoft, inkFaint, or a semantic ink — never a saturated
  accent body color.
- The `connected` green is the one accent on screen that means "bytes are
  crossing"; nothing else uses it decoratively.
- No pure black, no purple, no multi-stop decorative gradients. Shadows are
  hairlines, not elevation.

---

## 3. Type

Two families, both variable fonts registered in `pubspec.yaml`:

- **Vazirmatn** (`AppTextStyles.sans`) — sets Latin and Persian from one family,
  so an RTL sheet is the same card mirrored rather than a substitute face. Used
  for display, title, body, and kickers.
- **Geist Mono** (`AppTextStyles.mono`) — every figure, label, log line, and
  unit. A reading gets fixed cells (tabular figures prevent layout shift).

| Style | Size / height | Weight | Tracking | Use |
|---|---|---|---|---|
| display | 30 / 1.0 | 600 | 0 | Section headlines ("Ground rules") |
| title | 17 / 1.0 | 500 | 0 | Section headers, nav labels |
| body | 14–15 / 1.4–1.6 | 400 | 0 | Row titles, paragraphs |
| label | 10–10.5 / 1.2–1.4 | 500 | 0–0.4 | Rubrics, units, small print |
| monoValue | 11–15 / 1.25 | 500–600 | 0 | IPs, timers, protocol, detail lines |

Sizes are logical pixels. `flutter_screenutil`'s `.sp` is banned in this
codebase. Colors are always explicit at call sites (`context.simple.ink` etc.).

`SimpleType` computes a responsive type scale off a 375px reference width,
clamped to 0.85–1.15×, so a single comp lands sensibly on small and large
phones without a breakpoint system.

Never center a paragraph; never set body copy in mono; never use weight below
400.

---

## 4. Layout

`SimpleLayout` measures nothing off a comp; every screen is a `Scaffold` with
`backgroundColor: s.background` and content inside a `ConstrainedBox(
maxWidth: 720)` so it reads well on tablets and foldables too.

- `cardRadius = 12`.
- Bottom nav: `DefyxNavBar`, height 64, surface print with a hairline top rule.
  Four destinations: Connect, Servers, Speed, Settings — icon + label,
  active state underlined in `s.connected`. A gear action button sits apart
  from the rail (openly separate, not a floating pill).
- Every screen pads itself by the bottom nav extent so nothing lands under a
  torn tab.
- Rows: `SimpleTermRow` — title left, optional sub right, optional trailing
  widget or value; `SimpleSection` — section header with optional leading,
  note, and disclosure mark; `SimpleNote` — a single line of print with an
  optional mark above it; `SimpleTrustMark` — a small mark at the trailing edge
  of a row (e.g. `NOT PRIVATE`).
- `SimpleCard` — surface card with hairline border and 12px corners; holds one
  face of the app.
- `SimpleKey` — the one key button: 44px tall, green fill when emphasis, navy
  otherwise, disabled state in inkFaint; content-width and centered.
- `TextButton` is used for secondary actions ("Back", "Restore purchases",
  footer links) — never a second emphasized button.

---

## 5. Components

**SimpleCard** — surface (`surface`) print on background (`background`), hairline
border (`hairline`), 12px corners. One face per screen.

**SimpleKey** — the one action button. Emphasis prints `connected` green with
`connectedInk` text; plain prints `primary` navy. Busy state shows a
18px spinner and locks the tap. 44px height minimum per the touch-target rule.

**SimpleSection** — section header: title in `ink`, optional leading mark,
optional `note` subtitle below, optional `disclosure` mark at the trailing
edge. `proven` prints the disclosure in `connected`, otherwise `error`.

**SimpleTermRow** — one settings line: title left (`ink`), optional sub below
in `inkSoft`, optional trailing value in mono, optional trailing widget.
`failed` prints title in `error`. `selected` lifts the surface to
`surfaceVariant`. 44px touch target.

**SimpleNote** — a single line of print: `text` in `inkSoft` / `error`
(failed), optional `mark` label above in `inkFaint`.

**SimpleTrustMark** — small trailing mark (e.g. `NOT PRIVATE`), `proven` green
or `error` red, never conveying meaning by color alone.

**SimpleField** — text input under a section: label above, value or hint below,
mono figures where applicable.

---

## 6. State and copy

`AirPhase` has eight states, exactly one on screen:

| Phase | Word | Meaning |
|---|---|---|
| idle | Standby | Path closed; prepared relay shown from memory |
| preparing | Preparing | Waking the engine |
| connecting | Connecting | Opening tunnel |
| verifying | Verifying | Checking the first byte |
| connected | Connected | Traffic confirmed · relay |
| closing | Closing | Closing the tunnel |
| failed | Blocked | No working path on this network |
| offline | No internet | This network is offline |

`RelayVerdict` is one vocabulary printed by both the connect surface and the
relay sheet:

| Verdict | Word | Meaning |
|---|---|---|
| carried | CARRIED | Bytes crossed this relay on this device — the only verdict that says the path works |
| probed | PROBED | Someone else's probe moved bytes; a fact about a datacenter, not this network |
| unproven | NOT PROVEN | Something answered, nothing carried |
| blocked | BLOCKED | A measurement came back refused or empty |
| untried | — | No measurement yet |

The word is the display line. ConnectTrace replaces the detail line only while
`preparing`, `connecting`, or `verifying`; it never shows a percentage and
never invents a stage. The witness line names the engine, the attempt
(`path 2 of 3`), and the relay the controller is actually dialling.

**Perceived wait.** A censored network can spend 20–40 s rotating paths before
one carries data. The state word changes on the first tap (labor begins
immediately), the trace names the work actually happening, the witness line
changes with each real attempt (goal gradient without a fake bar), and idle
already states what is prepared. Motion is evidence of work, not decoration.

---

## 7. Motion

| Element | Duration | Curve |
|---|---|---|
| Key press / release | 90 ms / 150 ms | easeOut / easeOutBack |
| Page progress bar | 220 ms | easeOut |
| Panel crossfade | 150–300 ms | easeOut |

Reduced motion (`MediaQuery.disableAnimationsOf`) parks animations at their
final reading. State changes still happen; they stop being decorative.

---

## 8. Accessibility and privacy

- Contrast: both `connected` (#22C55E) and `error` (#EF4444) meet WCAG AA
  against `background` (#0F172A) and `surface` (#1E293B); `ink` (#FFFFFF) on
  `background` exceeds AAA.
- Text scale: verified at 1.3×; rows grow rather than clip; notes wrap.
- Semantics: the key button exposes its label; the trust badge exposes the full
  disclosure; the destination row names relay and protocol.
- Selection is never the fill alone. A selected row also carries
  `Semantics(selected:)`.
- RTL: Vazirmatn sets Persian and Latin from one family; layouts mirror.
- Screen security: screenshots blocked while the tunnel is live in release
  builds (`ScreenSecurity`); debug builds stay capturable for QA.
- Public relays are opt-in, labeled `NOT PRIVATE`, and never described as
  secure or private anywhere in the interface or the store listing.

---

## 9. Don't

- Don't add cards, drop shadows to rows, a second accent, or glass/bloom on
  controls.
- Don't put a spinner where a state word belongs.
- Don't show a public relay without its badge, even on marketing surfaces.
- Don't invent numbers, "typical" speeds, or unverified claims.
- Don't reintroduce the Metered palette, the punch slot, the foil scratch, the
  tear strip, `MeteredColors`, `AirColors`, or the Clear Air world; they are
  deleted.

---

## 10. Evidence

The comp is `.impeccable/mocks/decision/simple.png` (reference 375×812). The
spec is `.impeccable/build/spec.json` (simple-spec v1), which names every
region (card, section, term row, key, trust mark, nav rail, key action) and
each region's semantic medium.
