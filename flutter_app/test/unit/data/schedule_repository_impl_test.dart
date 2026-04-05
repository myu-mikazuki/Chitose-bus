import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kagi_bus/data/repositories/schedule_repository_impl.dart';
import 'package:kagi_bus/data/sources/schedule_remote_source.dart';
import 'package:kagi_bus/data/models/bus_schedule_model.dart';

import '../../helpers/fake_schedule_local_source.dart';

class MockScheduleRemoteSource extends Mock implements ScheduleRemoteSource {}

const _responseModel = ScheduleResponseModel(
  updatedAt: '2024-01-01',
  current: BusTimetableModel(
    validFrom: '2024-01-01',
    validTo: '2024-03-31',
    pdfUrl: '',
    schedules: [
      BusEntryModel(
        time: '09:30',
        direction: 'from_chitose',
        destination: '千歳科技大',
      ),
    ],
  ),
  upcoming: null,
);

const _responseModelWithUpcoming = ScheduleResponseModel(
  updatedAt: '2024-01-01',
  current: BusTimetableModel(
    validFrom: '2024-01-01',
    validTo: '2024-03-31',
    pdfUrl: '',
    schedules: [],
  ),
  upcoming: BusTimetableModel(
    validFrom: '2024-04-01',
    validTo: '2024-06-30',
    pdfUrl: '',
    schedules: [],
  ),
);

void main() {
  late MockScheduleRemoteSource mockRemoteSource;
  late FakeScheduleLocalSource fakeLocalSource;
  late ScheduleRepositoryImpl repository;

  setUp(() {
    mockRemoteSource = MockScheduleRemoteSource();
    fakeLocalSource = FakeScheduleLocalSource();
    repository = ScheduleRepositoryImpl(
      remoteSource: mockRemoteSource,
      localSource: fakeLocalSource,
    );
  });

  group('ScheduleRepositoryImpl.fetchSchedule', () {
    test('maps remoteSource result to ScheduleResponse entity', () async {
      when(() => mockRemoteSource.fetchSchedule())
          .thenAnswer((_) async => _responseModel);

      final result = await repository.fetchSchedule();

      verify(() => mockRemoteSource.fetchSchedule()).called(1);
      expect(result.updatedAt, '2024-01-01');
      expect(result.current.schedules.length, 1);
      expect(result.upcoming, isNull);
    });

    test('saves to local cache on success', () async {
      when(() => mockRemoteSource.fetchSchedule())
          .thenAnswer((_) async => _responseModel);

      await repository.fetchSchedule();

      expect(fakeLocalSource.saveCallCount, 1);
      expect(fakeLocalSource.stored, _responseModel);
    });

    test('propagates exception when remote fails', () async {
      when(() => mockRemoteSource.fetchSchedule())
          .thenThrow(Exception('network error'));

      expect(() => repository.fetchSchedule(), throwsException);
    });

    test('maps upcoming timetable when non-null', () async {
      when(() => mockRemoteSource.fetchSchedule())
          .thenAnswer((_) async => _responseModelWithUpcoming);

      final result = await repository.fetchSchedule();

      expect(result.upcoming, isNotNull);
      expect(result.upcoming!.validFrom, '2024-04-01');
    });
  });

  group('ScheduleRepositoryImpl.getCached', () {
    test('returns null when no cache exists', () async {
      expect(await repository.getCached(), isNull);
    });

    test('returns cached data', () async {
      fakeLocalSource.stored = _responseModel;

      final result = await repository.getCached();

      expect(result, isNotNull);
      expect(result!.updatedAt, '2024-01-01');
    });

    test('returns cached upcoming timetable correctly', () async {
      fakeLocalSource.stored = _responseModelWithUpcoming;

      final result = await repository.getCached();

      expect(result!.upcoming, isNotNull);
      expect(result.upcoming!.validFrom, '2024-04-01');
    });
  });
}
