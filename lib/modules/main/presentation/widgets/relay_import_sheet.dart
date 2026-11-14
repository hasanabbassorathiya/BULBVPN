import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/core/theme/simple_colors.dart';
import 'package:bulbvpn/modules/core/reality/reality_relay.dart';
import 'package:bulbvpn/modules/core/reality/relay_link.dart';
import 'package:bulbvpn/modules/core/reality/relay_vault.dart';
import 'package:bulbvpn/shared/simple/simple_card.dart';
import 'package:bulbvpn/shared/simple/simple_field.dart';
import 'package:bulbvpn/shared/simple/simple_key.dart';
import 'package:bulbvpn/shared/simple/simple_note.dart';
import 'package:bulbvpn/shared/simple/simple_section.dart';
import 'package:bulbvpn/shared/simple/simple_type.dart';

/// Paste a server in, see what tunnel it becomes, then keep it.
///
/// The preview is the feature. Every client in this class of app accepts a link
/// and then dials it, and the failure mode users report — "it connected but
/// nothing works" — is a link whose transport was silently wrong. This sheet
/// reads the profile first and prints the protocol, transport and security the
/// core will actually be handed, so a plain-TLS server is visible before it is
/// saved and a server with no TLS at all cannot be added without saying so.
Future<void> showRelayImportSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: const FractionallySizedBox(
        heightFactor: 0.72,
        child: RelayImportSheet(),
      ),
    ),
  );
}

enum _Phase { editing, reading, previewing }

class RelayImportSheet extends ConsumerStatefulWidget {
  const RelayImportSheet({super.key});

  @override
  ConsumerState<RelayImportSheet> createState() => _RelayImportSheetState();
}

class _RelayImportSheetState extends ConsumerState<RelayImportSheet> {
  final _input = TextEditingController();

  /// The bytes that will be stored. For a pasted link this is the field; for a
  /// subscription it is the body that was fetched, so what the preview showed
  /// and what gets saved are read from the same text rather than from two
  /// network calls that need not agree.
  String _pending = '';
  List<RealityRelay> _preview = const <RealityRelay>[];
  _Phase _phase = _Phase.editing;
  String? _failure;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// A single address on its own line is a subscription, not a profile.
  ///
  /// `http` is recognised here even though the fetch refuses it: an address
  /// typed over plain http has to be answered with the reason it was refused,
  /// not with "that text is not a server".
  bool get _isSubscription {
    final text = _input.text.trim();
    if (text.isEmpty || text.contains(RegExp(r'\s'))) return false;
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return false;
    return uri.isScheme('https') || uri.isScheme('http');
  }

  Future<void> _read() async {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() => _failure = 'Paste a link or an https subscription first.');
      return;
    }
    setState(() {
      _failure = null;
      _preview = const <RealityRelay>[];
    });
    if (!_isSubscription) {
      final relays = relaysFromSubscription(text);
      setState(() {
        if (relays.isEmpty) {
          _pending = '';
          _phase = _Phase.editing;
          _failure =
              'No server in that text can be dialled. A share link starts '
              'with vless://, vmess://, trojan:// or ss://.';
        } else {
          _pending = text;
          _preview = relays;
          _phase = _Phase.previewing;
        }
      });
      return;
    }
    setState(() => _phase = _Phase.reading);
    final body = await fetchSubscription(text);
    if (!mounted) return;
    if (body == null) {
      setState(() {
        _phase = _Phase.editing;
        _failure =
            'That address did not return a subscription. It has to answer '
            'over https; plain http is refused because anyone between here '
            'and the server could rewrite which relay you get.';
      });
      return;
    }
    final relays = relaysFromSubscription(body);
    setState(() {
      if (relays.isEmpty) {
        _pending = '';
        _phase = _Phase.editing;
        _failure =
            'The subscription was read but holds no profile this build can '
            'dial. It may be a Clash or sing-box config using a protocol the '
            'tunnel on this phone does not carry.';
      } else {
        _pending = body;
        _preview = relays;
        _phase = _Phase.previewing;
      }
    });
  }

  Future<void> _save() async {
    final relays = await ref
        .read(importedRelaysProvider.notifier)
        .addLinks(_pending);
    if (!mounted) return;
    if (relays.isEmpty) {
      setState(() {
        _phase = _Phase.editing;
        _failure = 'The servers could not be stored on this phone.';
      });
      return;
    }
    // Taken before the pop: the sheet's own element is gone once it closes, so
    // the message has to be addressed to the screen underneath.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Added ${relays.length} ${relays.length == 1 ? 'server' : 'servers'}. '
          'Pick one under Your servers.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _phase == _Phase.reading;
    final previewing = _phase == _Phase.previewing;
    return SimpleCard(
      child: LayoutBuilder(
        builder: (context, c) {
          final type = SimpleType(c.maxWidth);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ImportHeader(
                type: type,
                onClose: () => Navigator.maybePop(context),
              ),
              SimpleNote(
                text:
                    'Paste a share link, several links, or one https '
                    'subscription address. The tunnel on this phone reads '
                    'VLESS, VMess, Trojan and Shadowsocks over TCP, WebSocket, '
                    'gRPC, XHTTP, HTTP/2 and QUIC, with TLS or REALITY.',
              ),
              Expanded(
                flex: previewing ? 2 : 1,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    type.px(26),
                    type.px(20),
                    type.px(24),
                    type.px(8),
                  ),
                  child: SimpleField(
                    controller: _input,
                    hint: 'vless://…  or  https://provider/subscription',
                    enabled: !busy,
                    expands: true,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.none,
                  ),
                ),
              ),
              if (_failure != null)
                SimpleNote(
                  text: _failure!,
                  failed: true,
                  mark: 'NOT DIALLED',
                ),
              if (previewing)
                Expanded(
                  flex: 3,
                  child: ListView(
                    padding: EdgeInsets.only(bottom: type.px(8)),
                    children: [
                      SimpleSection(
                        title: _preview.length == 1
                            ? 'One server read'
                            : 'Servers read',
                      ),
                      for (final relay in _preview)
                        _PreviewRow(type: type, relay: relay),
                      if (_preview.any(
                        (relay) => DialShape.of(relay).isUnprotected,
                      ))
                        SimpleNote(
                          failed: true,
                          mark: 'NO TLS',
                          text:
                              'At least one of these servers runs without '
                              'TLS, so the path from this phone to it is '
                              'readable. The tunnel still hides your '
                              'traffic from other apps on the network, but '
                              'not from whoever owns the link.',
                        ),
                    ],
                  ),
                ),
              _ImportFoot(
                type: type,
                label: previewing ? 'Add ${_preview.length}' : 'Read',
                busy: busy,
                onTap: busy
                    ? null
                    : previewing
                    ? _save
                    : () => unawaited(_read()),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The head of the import slip. It carries the close key because it is the only
/// place on this face that can dismiss the sheet, which frees the foot to spend
/// its one key on the action instead of repeating the exit.
class _ImportHeader extends StatelessWidget {
  const _ImportHeader({required this.type, required this.onClose});

  final SimpleType type;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final s = context.simple;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: s.hairline, width: type.px(2)),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          type.px(26),
          type.px(22),
          type.px(24),
          type.px(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'Add your own server',
                  maxLines: 1,
                  style: AppTextStyles.label(
                    color: s.ink,
                    size: type.navLabelAttached,
                    tracking: 0,
                  ).copyWith(height: 1.0, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            SizedBox(width: type.px(16)),
            SimpleKey(label: 'Close', onTap: onClose),
          ],
        ),
      ),
    );
  }
}

/// What this profile will be on the wire, printed before it is accepted.
///
/// It is not a SlipRow: a profile that has never been dialled has no figure and
/// no verdict, and printing the columns of a measurement the card did not take
/// would put a plausible reading next to a server this phone has not touched.
/// So the row carries the name and the dial plan, and the dial plan wears the
/// refusal colour when the transport has none.
class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.type, required this.relay});

  final SimpleType type;
  final RealityRelay relay;

  @override
  Widget build(BuildContext context) {
    final s = context.simple;
    final shape = DialShape.of(relay);
    final warning = shape.isUnprotected;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: s.hairline, width: type.px(2)),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          type.px(26),
          type.px(20),
          type.px(24),
          type.px(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                relay.displayName,
                maxLines: 1,
                style: AppTextStyles.body(
                  color: s.ink,
                  size: type.tableRowMixed,
                  weight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(height: type.claim * 0.3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '${shape.summary} · ${relay.endpoint}',
                maxLines: 1,
                style: AppTextStyles.monoValue(
                  color: warning ? s.error : s.inkSoft,
                  size: type.claim,
                  weight: warning ? FontWeight.w600 : FontWeight.w500,
                  height: 1.0,
                  tracking: 0,
                ),
              ),
            ),
            if (shape.camouflagesAs != null) ...[
              SizedBox(height: type.claim * 0.26),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'pretends to be ${shape.camouflagesAs}',
                  maxLines: 1,
                  style: AppTextStyles.monoValue(
                    color: s.inkFaint,
                    size: type.kicker,
                    height: 1.0,
                    tracking: 0,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The one key this face has left: read the text, then keep what was read.
class _ImportFoot extends StatelessWidget {
  const _ImportFoot({
    required this.type,
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final SimpleType type;
  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.simple;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: s.hairline, width: type.px(2)),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          type.px(26),
          type.px(20),
          type.px(24),
          type.px(24),
        ),
        child: Align(
          alignment: Alignment.centerRight,
          child: SimpleKey(
            label: label,
            busy: busy,
            emphasis: true,
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}
