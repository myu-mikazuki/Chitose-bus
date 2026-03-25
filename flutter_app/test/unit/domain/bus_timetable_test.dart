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
              direction: BusDirection.fromChitose,
              destination: '千歳科技大',
            ),
            BusEntry(
              time: '13:00', // future (after fixedNow 12:00)
              direction: BusDirection.fromChitose,
              destination: '千歳科技大',
            ),
          ],
        );

        final result = timetable.nextBus(BusDirection.fromChitose, now: fixedNow);
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
              direction: BusDirection.fromChitose,
              destination: '千歳科技大',
            ),
          ],
        );

        final result = timetable.nextBus(BusDirection.fromChitose, now: fixedNow);
        expect(result, isNull);
      });

      test('returns only buses with the specified direction', () {
        const timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-12-31',
          schedules: [
            BusEntry(
              time: '13:00',
              direction: BusDirection.fromMinamiChitose,
              destination: '南千歳',
            ),
            BusEntry(
              time: '13:00',
              direction: BusDirection.fromChitose,
              destination: '千歳科技大',
            ),
          ],
        );

        final result = timetable.nextBus(BusDirection.fromHonbuto, now: fixedNow);
        expect(result, isNull);
      });

      test('returns null when schedules is empty', () {
        const timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-12-31',
          schedules: [],
        );

        final result = timetable.nextBus(BusDirection.fromChitose, now: fixedNow);
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
              direction: BusDirection.fromChitose,
              destination: '科技大',
            ),
            BusEntry(
              time: '13:00',
              direction: BusDirection.fromChitose,
              destination: '科技大',
            ),
            BusEntry(
              time: '14:00',
              direction: BusDirection.fromChitose,
              destination: '科技大',
            ),
          ],
        );

        final result = timetable.nextBus(BusDirection.fromChitose, now: fixedNow);
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
              direction: BusDirection.fromKenkyutoToHonbuto,
              destination: '科技大',
              routeLabel: '空港経由',
            ),
            BusEntry(
              time: '10:22',
              direction: BusDirection.fromKenkyutoToHonbuto,
              destination: '科技大',
              routeLabel: '直通',
            ),
          ],
        );

        final result = timetable.nextBus(BusDirection.fromKenkyutoToHonbuto, now: now);
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
              direction: BusDirection.fromChitose,
              destination: '千歳科技大',
            ),
            BusEntry(
              time: '10:00',
              direction: BusDirection.fromMinamiChitose,
              destination: '南千歳',
            ),
            BusEntry(
              time: '11:00',
              direction: BusDirection.fromChitose,
              destination: '千歳科技大',
            ),
          ],
        );

        final result = timetable.todayBuses(BusDirection.fromChitose);
        expect(result.length, 2);
        expect(result.every((e) => e.direction == BusDirection.fromChitose), isTrue);
      });

      test('returns empty list when no buses match direction', () {
        const timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-12-31',
          schedules: [
            BusEntry(
              time: '09:30',
              direction: BusDirection.fromChitose,
              destination: '千歳科技大',
            ),
          ],
        );

        final result = timetable.todayBuses(BusDirection.fromHonbuto);
        expect(result, isEmpty);
      });

      test('returns empty list when schedules is empty', () {
        const timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-12-31',
          schedules: [],
        );

        final result = timetable.todayBuses(BusDirection.fromChitose);
        expect(result, isEmpty);
      });
    });
  });
}
