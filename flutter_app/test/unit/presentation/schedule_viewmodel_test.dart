import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kagi_bus/data/models/bus_schedule_model.dart';
import 'package:kagi_bus/data/repositories/schedule_repository_impl.dart';
import 'package:kagi_bus/data/sources/schedule_remote_source.dart';
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
      expect(result.data.updatedAt, '2024-01-01');
      expect(result.data.current.schedules.length, 1);
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
      when(() => mockSource.fetchSchedule())
          .thenAnswer((_) async => _responseModel);

      final container = makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(scheduleViewModelProvider.future);
      expect(result.isFromCache, isTrue);
    });

    test('build() silently updates to fresh data after returning cache',
        () async {
      fakeLocalSource.stored = _responseModel;
      when(() => mockSource.fetchSchedule())
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
      fakeLocalSource.stored = _responseModel;
      when(() => mockSource.fetchSchedule())
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
        isA<AsyncData<ScheduleResult>>(),
      );
    });

    test('refresh() falls back to cache when fetch fails', () async {
      when(() => mockSource.fetchSchedule())
          .thenAnswer((_) async => _responseModel);

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(scheduleViewModelProvider.future);

      when(() => mockSource.fetchSchedule())
          .thenThrow(Exception('server error'));

      await container.read(scheduleViewModelProvider.notifier).refresh();

      expect(container.read(scheduleViewModelProvider), isA<AsyncData>());
      expect(
        container.read(scheduleViewModelProvider).value!.isFromCache,
        isTrue,
      );
    });
  });
}
