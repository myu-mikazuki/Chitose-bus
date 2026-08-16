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
    _startAutoRefresh();

    final cached = await _repo.getCached();
    if (cached == null) {
      return ScheduleResult(data: await _repo.fetchSchedule());
    }

    // 選択を変えた直後は、キャッシュが今の停留所を賄えていない。
    //
    // そのまま出すと、**自分で足した停留所が一瞬「取得できていません」になり**、
    // 「キャッシュデータを表示中」バナーまで出てから正しい時刻に切り替わる。
    // 操作した直後だけに戸惑いやすいので、この経路は取得を先に試す。
    // オフラインなら失敗するまで待たされるが、持っている分は結局出る（#177）。
    final selection = await ref.read(stopSelectionRepositoryProvider).load();
    if (!selection.stopIds.every(cached.covers)) {
      try {
        return ScheduleResult(data: await _repo.fetchSchedule());
      } catch (_) {
        return ScheduleResult(data: cached, isFromCache: true);
      }
    }

    // 起動時などキャッシュが今の選択を賄えている場合。すぐ出して裏で更新する
    _fetchAndUpdateSilently();
    return ScheduleResult(data: cached, isFromCache: true);
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
