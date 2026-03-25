class NotificationSettings {
  NotificationSettings({
    this.enabled = false,
    this.minutesBefore = 10,
    Set<String>? scheduledBusKeys,
  }) : scheduledBusKeys = Set.unmodifiable(scheduledBusKeys ?? {});

  final bool enabled;
  final int minutesBefore;
  final Set<String> scheduledBusKeys;

  static const minutesOptions = [5, 10, 15, 30];

  NotificationSettings copyWith({
    bool? enabled,
    int? minutesBefore,
    Set<String>? scheduledBusKeys,
  }) {
    return NotificationSettings(
      enabled: enabled ?? this.enabled,
      minutesBefore: minutesBefore ?? this.minutesBefore,
      scheduledBusKeys: scheduledBusKeys ?? this.scheduledBusKeys,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationSettings &&
          enabled == other.enabled &&
          minutesBefore == other.minutesBefore &&
          _setEquals(scheduledBusKeys, other.scheduledBusKeys);

  static bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  int get hashCode => Object.hash(
        enabled,
        minutesBefore,
        Object.hashAllUnordered(scheduledBusKeys),
      );
}
