import 'package:flutter/widgets.dart';
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
