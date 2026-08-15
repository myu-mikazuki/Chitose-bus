import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';
import 'package:kagi_bus/domain/entities/stop_selection.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_result.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_viewmodel.dart';
import 'package:kagi_bus/presentation/viewmodels/stop_selection_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 作り直された回数を数えるだけの VM。
/// invalidate されると build がもう一度走る。
int _scheduleBuilds = 0;

class _CountingScheduleViewModel extends ScheduleViewModel {
  @override
  Future<ScheduleResult> build() async {
    _scheduleBuilds++;
    return ScheduleResult(
      data: ScheduleResponse(
        updatedAt: '2024-01-01',
        current: const BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-12-31',
          schedules: [],
        ),
      ),
    );
  }
}

ProviderContainer _makeContainer() {
  final container = ProviderContainer(
    overrides: [
      scheduleViewModelProvider.overrideWith(_CountingScheduleViewModel.new),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _scheduleBuilds = 0;
  });

  group('StopSelectionNotifier', () {
    test('build: 未設定なら初期値（現行の4停留所）', () async {
      final container = _makeContainer();

      expect(await container.read(stopSelectionProvider.future),
          StopSelection.initial);
    });

    test('build: 保存済みの選択を読む', () async {
      SharedPreferences.setMockInitialValues({
        'stop_selection_ids': ['honbuto', 'morimoto'],
      });
      final container = _makeContainer();

      final result = await container.read(stopSelectionProvider.future);
      expect(result.stopIds, ['honbuto', 'morimoto']);
    });

    test('select: state が更新され、SharedPreferences にも残る', () async {
      final container = _makeContainer();
      await container.read(stopSelectionProvider.future);

      const next = StopSelection(stopIds: ['chitose', 'morimoto']);
      await container.read(stopSelectionProvider.notifier).select(next);

      expect(container.read(stopSelectionProvider).value, next);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('stop_selection_ids'), ['chitose', 'morimoto']);
    });

    test('select: 時刻表が取り直される（?stops= が変わるため）', () async {
      final container = _makeContainer();
      await container.read(stopSelectionProvider.future);
      await container.read(scheduleViewModelProvider.future);
      expect(_scheduleBuilds, 1);

      await container.read(stopSelectionProvider.notifier).select(
            const StopSelection(stopIds: ['chitose', 'morimoto']),
          );
      await container.read(scheduleViewModelProvider.future);

      expect(_scheduleBuilds, 2);
    });

    test('select: 並べ替えただけでも取り直す（順序も ?stops= に出る）', () async {
      final container = _makeContainer();
      await container.read(stopSelectionProvider.future);
      await container.read(scheduleViewModelProvider.future);

      final reversed =
          StopSelection(stopIds: StopSelection.defaultStopIds.reversed.toList());
      await container.read(stopSelectionProvider.notifier).select(reversed);
      await container.read(scheduleViewModelProvider.future);

      expect(_scheduleBuilds, 2);
    });

    test('select: 同じ選択なら取り直さない', () async {
      final container = _makeContainer();
      await container.read(stopSelectionProvider.future);
      await container.read(scheduleViewModelProvider.future);

      await container
          .read(stopSelectionProvider.notifier)
          .select(StopSelection.initial);
      await container.read(scheduleViewModelProvider.future);

      expect(_scheduleBuilds, 1);
    });
  });
}
