import 'package:flutter/material.dart';

import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/theme/metered_colors.dart';
import 'package:bulbvpn/modules/core/relay_verdict.dart';
import 'package:bulbvpn/shared/metered/metered_layout.dart';
import 'package:bulbvpn/shared/metered/pressable.dart';

/// One row of the tariff sheet: what a relay was asked to carry and what it
/// actually delivered.
class TariffRow {
  const TariffRow({
    required this.rank,
    required this.destination,
    required this.measured,
    required this.verdict,
    this.awaitingAck = false,
  });

  final String rank;
  final String destination;

  /// The measurement, already formatted, or an em dash when there is none.
  final String measured;

  /// The finding the measurement supports — the same word the relay slip prints
  /// for the same host.
  final RelayVerdict verdict;

  /// A row that changed since the user last looked holds its mark until they
  /// have, rather than flashing once and settling.
  final bool awaitingAck;
}

/// The tariff table. Blocked relays stay on the sheet: hiding them would make
/// the remaining rows look like a list of things that work.
class TariffTable extends StatelessWidget {
  const TariffTable({
    super.key,
    required this.rows,
    required this.headers,
    required this.type,
    this.onRowTap,
  });

  final List<TariffRow> rows;
  final List<String> headers;

  /// The card's print sizes, so a row is the sheet line the plate rules it on
  /// rather than whatever height the box was given.
  final MeteredType type;

  final ValueChanged<int>? onRowTap;

  /// RELAY / DESTINATION / MEASURED / STATE, ruled on the plate's own column
  /// register.
  static const _flex = MeteredLayout.tableColumns;

  /// The header band against the whole sheet: 62 of the plate's 275.
  static const _headerOfTable = 62 / 275;

  @override
  Widget build(BuildContext context) {
    final m = context.metered;
    return LayoutBuilder(
      builder: (context, c) {
        final hairline = type.px(2);
        final header = c.maxHeight * _headerOfTable;
        final rowHeight = rows.isEmpty
            ? c.maxHeight - header
            : (c.maxHeight - header) / rows.length;
        var before = 0.0;
        final bounds = <double>[];
        for (var i = 0; i < _flex.length - 1; i++) {
          before += c.maxWidth * _flex[i] / _flex.fold<int>(0, (s, f) => s + f);
          bounds.add(before);
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _GridPainter(
                hairline: hairline,
                rule: m.ruleStrong,
                columns: bounds,
                rows: [
                  for (var i = 0; i < rows.length; i++) header + rowHeight * i,
                ],
                headerBottom: header,
              ),
            ),
            Column(
              children: [
                SizedBox(
                  height: header,
                  child: _line(context, headers, header: true),
                ),
                for (var i = 0; i < rows.length; i++)
                  SizedBox(
                    height: rowHeight,
                    child: Pressable.flat(
                      onTap: onRowTap == null ? null : () => onRowTap!(i),
                      child: _line(context, [
                        rows[i].rank,
                        rows[i].destination,
                        rows[i].measured,
                        rows[i].verdict.word,
                      ], row: rows[i]),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// One ruled band. The grid is painted underneath, so the cells carry no
  /// borders of their own and a rule cannot end up twice as thick where two
  /// cells meet.
  ///
  /// The plate centres the rank and the measurement and hangs the destination
  /// and the verdict off the rule to their left: two columns read across the
  /// sheet, two read down it.
  Widget _line(
    BuildContext context,
    List<String> cells, {
    bool header = false,
    TariffRow? row,
  }) {
    final m = context.metered;
    final verdict = row?.verdict ?? RelayVerdict.untried;
    return Row(
      children: [
        for (var i = 0; i < cells.length; i++)
          Expanded(
            flex: _flex[i],
            child: Padding(
              padding: EdgeInsets.only(
                left: switch (i) {
                  1 => type.px(37),
                  3 => type.px(65),
                  _ => 0,
                },
                right: type.px(6),
              ),
              child: Row(
                mainAxisAlignment: i == 1 || i == 3
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  if (row != null && row.awaitingAck && i == cells.length - 1)
                    Container(
                      width: type.px(12),
                      height: type.px(12),
                      margin: EdgeInsets.only(right: type.px(10)),
                      decoration: BoxDecoration(
                        color: m.value,
                        shape: BoxShape.circle,
                      ),
                    ),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: i == 1 || i == 3
                          ? Alignment.centerLeft
                          : Alignment.center,
                      child: Text(
                        cells[i],
                        maxLines: 1,
                        style: _cellStyle(
                          m,
                          i,
                          header: header,
                          verdict: verdict,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// The plate sets a place name in the card's own face and everything that is
  /// a figure or a verdict in mono, so a measurement cannot be mistaken for a
  /// label. A relay that did not deliver is printed in the warm red across the
  /// whole row — the row is the finding, not one cell of it — and only a relay
  /// that actually carried bytes gets the accent, because the accent is the one
  /// colour on this card that makes a promise.
  TextStyle _cellStyle(
    MeteredColors m,
    int i, {
    required bool header,
    required RelayVerdict verdict,
  }) {
    if (header) {
      return AppTextStyles.label(
        color: m.ink,
        size: type.tableHead,
        tracking: 0.0,
      ).copyWith(height: 1.0, fontWeight: FontWeight.w600);
    }
    if (verdict.failed) {
      return AppTextStyles.monoValue(
        color: m.blockedLift,
        size: type.tableRow,
        weight: FontWeight.w700,
        height: 1.0,
        tracking: 0,
      );
    }
    final color = switch ((i, verdict)) {
      (0, _) => m.inkSoft,
      (1, _) => m.ink,
      // A round trip that only proves a handshake answered is printed a step
      // dimmer than a rate that proves bytes crossed: same column, less claim.
      (2, RelayVerdict.untried) => m.inkFaint,
      (2, RelayVerdict.unproven) => m.inkSoft,
      (2, _) => m.ink,
      _ => switch (verdict) {
        RelayVerdict.carried => m.proven,
        RelayVerdict.probed => m.ink,
        RelayVerdict.unproven => m.inkSoft,
        _ => m.inkFaint,
      },
    };
    if (i == 1) {
      return AppTextStyles.label(
        color: color,
        size: type.tableRowMixed,
        tracking: 0.0,
      ).copyWith(height: 1.0, fontWeight: FontWeight.w500);
    }
    return AppTextStyles.monoValue(
      color: color,
      size: type.tableRow,
      weight: verdict == RelayVerdict.carried
          ? FontWeight.w700
          : FontWeight.w500,
      height: 1.0,
      tracking: 0,
    );
  }
}

/// The sheet's rules, drawn as one grid rather than as the edge of each cell.
///
/// A border-per-cell table doubles its stroke wherever two cells meet, and at
/// the plate's own widths that turns a pencil rule into a cream gutter. The
/// grid also keeps the outer frame closed, which cell borders never do at the
/// last row.
class _GridPainter extends CustomPainter {
  const _GridPainter({
    required this.hairline,
    required this.rule,
    required this.columns,
    required this.rows,
    required this.headerBottom,
  });

  final double hairline;
  final Color rule;
  final List<double> columns;
  final List<double> rows;
  final double headerBottom;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = rule
      ..style = PaintingStyle.stroke
      ..strokeWidth = hairline
      ..strokeCap = StrokeCap.butt;
    final half = hairline / 2;
    canvas.drawRect(
      Rect.fromLTWH(half, half, size.width - hairline, size.height - hairline),
      p,
    );
    for (final x in columns) {
      canvas.drawLine(Offset(x, half), Offset(x, size.height - half), p);
    }
    canvas.drawLine(
      Offset(half, headerBottom),
      Offset(size.width - half, headerBottom),
      p,
    );
    for (final y in rows.skip(1)) {
      canvas.drawLine(Offset(half, y), Offset(size.width - half, y), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.hairline != hairline ||
      old.rule != rule ||
      old.columns != columns ||
      old.rows != rows ||
      old.headerBottom != headerBottom;
}
