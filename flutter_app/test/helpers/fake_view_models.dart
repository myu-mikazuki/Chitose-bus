import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kagi_bus/domain/entities/stop_selection.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_result.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_viewmodel.dart';
import 'package:kagi_bus/presentation/viewmodels/stop_selection_viewmodel.dart';

/// 決まった [ScheduleResult] を返すだけの ScheduleViewModel。
///
/// widget テスト・golden・単体テストの3箇所で同じものを持っていた（#219）。
class FakeScheduleViewModel extends ScheduleViewModel {
  FakeScheduleViewModel(this._result);

  final ScheduleResult _result;

  /// [refresh] が呼ばれたか。「再試行」を押したときの確認に使う
  bool refreshCalled = false;

  @override
  Future<ScheduleResult> build() async => _result;

  /// 本物は取り直して state を差し替えるが、テストでは呼ばれたことだけ見る
  @override
  Future<void> refresh() async {
    refreshCalled = true;
  }
}

/// 選択を外から差し替えられる StopSelectionNotifier。設定画面での操作を再現する。
///
/// 本物の select() は scheduleViewModelProvider を invalidate するため使わない。
class FakeStopSelectionNotifier extends StopSelectionNotifier {
  FakeStopSelectionNotifier(this._initial);

  final StopSelection _initial;

  @override
  Future<StopSelection> build() async => _initial;

  void set(StopSelection selection) => state = AsyncData(selection);
}
