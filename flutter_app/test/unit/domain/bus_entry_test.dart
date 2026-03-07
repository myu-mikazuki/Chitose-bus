import 'package:flutter_test/flutter_test.dart';
import 'package:chitose_bus/domain/entities/bus_schedule.dart';

void main() {
  // Fixed reference time for deterministic tests: 2024-06-15 12:00:00
  final fixedNow = DateTime(2024, 6, 15, 12, 0, 0);

  group('BusEntry', () {
    group('toDateTimeToday', () {
      test('returns DateTime with correct date and parsed time', () {
        const entry = BusEntry(
          time: '09:30',
          direction: BusDirection.fromChitose,
          destination: '千歳科技大',
        );
        final result = entry.toDateTimeToday(now: fixedNow);

        expect(result.year, 2024);
        expect(result.month, 6);
        expect(result.day, 15);
        expect(result.hour, 9);
        expect(result.minute, 30);
      });
    });

    group('minutesFromNow', () {
      test('returns positive value for future time', () {
        const entry = BusEntry(
          time: '13:00',
          direction: BusDirection.fromChitose,
          destination: '千歳科技大',
        );
        // fixedNow = 12:00, entry = 13:00 → +60 minutes
        expect(entry.minutesFromNow(now: fixedNow), equals(60));
      });

      test('returns negative value for past time', () {
        const entry = BusEntry(
          time: '11:00',
          direction: BusDirection.fromChitose,
          destination: '千歳科技大',
        );
        // fixedNow = 12:00, entry = 11:00 → -60 minutes
        expect(entry.minutesFromNow(now: fixedNow), equals(-60));
      });

      test('returns 0 for exact current time (boundary)', () {
        const entry = BusEntry(
          time: '12:00',
          direction: BusDirection.fromChitose,
          destination: '千歳科技大',
        );
        // fixedNow = 12:00:00, entry = 12:00 → 0 seconds diff → 0 minutes
        expect(entry.minutesFromNow(now: fixedNow), equals(0));
      });
    });
  });
}
