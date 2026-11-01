import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:bulbvpn/core/theme/air_colors.dart';
import 'package:bulbvpn/core/theme/app_text_styles.dart';
import 'package:bulbvpn/modules/core/trust_tier.dart';
import 'package:bulbvpn/shared/air/air_layout.dart';
import 'package:bulbvpn/shared/air/air_phase.dart';
import 'package:bulbvpn/shared/air/aperture_control.dart';
import 'package:bulbvpn/shared/air/connect_trace.dart';
import 'package:bulbvpn/shared/air/data_shelf.dart';
import 'package:bulbvpn/shared/air/horizon_field.dart';
import 'package:bulbvpn/shared/air/trust_badge.dart';

class HomeViewState {
  const HomeViewState({
    required this.phase,
    required this.statusTitle,
    required this.statusDetail,
    required this.networkLabel,
    required this.clockLabel,
    required this.pingLabel,
    required this.downLabel,
    required this.upLabel,
    required this.protocolLabel,
    required this.relayLabel,
    required this.exitIp,
    required this.exitLocation,
    this.flagCode = '',
    this.trustTier,
    required this.live,
    this.measuring = false,
    this.tight = false,
    this.connectStage,
    this.busyWitness,
  });

  final AirPhase phase;
  final String statusTitle;
  final String statusDetail;
  final String networkLabel;
  final String clockLabel;
  final String pingLabel;
  final String downLabel;
  final String upLabel;
  final String protocolLabel;
  final String relayLabel;
  final String exitIp;
  final String exitLocation;
  final String flagCode;
  final TrustTier? trustTier;
  final bool live;
  final bool measuring;
  final bool tight;

  /// Non-null while a dial is in flight; switches the detail line to the
  /// three-step trace instead of an indeterminate spinner.
  final ConnectStage? connectStage;

  /// What the dial is doing right now, from the controller (engine, path N of
  /// M, relay). Real work, never an invented percentage.
  final String? busyWitness;
}

/// The connect surface: horizon, one aperture, three figures, and the two rows
/// that say where traffic leaves and through which relay.
class HomeComposition extends StatelessWidget {
  const HomeComposition({
    super.key,
    required this.state,
    required this.onConnect,
    required this.onOpenServers,
    required this.onRefreshIps,
    required this.onCopyIp,
    this.sponsored,
  });

  final HomeViewState state;
  final VoidCallback onConnect;
  final VoidCallback onOpenServers;
  final VoidCallback onRefreshIps;
  final VoidCallback onCopyIp;
  final Widget? sponsored;

  @override
  Widget build(BuildContext context) {
    return HorizonField(
      phase: state.phase,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bounded =
              constraints.hasBoundedHeight && constraints.maxHeight.isFinite;
          final view = MediaQuery.sizeOf(context);
          final height = bounded ? constraints.maxHeight : view.height;
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : view.width;
          final tight = state.tight || !bounded || height < 740;
          final railWidth = math.min(width, AirLayout.rail);
          final railLeft = (width - railWidth) / 2;
          final apertureTop = math.max(0.0, height * 0.38 - 48);

          final aperture = ApertureControl(
            phase: state.phase,
            onTap: onConnect,
            caption: _captionFor(state.phase),
          );

          final column = Column(
            mainAxisSize: tight ? MainAxisSize.min : MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopRail(state: state),
              const SizedBox(height: 10),
              _StatusBlock(state: state),
              if (tight)
                _TightApertureBand(child: aperture)
              else
                const Spacer(),
              _Shelf(state: state),
              const SizedBox(height: 10),
              _ExitRow(state: state, onRefresh: onRefreshIps, onCopy: onCopyIp),
              if (sponsored != null) ...[
                const SizedBox(height: 10),
                sponsored!,
              ],
              const SizedBox(height: 8),
              _DestinationRow(state: state, onTap: onOpenServers),
              const SizedBox(height: 96),
            ],
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: AirLayout.rail),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                      child: tight
                          ? SingleChildScrollView(child: column)
                          : column,
                    ),
                  ),
                ),
              ),
              if (!tight)
                Positioned(
                  left: railLeft + railWidth * 0.30 - 60,
                  top: apertureTop,
                  child: aperture,
                ),
            ],
          );
        },
      ),
    );
  }

  static String _captionFor(AirPhase phase) => switch (phase) {
    AirPhase.idle => 'Tap to connect',
    AirPhase.preparing => 'waking the engine',
    AirPhase.connecting => 'opening tunnel',
    AirPhase.verifying => 'checking the first byte',
    AirPhase.connected => 'Tap to disconnect',
    AirPhase.closing => 'closing the tunnel',
    AirPhase.failed || AirPhase.offline => 'Tap to retry',
  };
}

class _TopRail extends StatelessWidget {
  const _TopRail({required this.state});

  final HomeViewState state;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    return Row(
      children: [
        Flexible(
          child: Text(
            state.networkLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.label(color: air.steel, size: 10.5),
          ),
        ),
        const SizedBox(width: 14),
        Text(
          state.clockLabel,
          maxLines: 1,
          style: AppTextStyles.label(color: air.ink, size: 10.5),
        ),
      ],
    );
  }
}

class _StatusBlock extends StatelessWidget {
  const _StatusBlock({required this.state});

  final HomeViewState state;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final color = _statusColor(air, state.phase);
    final stage = state.connectStage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_statusIcon(state.phase), size: 16, color: color),
            const SizedBox(width: 8),
            Flexible(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.22),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Text(
                  state.statusTitle,
                  key: ValueKey(state.statusTitle),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.display(color: color),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: stage != null
              ? ConnectTrace(
                  key: const ValueKey('connect-trace'),
                  stage: stage,
                  witness: state.busyWitness,
                )
              : Text(
                  state.statusDetail,
                  key: const ValueKey('status-detail'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.monoValue(color: air.steel, size: 11),
                ),
        ),
      ],
    );
  }
}

class _TightApertureBand extends StatelessWidget {
  const _TightApertureBand({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 250,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned(
              left: math.max(0, constraints.maxWidth * 0.30 - 60),
              top: 80,
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _Shelf extends StatelessWidget {
  const _Shelf({required this.state});

  final HomeViewState state;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final (downValue, downUnit) = _splitRate(state.downLabel);
    final (upValue, upUnit) = _splitRate(state.upLabel);
    final hasPing = state.pingLabel != '—' && state.pingLabel.isNotEmpty;

    return DataShelf(
      metrics: [
        ShelfMetric(
          label: 'Ping',
          value: state.pingLabel,
          unit: hasPing ? 'ms' : '',
          color: air.ink,
        ),
        ShelfMetric(
          label: 'Down',
          value: downValue,
          unit: downUnit,
          color: air.connectedInk,
        ),
        ShelfMetric(
          label: 'Up',
          value: upValue,
          unit: upUnit,
          color: air.accentInk,
        ),
      ],
      // Wrap, not Row: at large accessibility text sizes the badge drops to
      // its own line instead of clipping the trust contract.
      meta: Wrap(
        spacing: 10,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            state.protocolLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.monoValue(color: air.steel, size: 12),
          ),
          if (state.trustTier != null)
            TrustBadge(tier: state.trustTier!, compact: true)
          else if (state.live)
            const _PathVerifiedBadge(),
        ],
      ),
    );
  }

  static (String, String) _splitRate(String label) {
    final cut = label.lastIndexOf(' ');
    if (cut <= 0) return (label, '');
    return (label.substring(0, cut), label.substring(cut + 1));
  }
}

class _ExitRow extends StatelessWidget {
  const _ExitRow({
    required this.state,
    required this.onRefresh,
    required this.onCopy,
  });

  final HomeViewState state;
  final VoidCallback onRefresh;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final hasIp = state.exitIp.isNotEmpty;
    // There is no exit while the tunnel is closed, and a lookup that has not
    // started yet is not a measurement.
    final placeholder = state.live || state.phase.isBusy
        ? 'Exit · measuring'
        : 'Exit · closed';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasIp ? state.exitIp : placeholder,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.monoValue(
                  color: hasIp ? air.ink : air.steel,
                  size: 12,
                ),
              ),
              if (state.exitLocation.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    state.exitLocation,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.monoValue(color: air.steel, size: 11),
                  ),
                ),
            ],
          ),
        ),
        if (hasIp)
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              onPressed: onCopy,
              padding: EdgeInsets.zero,
              tooltip: 'Copy exit IP',
              icon: Icon(Icons.copy_rounded, size: 16, color: air.steel),
            ),
          ),
        if (state.live)
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              onPressed: state.measuring ? null : onRefresh,
              padding: EdgeInsets.zero,
              tooltip: 'Refresh exit IP',
              icon: state.measuring
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: air.accent,
                      ),
                    )
                  : Icon(Icons.refresh, size: 18, color: air.steel),
            ),
          ),
      ],
    );
  }
}

class _DestinationRow extends StatelessWidget {
  const _DestinationRow({required this.state, required this.onTap});

  final HomeViewState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    final flagCode = state.flagCode;
    return Semantics(
      button: true,
      label: 'Choose relay. ${state.relayLabel}. ${state.protocolLabel}.',
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            border: Border.symmetric(
              horizontal: BorderSide(color: air.hairline),
            ),
          ),
          child: Row(
            children: [
              if (flagCode.length == 2)
                SizedBox(
                  width: 18,
                  height: 12,
                  child: SvgPicture.asset(
                    'assets/flags/$flagCode.svg',
                    fit: BoxFit.cover,
                    placeholderBuilder: (_) =>
                        Icon(Icons.public, size: 16, color: air.steel),
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.public, size: 16, color: air.steel),
                  ),
                )
              else
                Icon(Icons.public, size: 16, color: air.steel),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${state.relayLabel} · ${state.protocolLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body(color: air.ink, size: 14),
                ),
              ),
              const SizedBox(width: 8),
              if (state.trustTier != null)
                TrustBadge(tier: state.trustTier!, compact: true)
              else if (state.live)
                const _PathVerifiedBadge(),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: air.mute),
            ],
          ),
        ),
      ),
    );
  }
}

class _PathVerifiedBadge extends StatelessWidget {
  const _PathVerifiedBadge();

  @override
  Widget build(BuildContext context) {
    final air = context.air;
    return Semantics(
      label: 'Path verified',
      excludeSemantics: true,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: air.accentWash,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'PATH VERIFIED',
          maxLines: 1,
          style: AppTextStyles.label(
            color: air.accentInk,
            size: 9.5,
            tracking: 0.6,
          ),
        ),
      ),
    );
  }
}

Color _statusColor(AirColors air, AirPhase phase) => switch (phase) {
  AirPhase.idle => air.ink,
  AirPhase.preparing ||
  AirPhase.connecting ||
  AirPhase.verifying => air.accentInk,
  AirPhase.connected => air.connectedInk,
  AirPhase.closing => air.steel,
  AirPhase.failed || AirPhase.offline => air.alertInk,
};

IconData _statusIcon(AirPhase phase) => switch (phase) {
  AirPhase.idle => Icons.horizontal_rule,
  AirPhase.preparing => Icons.more_horiz,
  AirPhase.connecting => Icons.arrow_outward,
  AirPhase.verifying => Icons.visibility_outlined,
  AirPhase.connected => Icons.check,
  AirPhase.closing => Icons.close,
  AirPhase.failed => Icons.priority_high,
  AirPhase.offline => Icons.cloud_off_outlined,
};
