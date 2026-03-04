enum BusDirection { toStation, toUniversity }

class BusEntry {
  const BusEntry({
    required this.time,
    required this.direction,
    required this.destination,
  });

  final String time; // "HH:MM"
  final BusDirection direction;
  final String destination;

  DateTime toDateTimeToday() {
    final now = DateTime.now();
    final parts = time.split(':');
    return DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
  }

  int minutesFromNow() {
    final diff = toDateTimeToday().difference(DateTime.now());
    return diff.inMinutes;
  }
}

class BusTimetable {
  const BusTimetable({
    required this.validFrom,
    required this.validTo,
    required this.schedules,
  });

  final String validFrom;
  final String validTo;
  final List<BusEntry> schedules;

  BusEntry? nextBus(BusDirection direction) {
    final now = DateTime.now();
    return schedules
        .where((e) => e.direction == direction && e.toDateTimeToday().isAfter(now))
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
