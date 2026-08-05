enum BusDirection {
  fromChitose,
  fromMinamiChitose,
  fromKenkyutoToHonbuto,
  fromKenkyutoToStation,
  fromHonbuto,
}

/// ダイヤ種別（平日 / 土日祝日）
enum DayType {
  weekday,
  weekendHoliday;

  /// 土日、および祝日は土日祝ダイヤ（Issue #158）。
  /// ただし [JapaneseHoliday.runsOnWeekdaySchedule] に該当する5日は
  /// 祝日でも平日ダイヤで運行する。
  static DayType fromDate(DateTime date) {
    final isWeekend = date.weekday == DateTime.saturday ||
        date.weekday == DateTime.sunday;
    if (isWeekend) return DayType.weekendHoliday;
    if (JapaneseHoliday.runsOnWeekdaySchedule(date)) return DayType.weekday;
    if (JapaneseHoliday.is_(date)) return DayType.weekendHoliday;
    return DayType.weekday;
  }
}

/// 日本の祝日判定（振替休日・国民の休日を含む）
///
/// 外部 API に依存すると通信失敗時に時刻表が出せなくなるため計算で求める。
/// 春分・秋分は天文学的な近似式を使う（2150年まで有効）。
///
/// GAS 側の `holidayNameOf` / `dayTypeForYmd` と同一のロジック。
/// 片方だけ変更すると v=1 と v=2 で結果が食い違うため、必ず両方を揃えること。
abstract final class JapaneseHoliday {
  /// 「祝日だが平日ダイヤで運行する」日（時刻表 PDF 注記より）
  ///
  /// > 以下の日付は、祝日ですが、平日ダイヤでの運行となりますので、ご留意ください。
  /// > 【対象日】 4/29・7/20・10/12・11/3・11/23
  ///
  /// 7/20（海の日）と 10/12（スポーツの日）はハッピーマンデーで日付が動くが、
  /// PDF が固定日で列挙しているためそれに従う。
  static bool runsOnWeekdaySchedule(DateTime date) {
    final md = date.month * 100 + date.day;
    return md == 429 || md == 720 || md == 1012 || md == 1103 || md == 1123;
  }

  /// 祝日かどうか。名前が不要な場合はこちらを使う。
  // ignore: non_constant_identifier_names
  static bool is_(DateTime date) => nameOf(date) != null;

  /// 祝日名を返す（祝日でなければ null）
  static String? nameOf(DateTime date) {
    final base = _fixedOrHappyMonday(date);
    if (base != null) return base;

    // 振替休日: 直前の日曜が祝日で、そこから連続して祝日が続く場合
    if (date.weekday != DateTime.sunday) {
      var prev = DateTime(date.year, date.month, date.day);
      while (true) {
        prev = prev.subtract(const Duration(days: 1));
        if (_fixedOrHappyMonday(prev) == null) break;
        if (prev.weekday == DateTime.sunday) return '振替休日';
      }
    }

    // 国民の休日: 前日と翌日がともに祝日で、自身は祝日でない平日
    if (date.weekday != DateTime.sunday && date.weekday != DateTime.saturday) {
      final before = DateTime(date.year, date.month, date.day - 1);
      final after = DateTime(date.year, date.month, date.day + 1);
      if (_fixedOrHappyMonday(before) != null &&
          _fixedOrHappyMonday(after) != null) {
        return '国民の休日';
      }
    }

    return null;
  }

  /// 固定日・ハッピーマンデー・春分秋分（振替休日と国民の休日は含まない）
  static String? _fixedOrHappyMonday(DateTime d) {
    final m = d.month, day = d.day;
    final isMonday = d.weekday == DateTime.monday;
    final nth = ((day - 1) ~/ 7) + 1;

    if (m == 1 && day == 1) return '元日';
    if (m == 1 && isMonday && nth == 2) return '成人の日';
    if (m == 2 && day == 11) return '建国記念の日';
    if (m == 2 && day == 23) return '天皇誕生日';
    if (m == 3 && day == _vernalEquinox(d.year)) return '春分の日';
    if (m == 4 && day == 29) return '昭和の日';
    if (m == 5 && day == 3) return '憲法記念日';
    if (m == 5 && day == 4) return 'みどりの日';
    if (m == 5 && day == 5) return 'こどもの日';
    if (m == 7 && isMonday && nth == 3) return '海の日';
    if (m == 8 && day == 11) return '山の日';
    if (m == 9 && isMonday && nth == 3) return '敬老の日';
    if (m == 9 && day == _autumnalEquinox(d.year)) return '秋分の日';
    if (m == 10 && isMonday && nth == 2) return 'スポーツの日';
    if (m == 11 && day == 3) return '文化の日';
    if (m == 11 && day == 23) return '勤労感謝の日';
    return null;
  }

  static int _vernalEquinox(int y) =>
      (20.8431 + 0.242194 * (y - 1980) - ((y - 1980) ~/ 4)).floor();

  static int _autumnalEquinox(int y) =>
      (23.2488 + 0.242194 * (y - 1980) - ((y - 1980) ~/ 4)).floor();
}

/// 期別（授業期 / 学休期）
///
/// 公立千歳科学技術大学の学休期間中、美々空港線は「学休期ダイヤ」で運行する。
/// 学休期ダイヤの適用は美々空港線に限られる（時刻表 PDF 注記より）。
enum SeasonType {
  academic,
  vacation;

  /// 学休期の対象期間（時刻表 PDF 注記より）
  /// - 夏季: 8月第1月曜日 〜 9月第4週金曜日
  /// - 冬季: 2月第1月曜日 〜 3月31日
  /// - お盆: 8/13 〜 8/16
  ///
  /// 「9月第4週金曜日」は第4金曜日として解釈している。9月1日が土曜日の年のみ
  /// 両解釈が1週ずれるが、それ以外の年では一致する。
  static SeasonType fromDate(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);

    // お盆（夏季学休期に内包されるが、PDF に明記されているため独立して判定する）
    if (day.month == DateTime.august && day.day >= 13 && day.day <= 16) {
      return SeasonType.vacation;
    }

    // 夏季: 8月第1月曜日 〜 9月第4金曜日
    final summerFrom = _nthWeekday(day.year, DateTime.august, DateTime.monday, 1);
    final summerTo = _nthWeekday(day.year, DateTime.september, DateTime.friday, 4);
    if (!day.isBefore(summerFrom) && !day.isAfter(summerTo)) {
      return SeasonType.vacation;
    }

    // 冬季: 2月第1月曜日 〜 3月31日
    final winterFrom =
        _nthWeekday(day.year, DateTime.february, DateTime.monday, 1);
    final winterTo = DateTime(day.year, DateTime.march, 31);
    if (!day.isBefore(winterFrom) && !day.isAfter(winterTo)) {
      return SeasonType.vacation;
    }

    return SeasonType.academic;
  }

  /// year年month月の第n【weekday】曜日（n は 1 始まり）
  static DateTime _nthWeekday(int year, int month, int weekday, int n) {
    final first = DateTime(year, month, 1);
    final offset = (weekday - first.weekday + 7) % 7;
    return DateTime(year, month, 1 + offset + (n - 1) * 7);
  }
}

/// 運行カレンダー上の特例日
abstract final class ServiceCalendar {
  /// 年末年始（12/31 〜 1/3）は全便運休
  static bool isSuspended(DateTime date) =>
      (date.month == DateTime.december && date.day == 31) ||
      (date.month == DateTime.january && date.day <= 3);
}

class BusEntry {
  const BusEntry({
    required this.time,
    required this.direction,
    required this.destination,
    this.arrivals = const {},
    this.routeLabel,
    this.platformNumber,
    this.weekdayOnly = false,
    this.weekendOnly = false,
    this.academicOnly = false,
    this.vacationOnly = false,
  });

  final String time; // "HH:MM"
  final BusDirection direction;
  final String destination;
  final Map<String, String> arrivals;
  final String? routeLabel;
  final String? platformNumber;
  final bool weekdayOnly;
  final bool weekendOnly;

  /// 授業期のみ運行（学休期は運休）
  final bool academicOnly;

  /// 学休期のみ運行（授業期は運休）
  final bool vacationOnly;

  bool runsOn(DayType dayType, SeasonType season) {
    if (dayType == DayType.weekendHoliday && weekdayOnly) return false;
    if (dayType == DayType.weekday && weekendOnly) return false;
    if (season == SeasonType.vacation && academicOnly) return false;
    if (season == SeasonType.academic && vacationOnly) return false;
    return true;
  }

  bool isRunningToday(DateTime now) =>
      !ServiceCalendar.isSuspended(now) &&
      runsOn(DayType.fromDate(now), SeasonType.fromDate(now));

  DateTime toDateTimeToday({DateTime? now}) {
    final base = now ?? DateTime.now();
    final parts = time.split(':');
    return DateTime(
      base.year,
      base.month,
      base.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  int minutesFromNow({DateTime? now}) {
    final base = now ?? DateTime.now();
    final diff = toDateTimeToday(now: base).difference(base);
    return diff.inMinutes;
  }
}

class BusTimetable {
  const BusTimetable({
    required this.validFrom,
    required this.validTo,
    required this.schedules,
    this.pdfUrl = '',
  });

  final String validFrom;
  final String validTo;
  final List<BusEntry> schedules;
  final String pdfUrl;

  BusEntry? nextBus(BusDirection direction, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final candidates = schedules
        .where((e) =>
            e.direction == direction &&
            e.isRunningToday(current) &&
            e.toDateTimeToday(now: current).isAfter(current))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    return candidates.firstOrNull;
  }

  List<BusEntry> todayBuses(BusDirection direction, {DateTime? now}) {
    final current = now ?? DateTime.now();
    if (ServiceCalendar.isSuspended(current)) return const [];
    return busesFor(
      direction,
      DayType.fromDate(current),
      SeasonType.fromDate(current),
    );
  }

  List<BusEntry> busesFor(
    BusDirection direction,
    DayType dayType,
    SeasonType season,
  ) {
    final filtered = schedules
        .where((e) => e.direction == direction && e.runsOn(dayType, season))
        .toList();
    filtered.sort((a, b) => a.time.compareTo(b.time));
    return filtered;
  }
}

class ScheduleResponse {
  const ScheduleResponse({
    required this.updatedAt,
    required this.current,
    this.upcoming,
  });

  final String updatedAt;
  final BusTimetable current;
  final BusTimetable? upcoming;
}
