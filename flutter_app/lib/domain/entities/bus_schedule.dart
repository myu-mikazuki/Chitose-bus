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
  });

  final String time; // "HH:MM"
  final BusDirection direction;
  final String destination;
  final Map<String, String> arrivals;

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
    return schedules
        .where((e) => e.direction == direction && e.toDateTimeToday(now: current).isAfter(current))
        .firstOrNull;
  }

  List<BusEntry> todayBuses(BusDirection direction) {
    return schedules.where((e) => e.direction == direction).toList();
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
