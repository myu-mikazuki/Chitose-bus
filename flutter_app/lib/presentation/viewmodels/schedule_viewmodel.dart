import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../data/repositories/schedule_repository_impl.dart';
import '../../data/sources/schedule_remote_source.dart';
import '../../data/sources/schedule_local_source.dart';
import '../../domain/entities/bus_schedule.dart';
import '../../domain/repositories/schedule_repository.dart';

// ----- Providers -----

final scheduleLocalSourceProvider = Provider<ScheduleLocalSource>((ref) {
  return ScheduleLocalSource();
});

final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  final remote = ScheduleRemoteSource(endpointUrl: AppConstants.gasEndpointUrl);
  final local = ref.read(scheduleLocalSourceProvider);
  return ScheduleRepositoryImpl(remoteSource: remote, localSource: local);
});

final scheduleViewModelProvider =
    AsyncNotifierProvider<ScheduleViewModel, ScheduleResponse>(
  ScheduleViewModel.new,
);

final debugTimeProvider = StateProvider<DateTime?>((ref) => null);

final countdownProvider =
    StateNotifierProvider<CountdownNotifier, DateTime>((ref) {
  return CountdownNotifier(ref);
});

// ----- ScheduleViewModel -----

class ScheduleViewModel extends AsyncNotifier<ScheduleResponse> {
  Timer? _refreshTimer;

  @override
  Future<ScheduleResponse> build() async {
    ref.onDispose(() => _refreshTimer?.cancel());

    final cached = await _repo.getCached();
    if (cached != null) {
      _startAutoRefresh();
      _fetchAndUpdateSilently();
      return cached;
    }

    _startAutoRefresh();
    return _fetch();
  }

  ScheduleRepository get _repo => ref.read(scheduleRepositoryProvider);

  Future<ScheduleResponse> _fetch() => _repo.fetchSchedule();

  Future<void> _fetchAndUpdateSilently() async {
    try {
      state = AsyncData(await _fetch());
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
    state = await AsyncValue.guard(_fetch);
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
