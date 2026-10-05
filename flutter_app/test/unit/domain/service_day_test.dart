import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';

/// 24 時台の便は、日付が変わった後も前日の運行日の便として扱う（#272）。
void main() {
  const lastBus = BusEntry(
    time: '24:10',
    boardingStopId: 'chitose',
    destination: '科技大',
    weekdayOnly: true,
  );
  const weekendBus = BusEntry(
    time: '07:00',
    boardingStopId: 'chitose',
    destination: '科技大',
    weekendOnly: true,
  );
  const timetable = BusTimetable(
    validFrom: '2024-01-01',
    validTo: '2024-12-31',
    schedules: [weekendBus, lastBus],
  );

  // 2024-06-14 は金曜、06-15 は土曜
  final friNight = DateTime(2024, 6, 14, 23, 50);
  final satAfterMidnight = DateTime(2024, 6, 15, 0, 5);
  final satAfterLast = DateTime(2024, 6, 15, 0, 30);

  group('ServiceCalendar.serviceDate', () {
    test('午前3時より前は前日、3時以降は当日', () {
      expect(ServiceCalendar.serviceDate(DateTime(2024, 6, 15, 2, 59)),
          DateTime(2024, 6, 14));
      expect(ServiceCalendar.serviceDate(DateTime(2024, 6, 15, 3, 0)),
          DateTime(2024, 6, 15));
    });

    test('月初・年初をまたぐ', () {
      expect(ServiceCalendar.serviceDate(DateTime(2024, 7, 1, 0, 10)),
          DateTime(2024, 6, 30));
      expect(ServiceCalendar.serviceDate(DateTime(2025, 1, 1, 0, 10)),
          DateTime(2024, 12, 31));
    });
  });

  group('24 時台の便', () {
    test('日付が変わる前後で発車までの分数が連続する', () {
      expect(lastBus.minutesFromNow(now: friNight), 20);
      expect(lastBus.minutesFromNow(now: satAfterMidnight), 5);
    });

    test('0 時を過ぎても終バスが NEXT に残る', () {
      expect(timetable.nextBus('chitose', now: satAfterMidnight), lastBus);
    });

    test('終バスが出た後は、翌日扱いにならず NEXT なし', () {
      expect(lastBus.minutesFromNow(now: satAfterLast), lessThan(0));
      expect(timetable.nextBus('chitose', now: satAfterLast), isNull);
    });

    test('曜日区分は運行日基準: 金曜の終バスは土曜 0 時過ぎでも平日ダイヤ', () {
      final buses = timetable.todayBuses('chitose', now: satAfterMidnight);
      expect(buses, [lastBus]);
    });

    test('3 時になると当日（土曜）のダイヤに切り替わる', () {
      final buses =
          timetable.todayBuses('chitose', now: DateTime(2024, 6, 15, 3, 0));
      expect(buses, [weekendBus]);
      expect(timetable.nextBus('chitose', now: DateTime(2024, 6, 15, 3, 0)),
          weekendBus);
    });

    test('土曜の終バス（24:10）は日曜 0 時過ぎでも土日ダイヤのまま', () {
      const satLast = BusEntry(
        time: '24:10',
        boardingStopId: 'chitose',
        destination: '科技大',
        weekendOnly: true,
      );
      const t = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-12-31',
        schedules: [satLast, lastBus],
      );
      expect(t.nextBus('chitose', now: DateTime(2024, 6, 16, 0, 5)), satLast);
    });

    test('年末年始の運休は運行日基準: 1/4 0 時過ぎは 1/3 の運休扱い', () {
      expect(timetable.nextBus('chitose', now: DateTime(2025, 1, 4, 0, 5)),
          isNull);
      expect(timetable.todayBuses('chitose', now: DateTime(2025, 1, 4, 0, 5)),
          isEmpty);
    });

    test('12/30 の終バスは 12/31 0 時過ぎでも運行する', () {
      expect(timetable.nextBus('chitose', now: DateTime(2024, 12, 31, 0, 5)),
          lastBus);
    });
  });
}
