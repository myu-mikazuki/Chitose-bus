import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';

void main() {
  group('SeasonType.fromDate', () {
    group('夏季学休期（8月第1月曜日 〜 9月第4金曜日）', () {
      // 2026年: 8/1=土 → 第1月曜日は 8/3
      //         9/1=火 → 第4金曜日は 9/25
      test('開始前日（2026-08-02 日）は授業期', () {
        expect(SeasonType.fromDate(DateTime(2026, 8, 2)), SeasonType.academic);
      });

      test('開始日（2026-08-03 月）は学休期', () {
        expect(SeasonType.fromDate(DateTime(2026, 8, 3)), SeasonType.vacation);
      });

      test('終了日（2026-09-25 金）は学休期', () {
        expect(SeasonType.fromDate(DateTime(2026, 9, 25)), SeasonType.vacation);
      });

      test('終了翌日（2026-09-26 土）は授業期', () {
        expect(SeasonType.fromDate(DateTime(2026, 9, 26)), SeasonType.academic);
      });

      test('別の年でも第1月曜日から開始する（2027-08-01 は日曜、開始は 8/2）', () {
        expect(SeasonType.fromDate(DateTime(2027, 8, 1)), SeasonType.academic);
        expect(SeasonType.fromDate(DateTime(2027, 8, 2)), SeasonType.vacation);
      });
    });

    group('冬季学休期（2月第1月曜日 〜 3月31日）', () {
      // 2026年: 2/1=日 → 第1月曜日は 2/2
      test('開始前日（2026-02-01 日）は授業期', () {
        expect(SeasonType.fromDate(DateTime(2026, 2, 1)), SeasonType.academic);
      });

      test('開始日（2026-02-02 月）は学休期', () {
        expect(SeasonType.fromDate(DateTime(2026, 2, 2)), SeasonType.vacation);
      });

      test('終了日（2026-03-31）は学休期', () {
        expect(SeasonType.fromDate(DateTime(2026, 3, 31)), SeasonType.vacation);
      });

      test('終了翌日（2026-04-01）は授業期', () {
        expect(SeasonType.fromDate(DateTime(2026, 4, 1)), SeasonType.academic);
      });
    });

    group('お盆（8/13 〜 8/16）', () {
      test('お盆期間は学休期', () {
        for (final day in [13, 14, 15, 16]) {
          expect(
            SeasonType.fromDate(DateTime(2026, 8, day)),
            SeasonType.vacation,
            reason: '8/$day',
          );
        }
      });
    });

    test('授業期の代表日（6月・11月）は授業期', () {
      expect(SeasonType.fromDate(DateTime(2026, 6, 17)), SeasonType.academic);
      expect(SeasonType.fromDate(DateTime(2026, 11, 4)), SeasonType.academic);
    });

    test('時刻成分があっても日付のみで判定される', () {
      expect(
        SeasonType.fromDate(DateTime(2026, 8, 3, 23, 59)),
        SeasonType.vacation,
      );
      expect(
        SeasonType.fromDate(DateTime(2026, 8, 2, 23, 59)),
        SeasonType.academic,
      );
    });
  });

  group('ServiceCalendar.isSuspended', () {
    test('年末年始（12/31 〜 1/3）は全便運休', () {
      expect(ServiceCalendar.isSuspended(DateTime(2025, 12, 31)), isTrue);
      expect(ServiceCalendar.isSuspended(DateTime(2026, 1, 1)), isTrue);
      expect(ServiceCalendar.isSuspended(DateTime(2026, 1, 2)), isTrue);
      expect(ServiceCalendar.isSuspended(DateTime(2026, 1, 3)), isTrue);
    });

    test('前後の日は運休しない', () {
      expect(ServiceCalendar.isSuspended(DateTime(2025, 12, 30)), isFalse);
      expect(ServiceCalendar.isSuspended(DateTime(2026, 1, 4)), isFalse);
    });
  });

  group('BusEntry 期別フラグ', () {
    BusEntry entry({bool academicOnly = false, bool vacationOnly = false}) =>
        BusEntry(
          time: '09:00',
          boardingStopId: 'chitose',
          destination: '科技大',
          academicOnly: academicOnly,
          vacationOnly: vacationOnly,
        );

    test('academicOnly=true: 授業期のみ運行', () {
      final e = entry(academicOnly: true);
      expect(e.runsOn(DayType.weekday, SeasonType.academic), isTrue);
      expect(e.runsOn(DayType.weekday, SeasonType.vacation), isFalse);
    });

    test('vacationOnly=true: 学休期のみ運行', () {
      final e = entry(vacationOnly: true);
      expect(e.runsOn(DayType.weekday, SeasonType.academic), isFalse);
      expect(e.runsOn(DayType.weekday, SeasonType.vacation), isTrue);
    });

    test('フラグなし: 両期で運行', () {
      final e = entry();
      expect(e.runsOn(DayType.weekday, SeasonType.academic), isTrue);
      expect(e.runsOn(DayType.weekday, SeasonType.vacation), isTrue);
    });

    test('運行日フラグと期別フラグは AND で効く', () {
      const e = BusEntry(
        time: '09:00',
        boardingStopId: 'chitose',
        destination: '科技大',
        weekdayOnly: true,
        vacationOnly: true,
      );
      expect(e.runsOn(DayType.weekday, SeasonType.vacation), isTrue);
      expect(e.runsOn(DayType.weekendHoliday, SeasonType.vacation), isFalse);
      expect(e.runsOn(DayType.weekday, SeasonType.academic), isFalse);
    });

    test('isRunningToday: 年末年始は期別に関わらず運休', () {
      expect(entry().isRunningToday(DateTime(2026, 1, 1, 9, 0)), isFalse);
      expect(entry().isRunningToday(DateTime(2026, 1, 4, 9, 0)), isTrue);
    });

    test('isRunningToday: 学休期の日は vacationOnly 便が運行する', () {
      // 2026-08-03（月）は夏季学休期の初日
      final day = DateTime(2026, 8, 3, 9, 0);
      expect(entry(vacationOnly: true).isRunningToday(day), isTrue);
      expect(entry(academicOnly: true).isRunningToday(day), isFalse);
    });
  });

  group('BusTimetable の期別絞り込み', () {
    final timetable = BusTimetable(
      validFrom: '2025-04-01',
      validTo: '2099-12-31',
      schedules: const [
        BusEntry(
          time: '07:14',
          boardingStopId: 'chitose',
          destination: '科技大',
          routeLabel: '直通',
          weekdayOnly: true,
          academicOnly: true,
        ),
        BusEntry(
          time: '08:10',
          boardingStopId: 'chitose',
          destination: '科技大',
          routeLabel: '直通',
          weekdayOnly: true,
          vacationOnly: true,
        ),
        BusEntry(
          time: '07:20',
          boardingStopId: 'chitose',
          destination: '科技大',
          routeLabel: '空港経由',
        ),
      ],
    );

    test('授業期の平日: 授業期便と共通便のみ', () {
      final result = timetable.busesFor(
        'chitose',
        DayType.weekday,
        SeasonType.academic,
      );
      expect(result.map((e) => e.time), ['07:14', '07:20']);
    });

    test('学休期の平日: 学休期便と共通便のみ', () {
      final result = timetable.busesFor(
        'chitose',
        DayType.weekday,
        SeasonType.vacation,
      );
      expect(result.map((e) => e.time), ['07:20', '08:10']);
    });

    test('学休期の土日祝: 直通便（平日限定）は消える', () {
      final result = timetable.busesFor(
        'chitose',
        DayType.weekendHoliday,
        SeasonType.vacation,
      );
      expect(result.map((e) => e.time), ['07:20']);
    });

    test('todayBuses: 年末年始は空リスト', () {
      final result = timetable.todayBuses(
        'chitose',
        now: DateTime(2026, 1, 1, 6, 0),
      );
      expect(result, isEmpty);
    });

    test('todayBuses: 学休期の平日は学休期ダイヤになる', () {
      final result = timetable.todayBuses(
        'chitose',
        now: DateTime(2026, 8, 3, 6, 0),
      );
      expect(result.map((e) => e.time), ['07:20', '08:10']);
    });

    test('nextBus: 学休期は授業期限定便を返さない', () {
      final next = timetable.nextBus(
        'chitose',
        now: DateTime(2026, 8, 3, 7, 0),
      );
      expect(next?.time, '07:20');
    });
  });
}
