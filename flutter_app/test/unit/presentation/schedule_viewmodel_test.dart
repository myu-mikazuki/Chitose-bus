import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:kagi_bus/data/models/bus_schedule_model.dart';
import 'package:kagi_bus/data/repositories/schedule_repository_impl.dart';
import 'package:kagi_bus/data/sources/schedule_remote_source.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_viewmodel.dart';

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

  setUp(() {
    mockSource = MockScheduleRemoteSource();
  });

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [
        scheduleRepositoryProvider.overrideWith(
          (ref) => ScheduleRepositoryImpl(remoteSource: mockSource),
        ),
      ],
    );
  }

  group('ScheduleViewModel', () {
    test('build() returns data on success', () async {
      when(() => mockSource.fetchSchedule())
          .thenAnswer((_) async => _responseModel);

      final container = makeContainer();
      addTearDown(container.dispose);

      final result = await container.read(scheduleViewModelProvider.future);
      expect(result.updatedAt, '2024-01-01');
      expect(result.current.schedules.length, 1);
      expect(result.upcoming, isNull);
    });

    test('build() sets AsyncError on failure', () async {
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

    test('refresh() transitions through AsyncLoading then AsyncData', () async {
      when(() => mockSource.fetchSchedule())
          .thenAnswer((_) async => _responseModel);

      final container = makeContainer();
      addTearDown(container.dispose);

      // Wait for initial build to complete
      await container.read(scheduleViewModelProvider.future);

      // Trigger refresh (don't await yet)
      // refresh() sets state = AsyncLoading() synchronously before first await
      final refreshFuture =
          container.read(scheduleViewModelProvider.notifier).refresh();

      expect(container.read(scheduleViewModelProvider), isA<AsyncLoading>());

      await refreshFuture;
      expect(
        container.read(scheduleViewModelProvider),
        isA<AsyncData<ScheduleResponse>>(),
      );
    });

    test('refresh() sets AsyncError when fetch fails', () async {
      when(() => mockSource.fetchSchedule())
          .thenAnswer((_) async => _responseModel);

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(scheduleViewModelProvider.future);

      // Subsequent fetches fail
      when(() => mockSource.fetchSchedule())
          .thenThrow(Exception('server error'));

      await container.read(scheduleViewModelProvider.notifier).refresh();

      expect(container.read(scheduleViewModelProvider), isA<AsyncError>());
    });
  });
}
