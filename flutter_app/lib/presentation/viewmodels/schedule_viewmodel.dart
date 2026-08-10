import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../data/repositories/schedule_repository_impl.dart';
import '../../data/sources/schedule_remote_source.dart';
import '../../data/sources/schedule_local_source.dart';
import 'stop_selection_viewmodel.dart';
import '../../domain/entities/bus_schedule.dart';
import '../../domain/repositories/schedule_repository.dart';
import 'schedule_result.dart';

// ----- Providers -----

final scheduleLocalSourceProvider = Provider<ScheduleLocalSource>((ref) {
  return ScheduleLocalSource();
});

final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  final remote = ScheduleRemoteSource(endpointUrl: AppConstants.gasEndpointUrl);
  final local = ref.read(scheduleLocalSourceProvider);
  return ScheduleRepositoryImpl(
    remoteSource: remote,
    localSource: local,
    stopSelectionRepository: ref.read(stopSelectionRepositoryProvider),
  );
});

final scheduleViewModelProvider =
    AsyncNotifierProvider<ScheduleViewModel, ScheduleResult>(
  ScheduleViewModel.new,
);

final debugTimeProvider = StateProvider<DateTime?>((ref) => null);

/// 当日以外のダイヤ表示モード。null = 当日のダイヤを表示（通常表示）。
/// 非 null の場合、指定したダイヤ種別（平日 / 土日祝）の全便を表示する。
final dayTypeOverrideProvider = StateProvider<DayType?>((ref) => null);

/// 当日以外のダイヤ表示モードで表示する期別（授業期 / 学休期）。
/// [dayTypeOverrideProvider] と同時に設定・解除される。
final seasonOverrideProvider = StateProvider<SeasonType?>((ref) => null);

final countdownProvider =
    StateNotifierProvider<CountdownNotifier, DateTime>((ref) {
  return CountdownNotifier(ref);
});

// ----- ScheduleViewModel -----

class ScheduleViewModel extends AsyncNotifier<ScheduleResult> {
  Timer? _refreshTimer;

  @override
  Future<ScheduleResult> build() async {
    ref.onDispose(() => _refreshTimer?.cancel());

    final cached = await _repo.getCached();
    if (cached != null) {
      _startAutoRefresh();
      _fetchAndUpdateSilently();
      return ScheduleResult(data: cached, isFromCache: true);
    }

    _startAutoRefresh();
    return ScheduleResult(data: await _repo.fetchSchedule());
  }

  ScheduleRepository get _repo => ref.read(scheduleRepositoryProvider);

  Future<void> _fetchAndUpdateSilently() async {
    try {
      final fresh = await _repo.fetchSchedule();
      state = AsyncData(ScheduleResult(data: fresh));
    } catch (_) {
      // キャッシュを表示し続ける
    }
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(AppConstants.scheduleRefreshInterval, (_) {
      _fetchAndUpdateSilently();
    });
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      final fresh = await _repo.fetchSchedule();
      state = AsyncData(ScheduleResult(data: fresh));
    } catch (e, st) {
      final cached = await _repo.getCached();
      if (cached != null) {
        state = AsyncData(ScheduleResult(data: cached, isFromCache: true));
      } else {
        state = AsyncError(e, st);
      }
    }
  }
}

// ----- CountdownNotifier -----

class CountdownNotifier extends StateNotifier<DateTime> {
  CountdownNotifier(this._ref) : super(DateTime.now()) {
    _timer = Timer.periodic(AppConstants.countdownRefreshInterval, (_) {
      state = _ref.read(debugTimeProvider) ?? DateTime.now();
    });
  }

  final Ref _ref;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
