import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';

void main() {
  // Fixed reference time for deterministic tests: 2024-06-15 12:00:00
  final fixedNow = DateTime(2024, 6, 15, 12, 0, 0);

  group('BusEntry', () {
    group('toDateTimeToday', () {
      test('returns DateTime with correct date and parsed time', () {
        const entry = BusEntry(
          time: '09:30',
          boardingStopId: 'chitose',
          destination: '科技大',
        );
        final result = entry.toDateTimeToday(now: fixedNow);

        expect(result.year, 2024);
        expect(result.month, 6);
        expect(result.day, 15);
        expect(result.hour, 9);
        expect(result.minute, 30);
      });
    });

    group('runsOn', () {
      test('weekdayOnly=true: 平日ダイヤでは運行、土日祝ダイヤでは運休', () {
        const entry = BusEntry(
          time: '09:30',
          boardingStopId: 'chitose',
          destination: '科技大',
          weekdayOnly: true,
        );
        expect(entry.runsOn(DayType.weekday, SeasonType.academic), isTrue);
        expect(entry.runsOn(DayType.weekendHoliday, SeasonType.academic), isFalse);
      });

      test('weekendOnly=true: 土日祝ダイヤでは運行、平日ダイヤでは運休', () {
        const entry = BusEntry(
          time: '09:30',
          boardingStopId: 'chitose',
          destination: '科技大',
          weekendOnly: true,
        );
        expect(entry.runsOn(DayType.weekday, SeasonType.academic), isFalse);
        expect(entry.runsOn(DayType.weekendHoliday, SeasonType.academic), isTrue);
      });

      test('フラグなし: どちらのダイヤでも運行', () {
        const entry = BusEntry(
          time: '09:30',
          boardingStopId: 'chitose',
          destination: '科技大',
        );
        expect(entry.runsOn(DayType.weekday, SeasonType.academic), isTrue);
        expect(entry.runsOn(DayType.weekendHoliday, SeasonType.academic), isTrue);
      });
    });

    group('isRunningToday', () {
      test('weekdayOnly=true: 土曜日は運休、月曜日は運行', () {
        const entry = BusEntry(
          time: '09:30',
          boardingStopId: 'chitose',
          destination: '科技大',
          weekdayOnly: true,
        );
        final saturday = DateTime(2024, 6, 15); // 土曜日
        final monday = DateTime(2024, 6, 17); // 月曜日
        expect(entry.isRunningToday(saturday), isFalse);
        expect(entry.isRunningToday(monday), isTrue);
      });

      test('weekendOnly=true: 月曜日は運休、日曜日は運行', () {
        const entry = BusEntry(
          time: '09:30',
          boardingStopId: 'chitose',
          destination: '科技大',
          weekendOnly: true,
        );
        final sunday = DateTime(2024, 6, 16); // 日曜日
        final monday = DateTime(2024, 6, 17); // 月曜日
        expect(entry.isRunningToday(monday), isFalse);
        expect(entry.isRunningToday(sunday), isTrue);
      });
    });

    group('minutesFromNow', () {
      test('returns positive value for future time', () {
        const entry = BusEntry(
          time: '13:00',
          boardingStopId: 'chitose',
          destination: '科技大',
        );
        // fixedNow = 12:00, entry = 13:00 → +60 minutes
        expect(entry.minutesFromNow(now: fixedNow), equals(60));
      });

      test('returns negative value for past time', () {
        const entry = BusEntry(
          time: '11:00',
          boardingStopId: 'chitose',
          destination: '科技大',
        );
        // fixedNow = 12:00, entry = 11:00 → -60 minutes
        expect(entry.minutesFromNow(now: fixedNow), equals(-60));
      });

      test('returns 0 for exact current time (boundary)', () {
        const entry = BusEntry(
          time: '12:00',
          boardingStopId: 'chitose',
          destination: '科技大',
        );
        // fixedNow = 12:00:00, entry = 12:00 → 0 seconds diff → 0 minutes
        expect(entry.minutesFromNow(now: fixedNow), equals(0));
      });
    });
  });
}
