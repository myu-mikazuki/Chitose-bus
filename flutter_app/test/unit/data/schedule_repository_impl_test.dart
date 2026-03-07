import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:chitose_bus/data/repositories/schedule_repository_impl.dart';
import 'package:chitose_bus/data/sources/schedule_remote_source.dart';
import 'package:chitose_bus/data/models/bus_schedule_model.dart';

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
  late ScheduleRepositoryImpl repository;

  setUp(() {
    mockRemoteSource = MockScheduleRemoteSource();
    repository = ScheduleRepositoryImpl(remoteSource: mockRemoteSource);
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

    test('propagates exception thrown by remoteSource', () async {
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
}
