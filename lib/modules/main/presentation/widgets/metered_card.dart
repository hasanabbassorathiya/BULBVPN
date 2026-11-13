import 'package:flutter/material.dart';

import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/theme/metered_colors.dart';
import 'package:bulbvpn/modules/main/presentation/widgets/home_composition.dart';
import 'package:bulbvpn/shared/air/air_phase.dart';
import 'package:bulbvpn/shared/metered/flip_meter.dart';
import 'package:bulbvpn/shared/metered/metered_layout.dart';
import 'package:bulbvpn/shared/metered/punched_slot.dart';
import 'package:bulbvpn/shared/metered/scratch_panel.dart';
import 'package:bulbvpn/shared/metered/tariff_table.dart';

/// The Metered connect face: its credit window, its scratch panel, its tariff
/// sheet and the single slot you push the card through.
///
/// This prints *inside* `MeteredShell`, which owns the card ground and the torn
/// nav strip. The regions are placed by fractions of the whole face, so the
/// shell's ground and this face agree on where the rim, the rules and the tear
/// fall without either one measuring the other.
class MeteredCard extends StatelessWidget {
  const MeteredCard({
    super.key,
    required this.state,
    required this.rows,
    required this.onConnect,
    required this.onOpenRelays,
    required this.onScratch,
    this.banner,
  });

  final HomeViewState state;
  final List<TariffRow> rows;
  final VoidCallback onConnect;
  final VoidCallback onOpenRelays;

  /// Tap on the exit panel: asks for a reading while it is still sealed, and
  /// copies the address once it has been shown.
  final VoidCallback onScratch;

  /// The sponsored strip, when one is due. It is given a band carved out of the
  /// tariff sheet, because an ad may cost the reader a relay line but never the
  /// card's foot: the tear and the terms hold their places either way.
  final Widget? banner;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        final type = MeteredType(size.width);
        return Stack(
          children: [
            _atTop(MeteredLayout.masthead, size, _masthead(m, type)),
            _atTop(MeteredLayout.sessionClock, size, _clock(m, type)),
            _at(MeteredLayout.headerRule, size, _rule(m.foil)),
            _at(MeteredLayout.mastheadRule, size, _rule(m.paper)),
            _at(MeteredLayout.clockRule, size, _rule(m.paper)),
            _atTop(MeteredLayout.claims, size, _claims(m, type)),
            _at(
              MeteredLayout.well,
              size,
              FlipMeter(cells: meteredCellsFor(state)),
            ),
            _at(MeteredLayout.panel, size, _panel(type)),
            _at(MeteredLayout.slot, size, _slot(type)),
            _at(_tableBox, size, _table(type)),
            _at(MeteredLayout.terms, size, _terms(m, type)),
            if (banner != null) _at(_bannerBox, size, banner!),
          ],
        );
      },
    );
  }

  /// The tariff sheet with room made for a strip: the sheet loses its lowest
  /// band and everything above it — masthead, clock, meter, panel, slot — is
  /// untouched, so the card still reads as one print in one register.
  static const Rect _bannerBox = Rect.fromLTRB(0.046, 0.660, 0.954, 0.745);

  Rect get _tableBox => banner == null
      ? MeteredLayout.table
      : Rect.fromLTRB(
          MeteredLayout.table.left,
          MeteredLayout.table.top,
          MeteredLayout.table.right,
          _bannerBox.top - 0.013,
        );

  Widget _at(Rect box, Size size, Widget child) => Positioned(
    left: box.left * size.width,
    top: box.top * size.height,
    width: box.width * size.width,
    height: box.height * size.height,
    child: child,
  );

  /// The comp boxes are ink extents, and a display face prints a taller line
  /// than the caps it draws. A block of print is anchored at the top and keeps
  /// its own height; forcing it into the ink box would make it overflow the
  /// card's own rules.
  Widget _atTop(Rect box, Size size, Widget child) => Positioned(
    left: box.left * size.width,
    top: box.top * size.height,
    width: box.width * size.width,
    child: child,
  );

  Widget _rule(Color color) => SizedBox.expand(child: ColoredBox(color: color));

  Widget _masthead(MeteredColors m, MeteredType type) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // The display line keeps its own box tight: the plate sets only 17px
      // between the wordmark's foot and the kicker's cap, and the face's normal
      // leading would spend 37 of them before the kicker is printed.
      FittedLine(
        'BULBVPN •',
        AppTextStyles.masthead(
          color: m.ink,
          size: type.wordmark,
          tracking: type.wordmarkTracking,
        ).copyWith(height: 0.80),
      ),
      SizedBox(height: type.wordmark * 0.02),
      FittedLine(
        'REGISTERED RELAY SERVICE',
        AppTextStyles.label(
          color: m.inkSoft,
          size: type.kicker,
          tracking: type.kickerRegister,
        ),
      ),
    ],
  );

  /// The clock is anchored at its ink top and keeps its own height: the comp's
  /// box runs from the kicker's cap top to the digits' base, and a figure set
  /// at that cap height prints a taller line than the digits it draws. The
  /// line heights below are what pull the box back onto the measured ink, so
  /// the digits land above the header's rule instead of across it.
  Widget _clock(MeteredColors m, MeteredType type) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      FittedLine(
        'SESSION TIME',
        AppTextStyles.label(
          color: m.inkSoft,
          size: type.kicker,
          tracking: type.kickerSession,
        ).copyWith(height: 1.0),
      ),
      SizedBox(height: type.kicker * 0.14),
      FittedLine(
        _sessionClock(),
        AppTextStyles.metric(
          color: state.live ? m.value : m.inkFaint,
          size: type.clock,
          weight: FontWeight.w700,
        ).copyWith(height: 0.86),
      ),
    ],
  );

  /// A session under an hour drops the leading zero pair: the card prints the
  /// time that is actually running, and `00:12:47` reads as three fields.
  String _sessionClock() {
    final label = state.clockLabel;
    return label.startsWith('00:') ? label.substring(3) : label;
  }

  /// The claims sit on the header's own column grid: the left pair under the
  /// wordmark, printed from the left edge, the right pair under the clock,
  /// printed flush to the rule it ends at. Their pitch is the comp's: 30px
  /// between cap tops for 24px of em, which is why the line height is set
  /// rather than left at the face's default.
  Widget _claims(MeteredColors m, MeteredType type) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        flex: 71,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedLine(
              'PRIVATE ACCESS',
              AppTextStyles.label(
                color: m.ink,
                size: type.claim,
                tracking: type.claimLeft,
              ).copyWith(height: 1.25),
            ),
            FittedLine(
              'A MORE OPEN INTERNET',
              AppTextStyles.label(
                color: m.inkSoft,
                size: type.claim,
                tracking: type.claimLeft,
              ).copyWith(height: 1.25),
            ),
          ],
        ),
      ),
      Expanded(
        flex: 29,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FittedLine(
              'SAME PEOPLE',
              AppTextStyles.label(
                color: m.ink,
                size: type.claim,
                tracking: 0,
              ).copyWith(height: 1.25),
            ),
            FittedLine(
              'FURTHER PLACES',
              AppTextStyles.label(
                color: m.inkSoft,
                size: type.claim,
                tracking: 0,
              ).copyWith(height: 1.25),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _panel(MeteredType type) => ScratchPanel(
    type: type,
    open: state.exitIp.isNotEmpty,
    prompt: 'SCRATCH TO SEE YOUR EXIT NODE',
    exitIp: state.exitIp.isEmpty ? null : state.exitIp,
    exitPlace: state.exitIp.isEmpty
        ? null
        : state.exitLocation.replaceAll(',', ' ·'),
    // A sealed panel is not inert: tapping it is how you ask for the reading.
    // Once open, the same tap takes the address off the card and onto the
    // clipboard, which is the only reason to scratch it at all.
    onOpen: onScratch,
  );

  Widget _slot(MeteredType type) => PunchedSlot(
    type: type,
    label: _slotLabel(),
    busy: state.connectStage != null,
    enabled: state.phase != AirPhase.closing,
    onTap: onConnect,
  );

  String _slotLabel() {
    if (state.connectStage != null) return state.busyWitness ?? 'DIALLING';
    return switch (state.phase) {
      AirPhase.connected || AirPhase.verifying => 'TAP TO DISCONNECT',
      AirPhase.connecting || AirPhase.preparing => 'TAP TO CANCEL',
      AirPhase.closing => 'RELEASING',
      _ => 'TAP TO CONNECT',
    };
  }

  Widget _table(MeteredType type) => TariffTable(
    type: type,
    headers: const ['RELAY', 'DESTINATION', 'MEASURED', 'STATE'],
    rows: rows,
    onRowTap: (_) => onOpenRelays(),
  );

  Widget _terms(MeteredColors m, MeteredType type) {
    // The plate's terms box is 929x192: a 2px ivory border on the card's own
    // face — it is ruled, not filled — a 24px side padding and 33px down to the
    // heading's ink. The divider sits at x777, which leaves the two columns 730
    // and 199 of the plate, and the promise on the right is four lines on a
    // 30px pitch rather than two pairs with a gap between them.
    final u = type.cardWidth / 1024.0;
    return Container(
      padding: EdgeInsets.fromLTRB(24 * u, 33 * u, 24 * u, 20 * u),
      decoration: BoxDecoration(
        border: Border.all(color: m.ruleStrong, width: type.px(2)),
        borderRadius: BorderRadius.circular(24 * u),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 730,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedLine(
                  'IF THIS READING LOOKS WRONG',
                  AppTextStyles.monoValue(
                    color: m.ink,
                    size: type.termsHead,
                    weight: FontWeight.w700,
                    height: 1.0,
                    tracking: 0,
                  ),
                ),
                SizedBox(height: type.termsHead * 0.79),
                FittedLine(
                  '1. Visit https://api.ipify.org from within the tunnel.',
                  AppTextStyles.monoValue(
                    color: m.inkSoft,
                    size: type.termsStep,
                    height: 1.0,
                    tracking: 0,
                  ),
                ),
                SizedBox(height: type.termsStep * 0.38),
                FittedLine(
                  '2. Compare the IP and location with the exit node above.',
                  AppTextStyles.monoValue(
                    color: m.inkSoft,
                    size: type.termsStep,
                    height: 1.0,
                    tracking: 0,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 13 * u),
          Container(width: type.px(2), color: m.ruleStrong),
          SizedBox(width: 13 * u),
          Expanded(
            flex: 199,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'SAME\nFREEDOM\nMORE\nTOMORROW',
                textAlign: TextAlign.left,
                style: AppTextStyles.monoValue(
                  color: m.ink,
                  size: type.termsRight,
                  weight: FontWeight.w600,
                  height: 1.2,
                  tracking: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The credit window is the state, not decoration: a figure is printed only
/// when there is a reading for it, and the wheel that is still moving is the
/// one carrying new bytes.
///
/// Four bays, because that is what the plate rules. The window is cut by rules
/// at x 272, 563 and 768 of its 934 — 226, 291, 205 and 212 — and the second
/// bay, the widest, carries no rubric. A meter leaves its own counter
/// unnamed; the three around it are the readings that need a noun.
///
/// What turns there is the age of the last byte crossing, in seconds. It is
/// the only seconds figure the card may honestly print: a round-trip time is a
/// fact about one relay and belongs in the tariff sheet's MEASURED column, and
/// the session's elapsed time is already printed above the header rule, where
/// the eye expects a clock. This one answers the question the credit window
/// exists to answer — how long ago did something actually come through — and
/// it goes blank exactly when the answer stops being a proof.
///
/// Named rather than private because this mapping *is* the card's unit rule,
/// and the only way to hold it is to state it against the readings it takes.
List<MeterCell> meteredCellsFor(HomeViewState s) {
  final traffic = _split(s.trafficLabel, 'KiB');
  final down = _split(s.downLabel, 'Mbps');
  final up = _split(s.upLabel, 'Mbps');
  final clacking = s.live && !s.measuring && s.downLabel != '—';
  return [
    MeterCell(
      rubric: 'TRAFFIC',
      value: traffic.$1,
      unit: traffic.$2,
      nudge: clacking ? traffic.$1.length - 1 : null,
    ),
    MeterCell(
      rubric: '',
      value: s.live ? _ageFigure(s.proofAge) : '—',
      unit: 's',
    ),
    // The unit is taken from the reading rather than fixed on the cell: a
    // trickle that formats as Kbps would otherwise be printed as Mbps, and a
    // card that overstates the tunnel's speed by three orders of magnitude is
    // the exact failure this app exists to not have.
    MeterCell(rubric: 'DOWN', value: down.$1, unit: down.$2),
    MeterCell(rubric: 'UP', value: up.$1, unit: up.$2),
  ];
}

/// The age with the precision the reading actually carries: centiseconds while
/// it is fresh enough to be a proof, whole seconds once it is only old, and no
/// figure at all past a minute and a quarter — a stale proof is not a reading,
/// and an empty wheel says so more honestly than a counting-up number would.
///
/// The two forms are the same width (three digits and a printed point, or two
/// digits), so the bay never has to give up tile size to hold the number.
String _ageFigure(Duration? age) {
  if (age == null || age.isNegative) return '—';
  final seconds = age.inMilliseconds / 1000.0;
  if (seconds >= 75) return '—';
  return seconds < 10 ? seconds.toStringAsFixed(2) : seconds.toStringAsFixed(0);
}

/// A reading and the unit it was printed with. The unit on the card is fixed
/// whether or not there is a number above it: an empty wheel is a missing
/// measurement, not a missing inch.
(String, String) _split(String label, String fallbackUnit) {
  final space = label.indexOf(' ');
  if (space < 0) return (label, fallbackUnit);
  return (label.substring(0, space), label.substring(space + 1));
}
