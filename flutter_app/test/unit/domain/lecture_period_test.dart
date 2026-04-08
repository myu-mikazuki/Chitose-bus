import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';
import 'package:kagi_bus/domain/entities/lecture_period.dart';

void main() {
  group('LecturePeriodCalculator.fromArrivalTime', () {
    test('null → null', () {
      expect(LecturePeriodCalculator.fromArrivalTime(null), isNull);
    });

    test('空文字 → null', () {
      expect(LecturePeriodCalculator.fromArrivalTime(''), isNull);
    });

    test('":" を含まない不正フォーマット → null（クラッシュしない）', () {
      expect(LecturePeriodCalculator.fromArrivalTime('0900'), isNull);
    });

    test('08:59 → period1 (1講)', () {
      expect(
        LecturePeriodCalculator.fromArrivalTime('08:59'),
        LecturePeriod.period1,
      );
    });

    test('09:00 → period2 (2講)（1講の開始時刻ちょうどは間に合わない）', () {
      expect(
        LecturePeriodCalculator.fromArrivalTime('09:00'),
        LecturePeriod.period2,
      );
    });

    test('10:44 → period2 (2講)', () {
      expect(
        LecturePeriodCalculator.fromArrivalTime('10:44'),
        LecturePeriod.period2,
      );
    });

    test('10:45 → lunchBreak (昼休み)', () {
      expect(
        LecturePeriodCalculator.fromArrivalTime('10:45'),
        LecturePeriod.lunchBreak,
      );
    });

    test('12:14 → lunchBreak (昼休み)', () {
      expect(
        LecturePeriodCalculator.fromArrivalTime('12:14'),
        LecturePeriod.lunchBreak,
      );
    });

    test('12:15 → period3 (3講)', () {
      expect(
        LecturePeriodCalculator.fromArrivalTime('12:15'),
        LecturePeriod.period3,
      );
    });

    test('13:14 → period3 (3講)', () {
      expect(
        LecturePeriodCalculator.fromArrivalTime('13:14'),
        LecturePeriod.period3,
      );
    });

    test('13:15 → period4 (4講)', () {
      expect(
        LecturePeriodCalculator.fromArrivalTime('13:15'),
        LecturePeriod.period4,
      );
    });

    test('14:59 → period4 (4講)', () {
      expect(
        LecturePeriodCalculator.fromArrivalTime('14:59'),
        LecturePeriod.period4,
      );
    });

    test('15:00 → period5 (5講)', () {
      expect(
        LecturePeriodCalculator.fromArrivalTime('15:00'),
        LecturePeriod.period5,
      );
    });

    test('16:44 → period5 (5講)', () {
      expect(
        LecturePeriodCalculator.fromArrivalTime('16:44'),
        LecturePeriod.period5,
      );
    });

    test('16:45 → afterSchool (放課後)', () {
      expect(
        LecturePeriodCalculator.fromArrivalTime('16:45'),
        LecturePeriod.afterSchool,
      );
    });

    test('23:59 → afterSchool (放課後)', () {
      expect(
        LecturePeriodCalculator.fromArrivalTime('23:59'),
        LecturePeriod.afterSchool,
      );
    });
  });

  group('LecturePeriodCalculator.forBus', () {
    test('arrivals に honbuto あり → 対応する講時を返す', () {
      final bus = BusEntry(
        time: '08:30',
        direction: BusDirection.fromChitose,
        destination: '本部棟',
        arrivals: const {'honbuto': '08:59'},
      );
      expect(LecturePeriodCalculator.forBus(bus), LecturePeriod.period1);
    });

    test('arrivals に honbuto なし → null', () {
      final bus = BusEntry(
        time: '08:30',
        direction: BusDirection.fromKenkyutoToStation,
        destination: '千歳駅',
        arrivals: const {'chitose': '09:00'},
      );
      expect(LecturePeriodCalculator.forBus(bus), isNull);
    });

    test('arrivals が空 → null', () {
      final bus = BusEntry(
        time: '08:30',
        direction: BusDirection.fromChitose,
        destination: '本部棟',
      );
      expect(LecturePeriodCalculator.forBus(bus), isNull);
    });
  });

  group('LecturePeriod.label', () {
    test('period1.label → "1講"', () {
      expect(LecturePeriod.period1.label, '1講');
    });

    test('period2.label → "2講"', () {
      expect(LecturePeriod.period2.label, '2講');
    });

    test('lunchBreak.label → "昼休み"', () {
      expect(LecturePeriod.lunchBreak.label, '昼休み');
    });

    test('period3.label → "3講"', () {
      expect(LecturePeriod.period3.label, '3講');
    });

    test('period4.label → "4講"', () {
      expect(LecturePeriod.period4.label, '4講');
    });

    test('period5.label → "5講"', () {
      expect(LecturePeriod.period5.label, '5講');
    });

    test('afterSchool.label → "放課後"', () {
      expect(LecturePeriod.afterSchool.label, '放課後');
    });
  });
}
