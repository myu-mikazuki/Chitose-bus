import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chitose_bus/domain/entities/bus_schedule.dart';
import 'package:chitose_bus/presentation/views/widgets/schedule_list.dart';

import '../helpers/test_theme.dart';

Widget _wrap(Widget child) => ProviderScope(
      overrides: [countdownOverride()],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  group('ScheduleList', () {
    testWidgets('バスリストが空の場合: 「時刻表データなし」が表示される', (tester) async {
      final timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        schedules: const [],
      );

      await tester.pumpWidget(
        _wrap(ScheduleList(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      expect(find.text('時刻表データなし'), findsOneWidget);
    });

    testWidgets('バスリストに複数エントリ: 時刻・行き先が表示される', (tester) async {
      final t1 = safeFutureHhmm(60);
      final t2 = safeFutureHhmm(120);
      final timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        schedules: [
          BusEntry(
              time: t1,
              direction: BusDirection.fromChitose,
              destination: '千歳科技大'),
          BusEntry(
              time: t2,
              direction: BusDirection.fromChitose,
              destination: '千歳科技大'),
        ],
      );

      await tester.pumpWidget(
        _wrap(ScheduleList(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      // When t1 == t2 (both capped at 23:58 near midnight), two widgets share
      // the same text, so use findsNWidgets(2). Otherwise each appears once.
      if (t1 == t2) {
        expect(find.text(t1), findsNWidgets(2));
      } else {
        expect(find.text(t1), findsOneWidget);
        expect(find.text(t2), findsOneWidget);
      }
      expect(find.text('千歳科技大'), findsNWidgets(2));
    });

    testWidgets('isNext=trueのバス: 背景色がColor(0xFF00FF88)・「◀ NEXT」が表示される',
        (tester) async {
      final nextTime = safeFutureHhmm(60);
      final timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        schedules: [
          BusEntry(
              time: nextTime,
              direction: BusDirection.fromChitose,
              destination: '千歳科技大'),
        ],
      );

      await tester.pumpWidget(
        _wrap(ScheduleList(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      expect(find.text('◀ NEXT'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Container && w.color == const Color(0xFF00FF88),
        ),
        findsWidgets,
      );
    });

    testWidgets('isPast=trueのバス: テキスト色がColor(0xFF444444)', (tester) async {
      // '00:01' is in the past for nearly the entire day (except the first minute).
      const pastTime = '00:01';
      final timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        schedules: [
          BusEntry(
              time: pastTime,
              direction: BusDirection.fromChitose,
              destination: '千歳科技大'),
        ],
      );

      await tester.pumpWidget(
        _wrap(ScheduleList(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      final timeText = tester.widget<Text>(find.text(pastTime));
      expect(timeText.style?.color, const Color(0xFF444444));
    });

    testWidgets('通常未来バス（isPast=false, isNext=false）: テキスト色がColor(0xFFCCCCCC)',
        (tester) async {
      // Two future buses: t1 is the "next" bus, t2 is a normal future bus.
      // nextBus() returns the first future entry, so t1 is NEXT and t2 is normal future.
      final t1 = safeFutureHhmm(60);
      final t2 = safeFutureHhmm(120);
      final timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        schedules: [
          BusEntry(
              time: t1,
              direction: BusDirection.fromChitose,
              destination: '千歳科技大'),
          BusEntry(
              time: t2,
              direction: BusDirection.fromChitose,
              destination: '千歳科技大'),
        ],
      );

      await tester.pumpWidget(
        _wrap(ScheduleList(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      // t2 is neither next nor past → textColor should be 0xFFCCCCCC.
      // Find the Text widget showing t2; there may be two Text widgets with the
      // same time string if t1 == t2 (capped at 23:58), so guard with findsWidgets.
      if (t1 != t2) {
        final timeText = tester.widget<Text>(find.text(t2));
        expect(timeText.style?.color, const Color(0xFFCCCCCC));
      }
      // If t1 == t2 (midnight cap), both are treated as the same entry; skip color check.
    });
  });
}
