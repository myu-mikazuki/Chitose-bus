import 'bus_schedule.dart';

enum LecturePeriod {
  period1,
  period2,
  lunchBreak,
  period3,
  period4,
  period5,
  afterSchool,
}

extension LecturePeriodLabel on LecturePeriod {
  String get label => switch (this) {
        LecturePeriod.period1 => '1講',
        LecturePeriod.period2 => '2講',
        LecturePeriod.lunchBreak => '昼休み',
        LecturePeriod.period3 => '3講',
        LecturePeriod.period4 => '4講',
        LecturePeriod.period5 => '5講',
        LecturePeriod.afterSchool => '放課後',
      };
}

class LecturePeriodCalculator {
  /// 到着時刻文字列（"HH:MM"）から間に合う最初の講時を返す。
  /// null または空文字の場合は null を返す。
  static LecturePeriod? fromArrivalTime(String? time) {
    if (time == null || time.isEmpty) return null;
    final parts = time.split(':');
    final total = int.parse(parts[0]) * 60 + int.parse(parts[1]);
    if (total < 9 * 60) return LecturePeriod.period1;
    if (total < 10 * 60 + 45) return LecturePeriod.period2;
    if (total < 12 * 60 + 15) return LecturePeriod.lunchBreak;
    if (total < 13 * 60 + 15) return LecturePeriod.period3;
    if (total < 15 * 60) return LecturePeriod.period4;
    if (total < 16 * 60 + 45) return LecturePeriod.period5;
    return LecturePeriod.afterSchool;
  }

  /// バスエントリから間に合う講時を返す。
  /// arrivals に 'honbuto' キーがない方向（帰り路線等）は null を返す。
  static LecturePeriod? forBus(BusEntry bus) =>
      fromArrivalTime(bus.arrivals['honbuto']);
}
