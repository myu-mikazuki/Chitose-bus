import 'package:flutter_test/flutter_test.dart';
import 'package:chitose_bus/data/services/local_notification_service.dart';
import 'package:chitose_bus/domain/entities/bus_schedule.dart';

void main() {
  group('LocalNotificationService.busNotificationId', () {
    test('同じ便は同じIDを返す', () {
      const bus = BusEntry(
        time: '08:30',
        direction: BusDirection.fromChitose,
        destination: '千歳駅',
      );
      final id1 = LocalNotificationService.busNotificationId(bus);
      final id2 = LocalNotificationService.busNotificationId(bus);
      expect(id1, equals(id2));
    });

    test('時刻が同じでも方面が異なれば異なるIDを返す', () {
      const busA = BusEntry(
        time: '08:30',
        direction: BusDirection.fromChitose,
        destination: '千歳駅',
      );
      const busB = BusEntry(
        time: '08:30',
        direction: BusDirection.fromHonbuto,
        destination: '本部棟',
      );
      expect(
        LocalNotificationService.busNotificationId(busA),
        isNot(equals(LocalNotificationService.busNotificationId(busB))),
      );
    });

    test('IDは非負の整数', () {
      const bus = BusEntry(
        time: '23:59',
        direction: BusDirection.fromMinamiChitose,
        destination: '南千歳駅',
      );
      final id = LocalNotificationService.busNotificationId(bus);
      expect(id, greaterThanOrEqualTo(0));
    });
  });
}
