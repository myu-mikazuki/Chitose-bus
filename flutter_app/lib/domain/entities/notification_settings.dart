import 'bus_schedule.dart';

class NotificationSettings {
  const NotificationSettings({
    this.enabled = false,
    this.minutesBefore = 10,
    this.direction,
  });

  final bool enabled;
  final int minutesBefore;
  final BusDirection? direction;

  static const minutesOptions = [5, 10, 15, 30];

  NotificationSettings copyWith({
    bool? enabled,
    int? minutesBefore,
    BusDirection? direction,
    bool clearDirection = false,
  }) {
    return NotificationSettings(
      enabled: enabled ?? this.enabled,
      minutesBefore: minutesBefore ?? this.minutesBefore,
      direction: clearDirection ? null : (direction ?? this.direction),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationSettings &&
          enabled == other.enabled &&
          minutesBefore == other.minutesBefore &&
          direction == other.direction;

  @override
  int get hashCode => Object.hash(enabled, minutesBefore, direction);
}
