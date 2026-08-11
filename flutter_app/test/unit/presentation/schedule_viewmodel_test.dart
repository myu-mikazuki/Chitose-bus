import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kagi_bus/data/models/bus_schedule_model.dart';
import 'package:kagi_bus/data/repositories/schedule_repository_impl.dart';
import 'package:kagi_bus/data/sources/schedule_remote_source.dart';
import 'package:kagi_bus/data/repositories/stop_selection_repository.dart';
import 'package:kagi_bus/domain/entities/stop_selection.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_result.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_viewmodel.dart';

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

void main() {
  setUpAll(() => registerFallbackValue(StopSelection.initial));

  late MockScheduleRemoteSource mockSource;
  late FakeScheduleLocalSource fakeLocalSource;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockSource = MockScheduleRemoteSource();
    fakeLocalSource = FakeScheduleLocalSource();
  });

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [
        scheduleLocalSourceProvider.overrideWithValue(fakeLocalSource),
        scheduleRepositoryProvider.overrideWith(
          (ref) => ScheduleRepositoryImpl(
            remoteSource: mockSource,
            localSource: ref.read(scheduleLocalSourceProvider),
            stopSelectionRepository: StopSelectionRepository(),
          ),
        ),
      ],
    );
  }

  group('ScheduleViewModel', () {
    test('build() returns data on success (no cache)', () async {
      when(() => mockSource.fetchSchedule(any()))
          .thenAnswer((_) async => _responseModel);

      final container = makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(scheduleViewModelProvider.future);
      expect(result.data.updatedAt, '2024-01-01');
      expect(result.data.current.schedules.length, 1);
      expect(result.isFromCache, isFalse);
    });

    test('build() sets AsyncError on failure with no cache', () async {
      when(() => mockSource.fetchSchedule(any()))
          .thenThrow(Exception('network error'));

      final container = makeContainer();
      addTearDown(container.dispose);

      await expectLater(
        container.read(scheduleViewModelProvider.future),
        throwsException,
      );
      expect(container.read(scheduleViewModelProvider), isA<AsyncError>());
    });

    test('build() returns cached data immediately when cache exists', () async {
      fakeLocalSource.preload(_responseModel);
      when(() => mockSource.fetchSchedule(any()))
          .thenAnswer((_) async => _responseModel);

      final container = makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(scheduleViewModelProvider.future);
      expect(result.isFromCache, isTrue);
    });

    group('選択を変えた直後（キャッシュが今の停留所を賄えていない）', () {
      // 自分で足した停留所が一瞬「取得できていません」になるのを避けるため、
      // この経路だけは取得を先に試す（#177）
      setUp(() {
        // キャッシュは既定の4停留所ぶん。選択には morimoto を足してある
        fakeLocalSource.preload(_responseModel);
        SharedPreferences.setMockInitialValues({
          'stop_selection_ids': [...StopSelection.defaultStopIds, 'morimoto'],
        });
      });

      test('取得を先に試し、キャッシュを出さない', () async {
        when(() => mockSource.fetchSchedule(any()))
            .thenAnswer((_) async => _responseModel);

        final container = makeContainer();
        addTearDown(container.dispose);

        final result = await container.read(scheduleViewModelProvider.future);
        // 一瞬でもキャッシュを見せない
        expect(result.isFromCache, isFalse);
        verify(() => mockSource.fetchSchedule(any())).called(1);
      });

      test('取得に失敗したらキャッシュへ落ちる（オフライン）', () async {
        when(() => mockSource.fetchSchedule(any()))
            .thenThrow(Exception('network error'));

        final container = makeContainer();
        addTearDown(container.dispose);

        final result = await container.read(scheduleViewModelProvider.future);
        // 持っている停留所のぶんは出す。足した分は covers() が false になる
        expect(result.isFromCache, isTrue);
        expect(result.data.covers('chitose'), isTrue);
        expect(result.data.covers('morimoto'), isFalse);
      });
    });

    test('選択を賄えているキャッシュはそのまま出す（起動時）', () async {
      // 賄えているなら待たせる理由が無い。従来どおり即出して裏で更新する
      fakeLocalSource.preload(_responseModel);
      when(() => mockSource.fetchSchedule(any()))
          .thenAnswer((_) async => _responseModel);

      final container = makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(scheduleViewModelProvider.future);
      expect(result.isFromCache, isTrue);
    });

    test('build() silently updates to fresh data after returning cache',
        () async {
      fakeLocalSource.preload(_responseModel);
      when(() => mockSource.fetchSchedule(any()))
          .thenAnswer((_) async => _responseModel);

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(scheduleViewModelProvider.future);
      await Future<void>.delayed(Duration.zero);

      final updated = container.read(scheduleViewModelProvider).value;
      expect(updated, isNotNull);
      expect(updated!.isFromCache, isFalse);
    });

    test('build() keeps showing cache when background update fails', () async {
      fakeLocalSource.preload(_responseModel);
      when(() => mockSource.fetchSchedule(any()))
          .thenThrow(Exception('network error'));

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(scheduleViewModelProvider.future);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(scheduleViewModelProvider), isA<AsyncData>());
      expect(
        container.read(scheduleViewModelProvider).value!.isFromCache,
        isTrue,
      );
    });

    test('refresh() transitions through AsyncLoading then AsyncData', () async {
      when(() => mockSource.fetchSchedule(any()))
          .thenAnswer((_) async => _responseModel);

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(scheduleViewModelProvider.future);

      final refreshFuture =
          container.read(scheduleViewModelProvider.notifier).refresh();

      expect(container.read(scheduleViewModelProvider), isA<AsyncLoading>());

      await refreshFuture;
      expect(
        container.read(scheduleViewModelProvider),
        isA<AsyncData<ScheduleResult>>(),
      );
    });

    test('refresh() falls back to cache when fetch fails', () async {
      when(() => mockSource.fetchSchedule(any()))
          .thenAnswer((_) async => _responseModel);

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(scheduleViewModelProvider.future);

      when(() => mockSource.fetchSchedule(any()))
          .thenThrow(Exception('server error'));

      await container.read(scheduleViewModelProvider.notifier).refresh();

      expect(container.read(scheduleViewModelProvider), isA<AsyncData>());
      expect(
        container.read(scheduleViewModelProvider).value!.isFromCache,
        isTrue,
      );
    });
  });

  group('再試行が固まらない', () {
    test('取得も失敗しキャッシュ読み出しも失敗するとき、AsyncError で止まる', () async {
      // getCached が投げると refresh の catch を突き抜け、
      // AsyncLoading のまま戻れないスピナーになる
      fakeLocalSource.failOnLoad = true;
      when(() => mockSource.fetchSchedule(any()))
          .thenThrow(Exception('network error'));

      final container = makeContainer();
      addTearDown(container.dispose);
      // 初回 build も失敗する。ここのエラーは想定内なので無視する
      try {
        await container.read(scheduleViewModelProvider.future);
      } catch (_) {}

      await container.read(scheduleViewModelProvider.notifier).refresh();

      expect(container.read(scheduleViewModelProvider),
          isA<AsyncError<ScheduleResult>>(),
          reason: 'AsyncLoading のまま残ってはいけない');
    });
  });
}
