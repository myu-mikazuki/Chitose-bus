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

/// 便の行き先。GAS の `destination` がこの2つだけであることは
/// scripts/check_gas_response.js が検査している。
///
/// 表記が変わると、これで絞っている画面が**黙って空になる**。
/// リテラルを散らさず、変更箇所を1つに保つためここに置く。
abstract final class BusDestination {
  /// 科技大（研究棟・本部棟）方面
  static const campus = '科技大';

  /// 千歳駅方面
  static const station = '千歳駅';
}

/// ある停留所から乗る場合の1便。
///
/// 便そのものではなく「どこから乗るか」を決めたあとの見え方を表す。
/// 同じ便でも乗車地が違えば別の BusEntry になる（時刻も到着地も変わる）。
class BusEntry {
  const BusEntry({
    required this.time,
    required this.boardingStopId,
    required this.destination,
    this.terminusStopId,
    this.arrivals = const {},
    this.routeLabel,
    this.platformNumber,
    this.weekdayOnly = false,
    this.weekendOnly = false,
    this.academicOnly = false,
    this.vacationOnly = false,
  });

  final String time; // "HH:MM" 乗車地を出る時刻
  final String boardingStopId;
  final String destination;

  /// 終点（一般に降りられる最後の停留所）の ID。GAS が絞り込みの前に決めて返す。
  ///
  /// [arrivals] の末尾から導いてはいけない。arrivals は選んだ停留所だけに
  /// 絞られているため、イオン千歳店前を足すと長都行きの終点がそこになる。
  /// 供給元が古くて分からないときは null（#177）。
  final String? terminusStopId;

  final Map<String, String> arrivals;
  final String? routeLabel;
  final String? platformNumber;
  final bool weekdayOnly;
  final bool weekendOnly;

  /// 授業期のみ運行（学休期は運休）
  final bool academicOnly;

  /// 学休期のみ運行（授業期は運休）
  final bool vacationOnly;

  /// 通知の識別に使うキー。**形式を変えないこと。**
  ///
  /// SharedPreferences に保存され、OS に予約した通知の ID の元にもなる。
  /// 変えると既存の予約が引き当てられなくなり、キャンセルできない通知が残る。
  ///
  /// #177 以前は `BusDirection` の名前を使っていたため、その5通りは同じ文字列に
  /// なるようにしてある。新しい停留所は該当が無いので `<乗車地>_<行き先>` を使う。
  ///
  /// TODO(#190): 系統が入っておらず同時刻の便で衝突する。形式を統一する際に
  /// 保存済みキーの移行も要る。
  String get notificationKey {
    final legacy = switch ((boardingStopId, destination)) {
      // 旧 BusDirection の enum 名（.name）。JSON の文字列ではない
      ('chitose', BusDestination.campus) => 'fromChitose',
      ('minamiChitose', BusDestination.campus) => 'fromMinamiChitose',
      ('kenkyuto', BusDestination.campus) => 'fromKenkyutoToHonbuto',
      ('kenkyuto', BusDestination.station) => 'fromKenkyutoToStation',
      ('honbuto', BusDestination.station) => 'fromHonbuto',
      _ => null,
    };
    return '${legacy ?? '${boardingStopId}_$destination'}_$time';
  }

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

  BusEntry? nextBus(String stopId, {String? destination, DateTime? now}) {
    final current = now ?? DateTime.now();
    final candidates = schedules
        .where((e) =>
            e.boardingStopId == stopId &&
            (destination == null || e.destination == destination) &&
            e.isRunningToday(current) &&
            e.toDateTimeToday(now: current).isAfter(current))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    return candidates.firstOrNull;
  }

  List<BusEntry> todayBuses(String stopId,
      {String? destination, DateTime? now}) {
    final current = now ?? DateTime.now();
    if (ServiceCalendar.isSuspended(current)) return const [];
    return busesFor(
      stopId,
      DayType.fromDate(current),
      SeasonType.fromDate(current),
      destination: destination,
    );
  }

  /// [stopId] から乗る便。
  ///
  /// [destination] を指定すると行き先で絞る。途中の停留所は上下両方向のバスが
  /// 通るため、画面に出すときは指定しないと逆方向の便が混ざる。
  List<BusEntry> busesFor(
    String stopId,
    DayType dayType,
    SeasonType season, {
    String? destination,
  }) {
    final filtered = schedules
        .where((e) =>
            e.boardingStopId == stopId &&
            (destination == null || e.destination == destination) &&
            e.runsOn(dayType, season))
        .toList();
    filtered.sort((a, b) => a.time.compareTo(b.time));
    return filtered;
  }
}

/// 路線上の停留所。表示名の供給元は GAS の `stopMaster` のみ（Issue #177）。
///
/// アプリ側に名前の対応表を持つと、停留所が増えるたびにリリースが必要になる。
class BusStop {
  const BusStop({
    required this.id,
    required this.label,
    this.shortLabel,
    this.boardable = true,
  });

  final String id;

  /// 正式名（バス停の表記）
  final String label;

  /// タブなど幅の狭い場所で使う短縮名。正式名と同じなら GAS は返さない
  final String? shortLabel;

  /// 表示に使う名前
  String get displayLabel => shortLabel ?? label;

  /// 乗車地として選べるか。
  /// ラピダス前は工場敷地内で一般利用できないため false。
  final bool boardable;
}

/// `stopMaster` から停留所を引く。
///
/// #177 でアプリ側のハードコードされた対応表を消したため、ID からラベルを
/// 引く必要が画面のあちこちに出てくる。同じ `where(...).firstOrNull` を
/// 書き散らさないようここへ寄せる。
extension BusStopLookup on List<BusStop> {
  /// [id] の停留所。stopMaster に無ければ null（GAS から消えた停留所）
  BusStop? byId(String id) => where((s) => s.id == id).firstOrNull;

  /// [id] の表示名。**引けなければ ID をそのまま返す。**
  ///
  /// null を返して呼び出し側で埋めさせると、対応表を持っていた頃と同じ
  /// `null 着` を作り込むことになる。
  String labelOf(String id) => byId(id)?.displayLabel ?? id;
}

class ScheduleResponse {
  const ScheduleResponse({
    required this.updatedAt,
    required this.current,
    this.stopMaster = const [],
    this.upcoming,
  });

  final String updatedAt;
  final List<BusStop> stopMaster;
  final BusTimetable current;
  final BusTimetable? upcoming;
}
