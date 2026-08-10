import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kagi_bus/data/repositories/schedule_repository_impl.dart';
import 'package:kagi_bus/data/sources/schedule_remote_source.dart';
import 'package:kagi_bus/data/models/bus_schedule_model.dart';
import 'package:kagi_bus/data/repositories/stop_selection_repository.dart';
import 'package:kagi_bus/domain/entities/stop_selection.dart';

import '../../helpers/fake_schedule_local_source.dart';

class MockScheduleRemoteSource extends Mock implements ScheduleRemoteSource {}

const _responseModel = ScheduleResponseModel(
  updatedAt: '2024-01-01',
  current: BusTimetableModel(
    validFrom: '2024-01-01',
    validTo: '2024-03-31',
    pdfUrl: '',
    trips: [
      TripModel(
        destination: '科技大',
        stops: [
          StopTimeModel(id: 'chitose', time: '09:30'),
          StopTimeModel(id: 'honbuto', time: '09:55'),
        ],
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
    trips: [],
  ),
  upcoming: BusTimetableModel(
    validFrom: '2024-04-01',
    validTo: '2024-06-30',
    pdfUrl: '',
    trips: [],
  ),
);

void main() {
  setUpAll(() => registerFallbackValue(StopSelection.initial));

  late MockScheduleRemoteSource mockRemoteSource;
  late FakeScheduleLocalSource fakeLocalSource;
  late ScheduleRepositoryImpl repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRemoteSource = MockScheduleRemoteSource();
    fakeLocalSource = FakeScheduleLocalSource();
    repository = ScheduleRepositoryImpl(
      remoteSource: mockRemoteSource,
      localSource: fakeLocalSource,
      stopSelectionRepository: StopSelectionRepository(),
    );
  });

  group('ScheduleRepositoryImpl.fetchSchedule', () {
    test('maps remoteSource result to ScheduleResponse entity', () async {
      when(() => mockRemoteSource.fetchSchedule(any()))
          .thenAnswer((_) async => _responseModel);

      final result = await repository.fetchSchedule();

      verify(() => mockRemoteSource.fetchSchedule(any())).called(1);
      expect(result.updatedAt, '2024-01-01');
      expect(result.current.schedules.length, 1);
      expect(result.upcoming, isNull);
    });

    test('saves to local cache on success', () async {
      when(() => mockRemoteSource.fetchSchedule(any()))
          .thenAnswer((_) async => _responseModel);

      await repository.fetchSchedule();

      expect(fakeLocalSource.saveCallCount, 1);
      expect(fakeLocalSource.stored, _responseModel);
    });

    test('propagates exception when remote fails', () async {
      when(() => mockRemoteSource.fetchSchedule(any()))
          .thenThrow(Exception('network error'));

      expect(() => repository.fetchSchedule(), throwsException);
    });

    test('maps upcoming timetable when non-null', () async {
      when(() => mockRemoteSource.fetchSchedule(any()))
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
      fakeLocalSource.preload(_responseModel);

      final result = await repository.getCached();

      expect(result, isNotNull);
      expect(result!.updatedAt, '2024-01-01');
    });

    test('returns cached upcoming timetable correctly', () async {
      fakeLocalSource.preload(_responseModelWithUpcoming);

      final result = await repository.getCached();

      expect(result!.upcoming, isNotNull);
      expect(result.upcoming!.validFrom, '2024-04-01');
    });
  });

  group('停留所の選択が remote / local に伝わる', () {
    test('保存済みの選択がそのまま fetchSchedule と キャッシュキーに渡る', () async {
      SharedPreferences.setMockInitialValues({
        'stop_selection_ids': ['chitose', 'morimoto'],
      });
      when(() => mockRemoteSource.fetchSchedule(any()))
          .thenAnswer((_) async => _responseModel);

      await repository.fetchSchedule();

      verify(() => mockRemoteSource.fetchSchedule(
            const StopSelection(stopIds: ['chitose', 'morimoto']),
          )).called(1);
      expect(fakeLocalSource.storedStops, 'chitose,morimoto');
    });

    test('選択が未設定なら既定の4停留所で取得する', () async {
      when(() => mockRemoteSource.fetchSchedule(any()))
          .thenAnswer((_) async => _responseModel);

      await repository.fetchSchedule();

      verify(() => mockRemoteSource.fetchSchedule(StopSelection.initial))
          .called(1);
      expect(fakeLocalSource.storedStops, StopSelection.initial.query);
    });

    test('選択が変わるとキャッシュは当たらない', () async {
      // 既定の選択で保存されたキャッシュは、別の選択では使えない
      fakeLocalSource.preload(_responseModel);
      SharedPreferences.setMockInitialValues({
        'stop_selection_ids': ['chitose', 'morimoto'],
      });

      expect(await repository.getCached(), isNull);
    });
  });
}
