import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kagi_bus/data/repositories/schedule_repository_impl.dart';
import 'package:kagi_bus/data/sources/schedule_remote_source.dart';
import 'package:kagi_bus/data/models/bus_schedule_model.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';
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

    test('選択が変わってもキャッシュを返し、持っている停留所を伝える', () async {
      // オフラインで停留所を足しただけで時刻表が全く出せなくなるのを避ける。
      // 足りない分は coveredStopIds で分かるので、画面側が出し分ける（#177）
      fakeLocalSource.preload(_responseModel);
      SharedPreferences.setMockInitialValues({
        'stop_selection_ids': ['chitose', 'morimoto'],
      });

      final cached = await repository.getCached();
      expect(cached, isNotNull);
      expect(cached!.coveredStopIds, StopSelection.initial.stopIds);
      expect(cached.covers('chitose'), isTrue);
      // 足したばかりで一度も取得していない停留所
      expect(cached.covers('morimoto'), isFalse);
    });

    test('取得直後はいま選んでいる停留所を持っていると伝える', () async {
      SharedPreferences.setMockInitialValues({
        'stop_selection_ids': ['chitose', 'morimoto'],
      });
      when(() => mockRemoteSource.fetchSchedule(any()))
          .thenAnswer((_) async => _responseModel);

      final fresh = await repository.fetchSchedule();
      expect(fresh.coveredStopIds, ['chitose', 'morimoto']);
    });
  });

  group('#177 以前のキャッシュへのフォールバック（移行用）', () {
    final legacy = ScheduleResponse(
      updatedAt: '2026-08-01',
      current: BusTimetable(
        validFrom: '',
        validTo: '',
        schedules: [
          BusEntry(
            time: '07:20',
            boardingStopId: 'chitose',
            destination: '科技大',
            arrivals: const {'honbuto': '07:45'},
          ),
        ],
      ),
    );

    test('新形式のキャッシュが無ければ旧キャッシュを返す', () async {
      // 更新直後にオフラインでも時刻表を出せるようにする
      fakeLocalSource.legacy = legacy;

      final result = await repository.getCached();
      expect(result, isNotNull);
      expect(result!.updatedAt, '2026-08-01');
      expect(result.current.schedules.single.time, '07:20');
    });

    test('新形式のキャッシュがあればそちらを優先する', () async {
      fakeLocalSource.preload(_responseModel);
      fakeLocalSource.legacy = legacy;

      final result = await repository.getCached();
      expect(result!.updatedAt, _responseModel.updatedAt);
    });

    test('どちらも無ければ null', () async {
      expect(await repository.getCached(), isNull);
    });
  });

  group('キャッシュ読み出しが失敗しても getCached は投げない', () {
    // getCached は取得失敗後の復帰手段として呼ばれる。ここで投げると
    // 呼び出し側の catch を突き抜けて画面が AsyncLoading のまま固まる
    test('読み出しが例外を投げても null を返す', () async {
      fakeLocalSource.failOnLoad = true;

      expect(await repository.getCached(), isNull);
    });

    test('読み出しが失敗しても旧キャッシュがあればそちらを返す', () async {
      fakeLocalSource.failOnLoad = true;
      fakeLocalSource.legacy = ScheduleResponse(
        updatedAt: '2026-08-01',
        current: const BusTimetable(validFrom: '', validTo: '', schedules: []),
      );

      expect((await repository.getCached())?.updatedAt, '2026-08-01');
    });
  });
}
