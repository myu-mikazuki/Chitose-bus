import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';

void main() {
  group('JapaneseHoliday.nameOf', () {
    test('固定日の祝日', () {
      expect(JapaneseHoliday.nameOf(DateTime(2026, 1, 1)), '元日');
      expect(JapaneseHoliday.nameOf(DateTime(2026, 2, 11)), '建国記念の日');
      expect(JapaneseHoliday.nameOf(DateTime(2026, 2, 23)), '天皇誕生日');
      expect(JapaneseHoliday.nameOf(DateTime(2026, 4, 29)), '昭和の日');
      expect(JapaneseHoliday.nameOf(DateTime(2026, 5, 3)), '憲法記念日');
      expect(JapaneseHoliday.nameOf(DateTime(2026, 5, 4)), 'みどりの日');
      expect(JapaneseHoliday.nameOf(DateTime(2026, 5, 5)), 'こどもの日');
      expect(JapaneseHoliday.nameOf(DateTime(2026, 8, 11)), '山の日');
      expect(JapaneseHoliday.nameOf(DateTime(2026, 11, 3)), '文化の日');
      expect(JapaneseHoliday.nameOf(DateTime(2026, 11, 23)), '勤労感謝の日');
    });

    test('ハッピーマンデー', () {
      // 2026年: 成人の日 1/12、海の日 7/20、敬老の日 9/21、スポーツの日 10/12
      expect(JapaneseHoliday.nameOf(DateTime(2026, 1, 12)), '成人の日');
      expect(JapaneseHoliday.nameOf(DateTime(2026, 7, 20)), '海の日');
      expect(JapaneseHoliday.nameOf(DateTime(2026, 9, 21)), '敬老の日');
      expect(JapaneseHoliday.nameOf(DateTime(2026, 10, 12)), 'スポーツの日');
      // 前後の月曜は祝日でない
      expect(JapaneseHoliday.nameOf(DateTime(2026, 1, 5)), isNull);
      expect(JapaneseHoliday.nameOf(DateTime(2026, 1, 19)), isNull);
    });

    test('春分・秋分', () {
      expect(JapaneseHoliday.nameOf(DateTime(2026, 3, 20)), '春分の日');
      expect(JapaneseHoliday.nameOf(DateTime(2026, 9, 23)), '秋分の日');
      expect(JapaneseHoliday.nameOf(DateTime(2025, 3, 20)), '春分の日');
      expect(JapaneseHoliday.nameOf(DateTime(2027, 3, 21)), '春分の日');
    });

    test('国民の休日（前後を祝日に挟まれた平日）', () {
      // 2026年: 9/21 敬老の日・9/23 秋分の日 に挟まれた 9/22（火）
      expect(JapaneseHoliday.nameOf(DateTime(2026, 9, 22)), '国民の休日');
    });

    test('振替休日（日曜が祝日の場合の翌月曜）', () {
      // 2027-08-11 は水曜なので振替なし。日曜祝日の年で確認する。
      // 2026-11-03 は火曜。2032-11-03 は水曜。
      // 日曜が祝日 → 翌月曜が振替休日になるケース: 2027-05-02(日) みどりの日? を避け、
      // 確実な例として 2026-05-03(日) 憲法記念日 → 2026-05-06(水) ではなく
      // 5/4・5/5 も祝日のため連続し、振替は 5/6(水)。
      expect(DateTime(2026, 5, 3).weekday, DateTime.sunday);
      expect(JapaneseHoliday.nameOf(DateTime(2026, 5, 6)), '振替休日');
    });

    test('祝日でない日は null', () {
      expect(JapaneseHoliday.nameOf(DateTime(2026, 8, 5)), isNull);
      expect(JapaneseHoliday.nameOf(DateTime(2026, 6, 17)), isNull);
      expect(JapaneseHoliday.nameOf(DateTime(2026, 8, 12)), isNull);
    });
  });

  group('DayType.fromDate（祝日対応・Issue #158）', () {
    test('平日は weekday', () {
      expect(DayType.fromDate(DateTime(2026, 8, 5)), DayType.weekday); // 水
      expect(DayType.fromDate(DateTime(2026, 6, 17)), DayType.weekday); // 水
    });

    test('土日は weekendHoliday', () {
      expect(DayType.fromDate(DateTime(2026, 8, 8)), DayType.weekendHoliday);
      expect(DayType.fromDate(DateTime(2026, 8, 9)), DayType.weekendHoliday);
    });

    test('平日に当たる祝日は weekendHoliday', () {
      // 8/11 山の日（火）
      expect(DayType.fromDate(DateTime(2026, 8, 11)), DayType.weekendHoliday);
      // 9/22 国民の休日（火）
      expect(DayType.fromDate(DateTime(2026, 9, 22)), DayType.weekendHoliday);
    });

    test('「祝日だが平日ダイヤ」の5日は weekday', () {
      // 時刻表 PDF の注記: 4/29・7/20・10/12・11/3・11/23
      for (final d in [
        DateTime(2026, 4, 29),
        DateTime(2026, 7, 20),
        DateTime(2026, 10, 12),
        DateTime(2026, 11, 3),
        DateTime(2026, 11, 23),
      ]) {
        expect(
          DayType.fromDate(d),
          DayType.weekday,
          reason: '${d.month}/${d.day} は祝日だが平日ダイヤ',
        );
      }
    });

    test('土日に当たる「平日ダイヤ」指定日は土日が優先される', () {
      // 2026-11-23 は月曜だが、土日に当たる年では土日祝ダイヤになるべき
      // 2025-11-23 は日曜
      expect(DateTime(2025, 11, 23).weekday, DateTime.sunday);
      expect(DayType.fromDate(DateTime(2025, 11, 23)), DayType.weekendHoliday);
    });
  });

  group('祝日の時刻表への反映', () {
    final timetable = BusTimetable(
      validFrom: '2025-04-01',
      validTo: '2099-12-31',
      schedules: const [
        BusEntry(
          time: '08:10',
          direction: BusDirection.fromChitose,
          destination: '科技大',
          routeLabel: '直通',
          weekdayOnly: true,
          vacationOnly: true,
        ),
        BusEntry(
          time: '08:18',
          direction: BusDirection.fromChitose,
          destination: '科技大',
          routeLabel: '空港経由',
          weekendOnly: true,
        ),
        BusEntry(
          time: '07:20',
          direction: BusDirection.fromChitose,
          destination: '科技大',
          routeLabel: '空港経由',
        ),
      ],
    );

    test('8/11（山の日・学休期）は直通便が出ない', () {
      final buses = timetable.todayBuses(
        BusDirection.fromChitose,
        now: DateTime(2026, 8, 11, 5, 0),
      );
      expect(buses.map((e) => e.time), ['07:20', '08:18']);
      expect(buses.any((e) => e.routeLabel == '直通'), isFalse);
    });

    test('8/12（平日・学休期）は直通便が出る', () {
      final buses = timetable.todayBuses(
        BusDirection.fromChitose,
        now: DateTime(2026, 8, 12, 5, 0),
      );
      expect(buses.map((e) => e.time), ['07:20', '08:10']);
    });
  });
}
