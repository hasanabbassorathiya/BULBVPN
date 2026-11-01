import 'package:bulbvpn/core/theme/app_theme.dart';
import 'package:bulbvpn/shared/air/air_phase.dart';
import 'package:bulbvpn/shared/air/connect_trace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _harness({
  required ConnectStage stage,
  String? witness,
  bool disableAnimations = true,
  double textScale = 1.0,
}) {
  return ScreenUtilInit(
    designSize: const Size(390, 844),
    minTextAdapt: true,
    splitScreenMode: true,
    builder: (_, __) => MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: disableAnimations,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: _TraceHost(initialStage: stage, initialWitness: witness),
        ),
      ),
    ),
  );
}

class _TraceHost extends StatefulWidget {
  const _TraceHost({required this.initialStage, this.initialWitness});

  final ConnectStage initialStage;
  final String? initialWitness;

  @override
  State<_TraceHost> createState() => _TraceHostState();
}

class _TraceHostState extends State<_TraceHost> {
  late ConnectStage _stage = widget.initialStage;
  late String? _witness = widget.initialWitness;

  void update(ConnectStage stage, String? witness) {
    setState(() {
      _stage = stage;
      _witness = witness;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ConnectTrace(stage: _stage, witness: _witness);
  }
}

void main() {
  test('only the three working phases own a stage', () {
    for (final phase in AirPhase.values) {
      final stage = connectStageFor(phase);
      switch (phase) {
        case AirPhase.preparing:
          expect(stage, ConnectStage.wake);
        case AirPhase.connecting:
          expect(stage, ConnectStage.dial);
        case AirPhase.verifying:
          expect(stage, ConnectStage.verify);
        default:
          expect(stage, isNull, reason: 'phase $phase');
      }
    }
  });

  testWidgets('names all three stops and repeats the controller witness', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _harness(
        stage: ConnectStage.dial,
        witness: 'REALITY · path 2 of 3 · Germany',
      ),
    );

    expect(find.text('wake'), findsOneWidget);
    expect(find.text('dial'), findsOneWidget);
    expect(find.text('verify'), findsOneWidget);
    expect(find.text('REALITY · path 2 of 3 · Germany'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Connection progress. opening the path, step 2 of 3. '
        'REALITY · path 2 of 3 · Germany.',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('advances without inventing a fourth stop', (tester) async {
    await tester.pumpWidget(_harness(stage: ConnectStage.wake));
    final host = tester.state<_TraceHostState>(find.byType(_TraceHost));

    host.update(ConnectStage.dial, 'SoftEther · path 1 of 2 · Japan');
    await tester.pumpAndSettle();
    expect(find.text('SoftEther · path 1 of 2 · Japan'), findsOneWidget);

    host.update(ConnectStage.verify, 'SoftEther · first bytes · Japan');
    await tester.pumpAndSettle();
    expect(find.text('SoftEther · first bytes · Japan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stays within the rail at 1.3 text scale', (tester) async {
    await tester.pumpWidget(
      _harness(stage: ConnectStage.dial, textScale: 1.3),
    );
    await tester.pumpAndSettle();

    final size = tester.getSize(find.byType(ConnectTrace));
    expect(size.width, lessThanOrEqualTo(300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('motion mode does not change the copy', (tester) async {
    await tester.pumpWidget(
      _harness(
        stage: ConnectStage.verify,
        witness: 'OpenVPN · first bytes · Netherlands',
        disableAnimations: false,
      ),
    );
    await tester.pump(const Duration(milliseconds: 450));

    expect(find.text('verify'), findsOneWidget);
    expect(
      find.text('OpenVPN · first bytes · Netherlands'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
