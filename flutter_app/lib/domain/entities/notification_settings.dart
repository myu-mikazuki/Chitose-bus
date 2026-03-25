import 'bus_schedule.dart';

class NotificationSettings {
  NotificationSettings({
    this.enabled = false,
    this.minutesBefore = 10,
    this.direction,
    Set<String>? scheduledBusKeys,
  }) : scheduledBusKeys = scheduledBusKeys ?? {};

  final bool enabled;
  final int minutesBefore;
  final BusDirection? direction;
  final Set<String> scheduledBusKeys;

  static const minutesOptions = [5, 10, 15, 30];

  NotificationSettings copyWith({
    bool? enabled,
    int? minutesBefore,
    BusDirection? direction,
    bool clearDirection = false,
    Set<String>? scheduledBusKeys,
  }) {
    return NotificationSettings(
      enabled: enabled ?? this.enabled,
      minutesBefore: minutesBefore ?? this.minutesBefore,
      direction: clearDirection ? null : (direction ?? this.direction),
      scheduledBusKeys: scheduledBusKeys ?? this.scheduledBusKeys,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationSettings &&
          enabled == other.enabled &&
          minutesBefore == other.minutesBefore &&
          direction == other.direction &&
          _setEquals(scheduledBusKeys, other.scheduledBusKeys);

  static bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  int get hashCode => Object.hash(
        enabled,
        minutesBefore,
        direction,
        Object.hashAllUnordered(scheduledBusKeys),
      );
}
