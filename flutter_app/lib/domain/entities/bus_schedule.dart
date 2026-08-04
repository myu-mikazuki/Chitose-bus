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

  static DayType fromDate(DateTime date) {
    final isWeekend = date.weekday == DateTime.saturday ||
        date.weekday == DateTime.sunday;
    return isWeekend ? DayType.weekendHoliday : DayType.weekday;
  }
}

/// 期別（授業期 / 学休期）
///
/// 大学の学休期間中、美々空港線は「学休期ダイヤ」で運行する。
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
