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
    test('取得も失敗しキャッシュも解釈できないとき、AsyncError で止まる', () async {
      // getCached が投げると refresh の catch を突き抜け、
      // AsyncLoading のまま戻れないスピナーになる
      final poisoned = ScheduleResponseModel(
        updatedAt: '2026-08-10',
        current: const BusTimetableModel(
          trips: [
            TripModel(
              destination: '長都駅',
              stops: [StopTimeModel(id: 'chitose', time: '21:00')],
            ),
          ],
        ),
      );
      fakeLocalSource.preload(poisoned);
      when(() => mockSource.fetchSchedule(any()))
          .thenThrow(Exception('network error'));

      final container = makeContainer();
      addTearDown(container.dispose);
      // 初回 build も失敗する。ここのエラーは想定内なので無視する
      try {
        await container.read(scheduleViewModelProvider.future);
      } catch (_) {}

      // 修正前はここで getCached() の例外が refresh を突き抜けていた
      await container.read(scheduleViewModelProvider.notifier).refresh();

      final state = container.read(scheduleViewModelProvider);
      expect(state, isA<AsyncError<ScheduleResult>>(),
          reason: 'AsyncLoading のまま残ってはいけない');
    });
  });
}
