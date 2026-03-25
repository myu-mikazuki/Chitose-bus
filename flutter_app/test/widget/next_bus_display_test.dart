import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';
import 'package:kagi_bus/presentation/views/widgets/next_bus_display.dart';

import '../helpers/test_theme.dart';

Widget _wrap(Widget child) => ProviderScope(
      overrides: [countdownOverride()],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  group('NextBusDisplay', () {
    testWidgets('次のバスがある場合: バス時刻・カウントダウンラベル・行き先テキストが表示される',
        (tester) async {
      final busTime = safeFutureHhmm(60);
      final timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        schedules: [
          BusEntry(
            time: busTime,
            direction: BusDirection.fromChitose,
            destination: '千歳科技大',
          ),
        ],
      );

      await tester.pumpWidget(
        _wrap(NextBusDisplay(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      // Departure time text (HH:MM format)
      expect(
        find.byWidgetPredicate((w) =>
            w is Text &&
            w.data != null &&
            RegExp(r'^\d{2}:\d{2}$').hasMatch(w.data!)),
        findsOneWidget,
      );
      // Countdown label: 60min → 'あと 1:00' (h:mm format)
      expect(
        find.byWidgetPredicate((w) =>
            w is Text &&
            w.data != null &&
            RegExp(r'^あと \d+:\d{2}$').hasMatch(w.data!)),
        findsAtLeastNWidgets(1),
      );
      expect(find.text('→ 科技大'), findsOneWidget);
    });

    testWidgets('次のバスが5分以内: カウントダウンが赤色（Color(0xFFFF4444)）', (tester) async {
      // 3 minutes ahead (≤ 5 min), capped within today.
      final busTime = safeFutureHhmm(3);
      final timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        schedules: [
          BusEntry(
            time: busTime,
            direction: BusDirection.fromChitose,
            destination: '千歳科技大',
          ),
        ],
      );

      await tester.pumpWidget(
        _wrap(NextBusDisplay(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      // minutesFromNow() ≤ 5 → label is 'あと N 分' or '発車中', color is red.
      final labelText = tester.widget<Text>(
        find.byWidgetPredicate((w) =>
            w is Text &&
            w.data != null &&
            (w.data!.contains('あと') || w.data == '発車中')),
      );
      expect(labelText.style?.color, const Color(0xFFFF4444));
    });

    // NOTE: '発車中' (minutes <= 0) is displayed only when nextBus() returns a bus whose
    // toDateTimeToday() is strictly after now() but inMinutes truncates to 0
    // (i.e. 0–59 seconds remaining in the current minute).
    // Reliably triggering this boundary requires DateTime injection into BusEntry.
    // Once bus_schedule.dart gains a `now` parameter, add a deterministic test here.
    testWidgets('発車中ラベル: 5分以内の赤色表示は「発車中」にも適用される（color確認）',
        (tester) async {
      // safeFutureHhmm(1) gives a bus 1 minute from now.
      // Depending on the seconds within the current minute, minutesFromNow() is 0 or 1.
      // Either way, it is ≤ 5, so the label color must be red (0xFFFF4444).
      final nearFuture = safeFutureHhmm(1);
      final timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        schedules: [
          BusEntry(
            time: nearFuture,
            direction: BusDirection.fromChitose,
            destination: '千歳科技大',
          ),
        ],
      );

      await tester.pumpWidget(
        _wrap(NextBusDisplay(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      // Label is either '発車中' (minutes == 0) or 'あと 1 分' (minutes == 1).
      // Both are within the ≤ 5 min threshold → color must be red.
      final labelText = tester.widget<Text>(
        find.byWidgetPredicate((w) =>
            w is Text &&
            w.data != null &&
            (w.data!.contains('あと') || w.data == '発車中')),
      );
      expect(labelText.style?.color, const Color(0xFFFF4444));
    });

    testWidgets('次のバスがない場合: 「本日の運行は終了しました」が表示される', (tester) async {
      final timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        schedules: const [],
      );

      await tester.pumpWidget(
        _wrap(NextBusDisplay(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      expect(find.text('本日の運行は終了しました'), findsOneWidget);
    });

    testWidgets('過去時刻のみのスケジュール: 「本日の運行は終了しました」が表示される', (tester) async {
      // nextBus() filters isAfter(now), so past-only schedules result in no next bus.
      const timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        schedules: [
          BusEntry(
            time: '00:01',
            direction: BusDirection.fromChitose,
            destination: '千歳科技大',
          ),
        ],
      );

      await tester.pumpWidget(
        _wrap(NextBusDisplay(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      expect(find.text('本日の運行は終了しました'), findsOneWidget);
    });

    testWidgets('カウントダウン境界値: 59分 → あと 59 分', (tester) async {
      final busTime = safeFutureHhmm(59);
      final timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        schedules: [
          BusEntry(
            time: busTime,
            direction: BusDirection.fromChitose,
            destination: '千歳科技大',
          ),
        ],
      );

      await tester.pumpWidget(
        _wrap(NextBusDisplay(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      expect(find.text('あと 59 分'), findsOneWidget);
    });

    testWidgets('カウントダウン境界値: 60分 → あと 1:00', (tester) async {
      final busTime = safeFutureHhmm(60);
      final timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        schedules: [
          BusEntry(
            time: busTime,
            direction: BusDirection.fromChitose,
            destination: '千歳科技大',
          ),
        ],
      );

      await tester.pumpWidget(
        _wrap(NextBusDisplay(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      expect(find.text('あと 1:00'), findsOneWidget);
    });

    testWidgets('カウントダウン境界値: 90分 → あと 1:30', (tester) async {
      final busTime = safeFutureHhmm(90);
      final timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        schedules: [
          BusEntry(
            time: busTime,
            direction: BusDirection.fromChitose,
            destination: '千歳科技大',
          ),
        ],
      );

      await tester.pumpWidget(
        _wrap(NextBusDisplay(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      expect(find.text('あと 1:30'), findsOneWidget);
    });

    testWidgets('arrivalsに値がある場合: 到着停留所・時刻が表示される', (tester) async {
      final busTime = safeFutureHhmm(60);
      final arrivalTime = safeFutureHhmm(80);
      final timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        schedules: [
          BusEntry(
            time: busTime,
            direction: BusDirection.fromChitose,
            destination: '千歳科技大',
            arrivals: {'kenkyuto': arrivalTime},
          ),
        ],
      );

      await tester.pumpWidget(
        _wrap(NextBusDisplay(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      expect(find.text('研究棟 着'), findsOneWidget);
      // arrivalTime may equal busTime when both are capped at 23:58 (late-night run),
      // so use findsAtLeastNWidgets(1) instead of findsOneWidget.
      expect(find.text(arrivalTime), findsAtLeastNWidgets(1));
    });
  });
}
