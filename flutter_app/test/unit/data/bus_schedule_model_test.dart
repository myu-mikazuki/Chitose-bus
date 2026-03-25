import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/data/models/bus_schedule_model.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';

void main() {
  group('BusEntryModelMapper', () {
    BusEntry makeEntry(String direction) => BusEntryModel(
          time: '09:30',
          direction: direction,
          destination: 'テスト',
        ).toEntity();

    test('maps from_chitose to fromChitose', () {
      expect(makeEntry('from_chitose').direction, BusDirection.fromChitose);
    });

    test('maps from_minami_chitose to fromMinamiChitose', () {
      expect(makeEntry('from_minami_chitose').direction, BusDirection.fromMinamiChitose);
    });

    test('maps from_kenkyuto_to_honbuto to fromKenkyutoToHonbuto', () {
      expect(makeEntry('from_kenkyuto_to_honbuto').direction, BusDirection.fromKenkyutoToHonbuto);
    });

    test('maps from_kenkyuto_to_station to fromKenkyutoToStation', () {
      expect(makeEntry('from_kenkyuto_to_station').direction, BusDirection.fromKenkyutoToStation);
    });

    test('maps from_honbuto to fromHonbuto', () {
      expect(makeEntry('from_honbuto').direction, BusDirection.fromHonbuto);
    });

    test('unknown direction falls back to fromChitose', () {
      expect(makeEntry('unknown_direction').direction, BusDirection.fromChitose);
    });

    test('copies other fields correctly', () {
      const model = BusEntryModel(
        time: '12:45',
        direction: 'from_chitose',
        destination: '千歳科技大',
        arrivals: {'stop_a': '12:50'},
      );
      final entity = model.toEntity();
      expect(entity.time, '12:45');
      expect(entity.destination, '千歳科技大');
      expect(entity.arrivals, {'stop_a': '12:50'});
    });
  });

  group('BusTimetableModelMapper', () {
    test('converts schedule list', () {
      const model = BusTimetableModel(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        pdfUrl: '',
        schedules: [
          BusEntryModel(time: '09:30', direction: 'from_chitose', destination: '千歳科技大'),
          BusEntryModel(time: '10:00', direction: 'from_honbuto', destination: '本部棟'),
        ],
      );
      final entity = model.toEntity();
      expect(entity.validFrom, '2024-01-01');
      expect(entity.validTo, '2024-03-31');
      expect(entity.schedules.length, 2);
      expect(entity.schedules[0].direction, BusDirection.fromChitose);
      expect(entity.schedules[1].direction, BusDirection.fromHonbuto);
    });
  });

  group('ScheduleResponseModelMapper', () {
    const currentModel = BusTimetableModel(
      validFrom: '2024-01-01',
      validTo: '2024-03-31',
      pdfUrl: '',
      schedules: [
        BusEntryModel(time: '09:30', direction: 'from_chitose', destination: '千歳科技大'),
      ],
    );

    test('toEntity with upcoming=null', () {
      const model = ScheduleResponseModel(
        updatedAt: '2024-01-01',
        current: currentModel,
        upcoming: null,
      );
      final entity = model.toEntity();
      expect(entity.updatedAt, '2024-01-01');
      expect(entity.upcoming, isNull);
      expect(entity.current.schedules.length, 1);
    });

    test('toEntity with non-null upcoming', () {
      const upcomingModel = BusTimetableModel(
        validFrom: '2024-04-01',
        validTo: '2024-06-30',
        pdfUrl: '',
        schedules: [],
      );
      const model = ScheduleResponseModel(
        updatedAt: '2024-01-01',
        current: currentModel,
        upcoming: upcomingModel,
      );
      final entity = model.toEntity();
      expect(entity.upcoming, isNotNull);
      expect(entity.upcoming!.validFrom, '2024-04-01');
    });
  });
}
