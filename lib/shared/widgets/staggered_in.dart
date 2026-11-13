import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Critically-damped spring curve (stiffness 100, damping 20 — DESIGN.md §6).
/// Maps t∈[0,1] onto a spring settling from 0 to 1.
class SpringCurve extends Curve {
  SpringCurve({this.stiffness = 100, this.damping = 20, this.horizon = 0.6});

  final double stiffness;
  final double damping;
  final double horizon;

  late final SpringSimulation _sim = SpringSimulation(
    SpringDescription(mass: 1.0, stiffness: stiffness, damping: damping),
    1.0, // start at 1
    0.0, // decay to 0 (so 1 - x rises 0 → 1)
    0.0,
  );

  @override
  double transformInternal(double t) {
    return (1.0 - _sim.x(t * horizon)).clamp(0.0, 1.0);
  }
}

final SpringCurve kSpring = SpringCurve();

/// Waterfall entrance: opacity 0→1 + translateY 16→0 on a spring, delayed by
/// [delayMs]. Leaf widget — never re-renders its parent (DESIGN.md §6).
class StaggeredIn extends StatefulWidget {
  const StaggeredIn({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.offset = 16,
  });

  final Widget child;
  final int delayMs;
  final double offset;

  @override
  State<StaggeredIn> createState() => _StaggeredInState();
}

class _StaggeredInState extends State<StaggeredIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  Animation<double>? _anim;

  @override
  void initState() {
    super.initState();
    _anim = CurvedAnimation(parent: _controller, curve: kSpring);
    if (widget.delayMs <= 0) {
      _controller.forward();
    } else {
      Future.delayed(Duration(milliseconds: widget.delayMs), () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final v = _anim!.value;
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1.0 - v) * widget.offset),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Formats bytes-per-second for the metric rail: `842 KB/s`, `1.2 MB/s`.
///
/// The probe column of the tariff sheet uses this: a relay probe is judged by
/// how many bytes it moved in a fixed window, and comparing that against
/// another relay is easier in bytes than in bits.
String formatRate(num bytesPerSecond) {
  if (bytesPerSecond >= 1048576) {
    return '${(bytesPerSecond / 1048576).toStringAsFixed(1)} MB/s';
  }
  if (bytesPerSecond >= 1024) {
    return '${(bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';
  }
  return '${bytesPerSecond.toStringAsFixed(0)} B/s';
}

/// Formats bytes-per-second as a link rate: `6.7 Mbps`, `940 Kbps`.
///
/// The hero card prints this because that is the unit a user measures a VPN in
/// — the same unit their speed test and their provider's plan use — while the
/// probe table stays in bytes, which is what it is compared in. Bits are
/// decimal (1 Mbps = 1,000,000 bit/s), so this is the one place in the app that
/// does not divide by 1024, and the prefix says so.
String formatMbps(num bytesPerSecond) {
  final bits = bytesPerSecond * 8;
  if (bits >= 1000000) {
    final mbps = bits / 1000000;
    return '${mbps >= 100 ? mbps.toStringAsFixed(0) : mbps.toStringAsFixed(1)}'
        ' Mbps';
  }
  return '${(bits / 1000).toStringAsFixed(0)} Kbps';
}

/// Formats a cumulative byte count for the credit meter: `0 B`, `146 KiB`,
/// `1.2 MiB`. Deliberately narrower than [formatRate] — the meter window is
/// sized for a reading, not a sentence.
///
/// The prefixes are binary because the division is: a step of 1024 is a kibibyte,
/// and a card that prints `KB` under a `/1024` figure is off by 10% at the top
/// of each band and 100% at the next one.
String formatVolume(num bytes) {
  if (bytes >= 1073741824) {
    return '${(bytes / 1073741824).toStringAsFixed(2)} GiB';
  }
  if (bytes >= 1048576) {
    return '${(bytes / 1048576).toStringAsFixed(1)} MiB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KiB';
  }
  return '${bytes.toStringAsFixed(0)} B';
}

/// Formats a Duration as `HH:MM:SS` (tabular mono metric).
///
/// Clamped at zero: a session length is measured from a wall-clock stamp, and
/// Android re-syncs the clock while a VPN is up. A backwards correction would
/// otherwise print a negative countdown in the session pill.
String formatDuration(Duration d) {
  String two(int v) => v.toString().padLeft(2, '0');
  final seconds = d.isNegative ? 0 : d.inSeconds;
  return '${two(seconds ~/ 3600)}:${two((seconds ~/ 60) % 60)}:${two(seconds % 60)}';
}

double lerpAngle(double a, double b, double t) => a + (b - a) * t;

double smoothTowards(double current, double target, double dt, double rate) {
  return current + (target - current) * (1 - math.exp(-rate * dt));
}
