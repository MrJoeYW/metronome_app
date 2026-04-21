import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:metronome_app/main.dart';

void main() {
  testWidgets('Metronome dashboard renders', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('Start Pulse'), findsOneWidget);
    expect(find.text('4/4'), findsOneWidget);
    expect(find.text('5/4'), findsOneWidget);
    expect(find.text('1/4'), findsNothing);
    expect(find.text('TAP TEMPO'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('Session Settings'), findsNothing);
  });

  testWidgets('Bpm dial outer ring responds to drag', (
    WidgetTester tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);

    var changedBpm = 120;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: BpmDial(
              bpm: 120,
              min: kMinBpm,
              max: kMaxBpm,
              pulseAmount: 0,
              size: 300,
              onChanged: (value) => changedBpm = value,
              onTapTempo: () {},
            ),
          ),
        ),
      ),
    );

    final dial = find.byType(BpmDial);
    final center = tester.getCenter(dial);
    final gesture = await tester.startGesture(center + const Offset(120, 0));
    await gesture.moveTo(center + const Offset(0, -120));
    await tester.pump();
    await gesture.up();

    expect(changedBpm, isNot(120));
  });

  test('Tap tempo uses moving average and ignores outliers', () {
    final tracker = TapTempoTracker(
      windowSize: 6,
      timeout: const Duration(seconds: 2),
      outlierTolerance: 0.30,
    );
    var now = DateTime(2026, 1, 1, 12);

    expect(tracker.registerTap(now).state, TapTempoState.primed);

    now = now.add(const Duration(milliseconds: 500));
    final secondTap = tracker.registerTap(now);
    expect(secondTap.state, TapTempoState.collecting);
    expect(secondTap.bpm, 120);

    now = now.add(const Duration(milliseconds: 500));
    final thirdTap = tracker.registerTap(now);
    expect(thirdTap.state, TapTempoState.locked);
    expect(thirdTap.bpm, 120);

    now = now.add(const Duration(milliseconds: 900));
    final outlierTap = tracker.registerTap(now);
    expect(outlierTap.state, TapTempoState.outlier);
    expect(outlierTap.bpm, isNull);

    now = now.add(const Duration(milliseconds: 500));
    final recoveredTap = tracker.registerTap(now);
    expect(recoveredTap.state, TapTempoState.locked);
    expect(recoveredTap.bpm, 120);
  });

  test('Tap tempo resets after timeout', () {
    final tracker = TapTempoTracker(
      windowSize: 6,
      timeout: const Duration(seconds: 2),
      outlierTolerance: 0.30,
    );
    var now = DateTime(2026, 1, 1, 12);

    tracker.registerTap(now);
    now = now.add(const Duration(milliseconds: 480));
    expect(tracker.registerTap(now).bpm, 125);

    now = now.add(const Duration(seconds: 3));
    final resetTap = tracker.registerTap(now);
    expect(resetTap.state, TapTempoState.primed);
    expect(resetTap.sampleCount, 1);
    expect(resetTap.bpm, isNull);
  });

  test('Tap tempo adapts after two consistent faster taps', () {
    final tracker = TapTempoTracker(
      windowSize: 6,
      timeout: const Duration(seconds: 2),
      outlierTolerance: 0.30,
    );
    var now = DateTime(2026, 1, 1, 12);

    tracker.registerTap(now);
    now = now.add(const Duration(milliseconds: 500));
    tracker.registerTap(now);
    now = now.add(const Duration(milliseconds: 500));
    tracker.registerTap(now);

    now = now.add(const Duration(milliseconds: 320));
    final firstShiftTap = tracker.registerTap(now);
    expect(firstShiftTap.state, TapTempoState.outlier);
    expect(firstShiftTap.bpm, isNull);

    now = now.add(const Duration(milliseconds: 320));
    final secondShiftTap = tracker.registerTap(now);
    expect(secondShiftTap.state, TapTempoState.collecting);
    expect(secondShiftTap.bpm, closeTo(188, 1));
  });
}
