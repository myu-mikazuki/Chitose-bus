import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kagi_bus/domain/entities/stop_selection.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_result.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_viewmodel.dart';
import 'package:kagi_bus/presentation/viewmodels/stop_selection_viewmodel.dart';

/// 決まった [ScheduleResult] を返す ScheduleViewModel。
///
/// widget テスト・golden・単体テストの3箇所に散っていたものを、**上位集合**として
/// 1つにまとめたもの（#219）。[refreshCalled] と `refresh()` の上書きは
/// `home_screen_test` だけが使う。**呼ばない側は触らなければよい**ので、
/// 使う側ごとに別の Fake を持つ必要は無い。
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

  /// 選択を差し替える。**state を書くだけで、時刻表は取り直さない。**
  ///
  /// 本物の select() は scheduleViewModelProvider を invalidate するので、
  /// 取り直しまで含めて見たいテストではこれでは足りない。
  void setSelection(StopSelection selection) => state = AsyncData(selection);
}
