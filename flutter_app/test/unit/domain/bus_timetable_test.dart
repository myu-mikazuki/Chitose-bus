import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';

void main() {
  // Fixed reference time for deterministic tests: 2024-06-15 12:00:00
  final fixedNow = DateTime(2024, 6, 15, 12, 0, 0);

  group('BusTimetable', () {
    group('nextBus', () {
      test('returns first bus after current time from multiple entries', () {
        const timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-12-31',
          schedules: [
            BusEntry(
              time: '11:00', // past (before fixedNow 12:00)
              boardingStopId: 'chitose',
              destination: '科技大',
            ),
            BusEntry(
              time: '13:00', // future (after fixedNow 12:00)
              boardingStopId: 'chitose',
              destination: '科技大',
            ),
          ],
        );

        final result = timetable.nextBus('chitose', now: fixedNow);
        expect(result, isNotNull);
        expect(result!.time, '13:00');
      });

      test('returns null when all buses are in the past', () {
        const timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-12-31',
          schedules: [
            BusEntry(
              time: '11:00',
              boardingStopId: 'chitose',
              destination: '科技大',
            ),
          ],
        );

        final result = timetable.nextBus('chitose', now: fixedNow);
        expect(result, isNull);
      });

      test('returns only buses with the specified direction', () {
        const timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-12-31',
          schedules: [
            BusEntry(
              time: '13:00',
              boardingStopId: 'minamiChitose',
              destination: '南千歳',
            ),
            BusEntry(
              time: '13:00',
              boardingStopId: 'chitose',
              destination: '科技大',
            ),
          ],
        );

        final result = timetable.nextBus('honbuto', now: fixedNow);
        expect(result, isNull);
      });

      test('returns null when schedules is empty', () {
        const timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-12-31',
          schedules: [],
        );

        final result = timetable.nextBus('chitose', now: fixedNow);
        expect(result, isNull);
      });

      test('schedules追加順に関わらず時刻が最も近い未来のバスを返す', () {
        // schedules に 15:00, 13:00, 14:00 の順で格納されていても
        // 最も近い未来（13:00）が返るべき
        const timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-12-31',
          schedules: [
            BusEntry(
              time: '15:00',
              boardingStopId: 'chitose',
              destination: '科技大',
            ),
            BusEntry(
              time: '13:00',
              boardingStopId: 'chitose',
              destination: '科技大',
            ),
            BusEntry(
              time: '14:00',
              boardingStopId: 'chitose',
              destination: '科技大',
            ),
          ],
        );

        final result = timetable.nextBus('chitose', now: fixedNow);
        expect(result, isNotNull);
        expect(result!.time, '13:00');
      });

      test('複数系統が混在する場合、系統の追加順ではなく時刻順で最近のバスを返す', () {
        // バグ再現: 系統1(10:54)がschedules先頭、系統2(10:22)が後ろにある場合
        // 10:14時点で10:22が返るべき（10:54ではない）
        final now = DateTime(2024, 6, 17, 10, 14, 0); // 月曜日（平日）
        const timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-12-31',
          schedules: [
            BusEntry(
              time: '10:54',
              boardingStopId: 'kenkyuto',
              destination: '科技大',
              routeLabel: '空港経由',
            ),
            BusEntry(
              time: '10:22',
              boardingStopId: 'kenkyuto',
              destination: '科技大',
              routeLabel: '直通',
            ),
          ],
        );

        final result = timetable.nextBus('kenkyuto', now: now);
        expect(result, isNotNull);
        expect(result!.time, '10:22');
      });
    });

    group('todayBuses', () {
      test('returns only entries with specified direction', () {
        const timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-12-31',
          schedules: [
            BusEntry(
              time: '09:30',
              boardingStopId: 'chitose',
              destination: '科技大',
            ),
            BusEntry(
              time: '10:00',
              boardingStopId: 'minamiChitose',
              destination: '南千歳',
            ),
            BusEntry(
              time: '11:00',
              boardingStopId: 'chitose',
              destination: '科技大',
            ),
          ],
        );

        final result = timetable.todayBuses('chitose');
        expect(result.length, 2);
        expect(result.every((e) => e.boardingStopId == 'chitose'), isTrue);
      });

      test('returns empty list when no buses match direction', () {
        const timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-12-31',
          schedules: [
            BusEntry(
              time: '09:30',
              boardingStopId: 'chitose',
              destination: '科技大',
            ),
          ],
        );

        final result = timetable.todayBuses('honbuto');
        expect(result, isEmpty);
      });

      test('returns empty list when schedules is empty', () {
        const timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-12-31',
          schedules: [],
        );

        final result = timetable.todayBuses('chitose');
        expect(result, isEmpty);
      });

      test('土曜日: weekdayOnly の便は含まれず weekendOnly の便は含まれる', () {
        final saturday = DateTime(2024, 6, 15, 8, 0); // 土曜日
        const timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-12-31',
          schedules: [
            BusEntry(
              time: '09:00',
              boardingStopId: 'chitose',
              destination: '科技大',
              weekdayOnly: true,
            ),
            BusEntry(
              time: '10:00',
              boardingStopId: 'chitose',
              destination: '科技大',
              weekendOnly: true,
            ),
          ],
        );

        final result =
            timetable.todayBuses('chitose', now: saturday);
        expect(result.length, 1);
        expect(result.first.time, '10:00');
      });
    });

    group('busesFor', () {
      const timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-12-31',
        schedules: [
          BusEntry(
            time: '10:00',
            boardingStopId: 'chitose',
            destination: '科技大',
            weekendOnly: true,
          ),
          BusEntry(
            time: '09:00',
            boardingStopId: 'chitose',
            destination: '科技大',
            weekdayOnly: true,
          ),
          BusEntry(
            time: '11:00',
            boardingStopId: 'chitose',
            destination: '科技大',
          ),
          BusEntry(
            time: '08:00',
            boardingStopId: 'minamiChitose',
            destination: '南千歳',
          ),
        ],
      );

      test('平日ダイヤ: weekendOnly の便を除外し時刻順に返す', () {
        final result =
            timetable.busesFor('chitose', DayType.weekday, SeasonType.academic);
        expect(result.map((e) => e.time), ['09:00', '11:00']);
      });

      test('土日祝ダイヤ: weekdayOnly の便を除外し時刻順に返す', () {
        final result = timetable.busesFor(
            'chitose', DayType.weekendHoliday, SeasonType.academic);
        expect(result.map((e) => e.time), ['10:00', '11:00']);
      });

      test('指定方向の便のみ返す', () {
        final result = timetable.busesFor(
            'minamiChitose', DayType.weekday, SeasonType.academic);
        expect(result.length, 1);
        expect(result.first.boardingStopId, 'minamiChitose');
      });
    });
  });

  group('DayType', () {
    test('fromDate: 平日は weekday を返す', () {
      expect(DayType.fromDate(DateTime(2024, 6, 17)), DayType.weekday); // 月
      expect(DayType.fromDate(DateTime(2024, 6, 21)), DayType.weekday); // 金
    });

    test('fromDate: 土日は weekendHoliday を返す', () {
      expect(
          DayType.fromDate(DateTime(2024, 6, 15)), DayType.weekendHoliday); // 土
      expect(
          DayType.fromDate(DateTime(2024, 6, 16)), DayType.weekendHoliday); // 日
    });
  });
}
