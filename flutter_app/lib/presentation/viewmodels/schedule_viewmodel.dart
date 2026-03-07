import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../data/repositories/schedule_repository_impl.dart';
import '../../data/sources/schedule_remote_source.dart';
import '../../domain/entities/bus_schedule.dart';

// ----- Providers -----

final scheduleRepositoryProvider = Provider((ref) {
  final source = ScheduleRemoteSource(endpointUrl: AppConstants.gasEndpointUrl);
  return ScheduleRepositoryImpl(remoteSource: source);
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
    _startAutoRefresh();
    return _fetch();
  }

  Future<ScheduleResponse> _fetch() {
    final repo = ref.read(scheduleRepositoryProvider);
    return repo.fetchSchedule();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(AppConstants.scheduleRefreshInterval, (_) {
      refresh();
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
