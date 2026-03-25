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

    testWidgets('arrivalsがある行をタップ: 到着停留所・時刻が展開表示される', (tester) async {
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
        _wrap(ScheduleList(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      // タップ前は到着情報が非表示
      expect(find.text('研究棟 着'), findsNothing);

      await tester.tap(find.text(busTime));
      await tester.pump();

      // タップ後は到着情報が表示
      expect(find.text('研究棟 着'), findsOneWidget);
      expect(find.text(arrivalTime), findsAtLeastNWidgets(1));
    });

    testWidgets('arrivalsがある行を2回タップ: 到着情報がトグル非表示になる', (tester) async {
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
        _wrap(ScheduleList(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      // 1回目タップ → 展開
      await tester.tap(find.text(busTime));
      await tester.pump();
      expect(find.text('研究棟 着'), findsOneWidget);

      // 2回目タップ → 折りたたみ
      await tester.tap(find.text(busTime));
      await tester.pump();
      expect(find.text('研究棟 着'), findsNothing);
    });

    testWidgets('arrivalsが空の行をタップ: 何も表示されない', (tester) async {
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
        _wrap(ScheduleList(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      await tester.tap(find.text(busTime));
      await tester.pump();

      expect(find.text('研究棟 着'), findsNothing);
    });

    testWidgets('NEXTバスが画面外にあっても初期表示でスクロールされて見える', (tester) async {
      // kTestNow = 09:00。過去便を18件並べてNEXTを画面外に追いやる
      final pastTimes = List.generate(
        18,
        (i) => '0${i ~/ 6 + 1}:${(i % 6 * 10).toString().padLeft(2, '0')}',
      );
      final nextTime = safeFutureHhmm(60); // 10:00

      final timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        schedules: [
          ...pastTimes.map((t) => BusEntry(
                time: t,
                direction: BusDirection.fromChitose,
                destination: '科技大',
              )),
          BusEntry(
            time: nextTime,
            direction: BusDirection.fromChitose,
            destination: '科技大',
          ),
        ],
      );

      // 高さ制限を設けて NEXT を画面外にする（ListView.builder では描画されない高さ）
      await tester.pumpWidget(
        ProviderScope(
          overrides: [countdownOverride()],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 200,
                child: ScheduleList(
                    timetable: timetable,
                    direction: BusDirection.fromChitose),
              ),
            ),
          ),
        ),
      );
      await tester.pump(); // postFrameCallback を発火させる

      // NEXT バスが画面内に表示されている（スクロールされた）
      expect(find.text(nextTime), findsOneWidget);
      expect(find.text('◀ NEXT'), findsOneWidget);
    });
  });
}
