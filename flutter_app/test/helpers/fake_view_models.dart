import 'dart:async';

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

/// 永遠にロード中のままの ScheduleViewModel。
///
/// widget テストと単体テストの2箇所で同じものを持っていた（#223）。
///
/// **`pumpAndSettle()` を呼ばないこと。** 解決しない future を待つので
/// タイムアウトする。`pump()` 1回で AsyncLoading の画面を確かめる。
class FakeLoadingScheduleViewModel extends ScheduleViewModel {
  @override
  Future<ScheduleResult> build() => Completer<ScheduleResult>().future;
}

/// [error] を投げる ScheduleViewModel。[FakeScheduleViewModel] のエラー版。
///
/// `refreshCalled` を持つのは向こうと同じ理由で、エラー画面の「再試行」が
/// 取り直しに繋がっているかを見るため（#223）。
class FakeErrorScheduleViewModel extends ScheduleViewModel {
  FakeErrorScheduleViewModel(this._error);

  final Object _error;

  /// [refresh] が呼ばれたか
  bool refreshCalled = false;

  @override
  Future<ScheduleResult> build() async => throw _error;

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
