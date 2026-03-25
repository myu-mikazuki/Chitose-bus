import 'package:flutter_test/flutter_test.dart';
import 'package:chitose_bus/domain/entities/notification_settings.dart';

void main() {
  group('NotificationSettings', () {
    test('デフォルト値: enabled=false, minutesBefore=10', () {
      final s = NotificationSettings();
      expect(s.enabled, isFalse);
      expect(s.minutesBefore, 10);
    });

    test('copyWith: enabled のみ変更', () {
      final s = NotificationSettings();
      final s2 = s.copyWith(enabled: true);
      expect(s2.enabled, isTrue);
      expect(s2.minutesBefore, 10);
    });

    test('copyWith: minutesBefore のみ変更', () {
      final s = NotificationSettings(enabled: true, minutesBefore: 10);
      final s2 = s.copyWith(minutesBefore: 5);
      expect(s2.minutesBefore, 5);
      expect(s2.enabled, isTrue);
    });

    test('minutesOptions に 5/10/15/30 が含まれる', () {
      expect(NotificationSettings.minutesOptions, containsAll([5, 10, 15, 30]));
    });

    test('== と hashCode: 同じ値は等しい', () {
      final a = NotificationSettings(enabled: true, minutesBefore: 5);
      final b = NotificationSettings(enabled: true, minutesBefore: 5);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    group('scheduledBusKeys', () {
      test('デフォルト値は空の Set', () {
        final s = NotificationSettings();
        expect(s.scheduledBusKeys, isEmpty);
      });

      test('copyWith: scheduledBusKeys を設定', () {
        final s = NotificationSettings();
        final s2 = s.copyWith(scheduledBusKeys: {'fromChitose_08:30', 'toChitose_09:00'});
        expect(s2.scheduledBusKeys, {'fromChitose_08:30', 'toChitose_09:00'});
        expect(s2.enabled, isFalse);
        expect(s2.minutesBefore, 10);
      });

      test('copyWith: scheduledBusKeys を省略すると元の値を保持', () {
        final s = NotificationSettings(scheduledBusKeys: {'fromChitose_08:30'});
        final s2 = s.copyWith(enabled: true);
        expect(s2.scheduledBusKeys, {'fromChitose_08:30'});
      });

      test('== と hashCode: scheduledBusKeys が等しければ等しい', () {
        final a = NotificationSettings(scheduledBusKeys: {'fromChitose_08:30'});
        final b = NotificationSettings(scheduledBusKeys: {'fromChitose_08:30'});
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('== : scheduledBusKeys が異なれば不等', () {
        final a = NotificationSettings(scheduledBusKeys: {'fromChitose_08:30'});
        final b = NotificationSettings(scheduledBusKeys: {'toChitose_09:00'});
        expect(a, isNot(equals(b)));
      });

      test('scheduledBusKeys は immutable（外部からの変更が例外を投げる）', () {
        final s = NotificationSettings(scheduledBusKeys: {'fromChitose_08:30'});
        expect(() => s.scheduledBusKeys.add('toChitose_09:00'), throwsUnsupportedError);
      });
    });
  });
}
