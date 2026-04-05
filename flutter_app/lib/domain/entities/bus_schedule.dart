enum BusDirection {
  fromChitose,
  fromMinamiChitose,
  fromKenkyutoToHonbuto,
  fromKenkyutoToStation,
  fromHonbuto,
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
  });

  final String time; // "HH:MM"
  final BusDirection direction;
  final String destination;
  final Map<String, String> arrivals;
  final String? routeLabel;
  final String? platformNumber;
  final bool weekdayOnly;
  final bool weekendOnly;

  bool isRunningToday(DateTime now) {
    final weekday = now.weekday;
    final isWeekend = weekday == DateTime.saturday || weekday == DateTime.sunday;
    if (isWeekend && weekdayOnly) return false;
    if (!isWeekend && weekendOnly) return false;
    return true;
  }

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
    final filtered = schedules
        .where((e) => e.direction == direction && e.isRunningToday(current))
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
    this.isFromCache = false,
  });

  final String updatedAt;
  final BusTimetable current;
  final BusTimetable? upcoming;
  final bool isFromCache;

  ScheduleResponse withIsFromCache(bool value) => ScheduleResponse(
        updatedAt: updatedAt,
        current: current,
        upcoming: upcoming,
        isFromCache: value,
      );
}
