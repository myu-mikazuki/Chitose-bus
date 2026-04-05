import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kagi_bus/data/models/bus_schedule_model.dart';
import 'package:kagi_bus/data/repositories/schedule_repository_impl.dart';
import 'package:kagi_bus/data/sources/schedule_remote_source.dart';
import 'package:kagi_bus/data/sources/schedule_local_source.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_viewmodel.dart';

class MockScheduleRemoteSource extends Mock implements ScheduleRemoteSource {}

class FakeScheduleLocalSource implements ScheduleLocalSource {
  ScheduleResponseModel? stored;

  @override
  Future<ScheduleResponseModel?> load() async => stored;

  @override
  Future<void> save(ScheduleResponseModel model) async => stored = model;

  @override
  Future<DateTime?> loadCachedAt() async =>
      stored != null ? DateTime.now() : null;
}

const _responseModel = ScheduleResponseModel(
  updatedAt: '2024-01-01',
  current: BusTimetableModel(
    validFrom: '2024-01-01',
    validTo: '2024-03-31',
    pdfUrl: '',
    schedules: [
      BusEntryModel(time: '09:30', direction: 'from_chitose', destination: '千歳科技大'),
    ],
  ),
  upcoming: null,
);

void main() {
  late MockScheduleRemoteSource mockSource;
  late FakeScheduleLocalSource fakeLocalSource;

  setUp(() {
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
          ),
        ),
      ],
    );
  }

  group('ScheduleViewModel', () {
    test('build() returns data on success (no cache)', () async {
      when(() => mockSource.fetchSchedule())
          .thenAnswer((_) async => _responseModel);

      final container = makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(scheduleViewModelProvider.future);
      expect(result.updatedAt, '2024-01-01');
      expect(result.current.schedules.length, 1);
      expect(result.upcoming, isNull);
      expect(result.isFromCache, isFalse);
    });

    test('build() sets AsyncError on failure with no cache', () async {
      when(() => mockSource.fetchSchedule())
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
      fakeLocalSource.stored = _responseModel;
      // remote は遅延して成功
      when(() => mockSource.fetchSchedule())
          .thenAnswer((_) async => _responseModel);

      final container = makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(scheduleViewModelProvider.future);
      // キャッシュから即返るので isFromCache: true
      expect(result.isFromCache, isTrue);
    });

    test('build() silently updates to fresh data after returning cache',
        () async {
      fakeLocalSource.stored = _responseModel;
      when(() => mockSource.fetchSchedule())
          .thenAnswer((_) async => _responseModel);

      final container = makeContainer();
      addTearDown(container.dispose);

      // 初期値（キャッシュ）を取得
      await container.read(scheduleViewModelProvider.future);

      // バックグラウンド更新が完了するまで待つ
      await Future<void>.delayed(Duration.zero);

      final updated = container.read(scheduleViewModelProvider).value;
      expect(updated, isNotNull);
      expect(updated!.isFromCache, isFalse);
    });

    test('build() keeps showing cache when background update fails', () async {
      fakeLocalSource.stored = _responseModel;
      when(() => mockSource.fetchSchedule())
          .thenThrow(Exception('network error'));

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(scheduleViewModelProvider.future);
      await Future<void>.delayed(Duration.zero);

      // エラーにならずキャッシュが表示されたまま
      expect(container.read(scheduleViewModelProvider), isA<AsyncData>());
      expect(
        container.read(scheduleViewModelProvider).value!.isFromCache,
        isTrue,
      );
    });

    test('refresh() transitions through AsyncLoading then AsyncData', () async {
      when(() => mockSource.fetchSchedule())
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
        isA<AsyncData<ScheduleResponse>>(),
      );
    });

    test('refresh() falls back to cache when fetch fails', () async {
      when(() => mockSource.fetchSchedule())
          .thenAnswer((_) async => _responseModel);

      final container = makeContainer();
      addTearDown(container.dispose);

      // 初回成功でキャッシュが保存される
      await container.read(scheduleViewModelProvider.future);

      // 以降のフェッチは失敗
      when(() => mockSource.fetchSchedule())
          .thenThrow(Exception('server error'));

      await container.read(scheduleViewModelProvider.notifier).refresh();

      // キャッシュがあるので AsyncData(isFromCache: true) になる
      expect(container.read(scheduleViewModelProvider), isA<AsyncData>());
      expect(
        container.read(scheduleViewModelProvider).value!.isFromCache,
        isTrue,
      );
    });
  });
}
