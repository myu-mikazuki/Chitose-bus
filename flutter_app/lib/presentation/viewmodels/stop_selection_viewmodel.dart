import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/stop_selection_repository.dart';
import '../../domain/entities/stop_selection.dart';
import 'schedule_viewmodel.dart';

final stopSelectionRepositoryProvider = Provider<StopSelectionRepository>(
  (ref) => StopSelectionRepository(),
);

/// タブに表示する停留所の選択。
///
/// 変更すると GAS への `?stops=` が変わり、キャッシュも別扱いになるため、
/// 時刻表の取り直しが必要になる（Issue #177）。
class StopSelectionNotifier extends AsyncNotifier<StopSelection> {
  @override
  Future<StopSelection> build() =>
      ref.read(stopSelectionRepositoryProvider).load();

  /// AsyncNotifierBase.update と名前が衝突するため select とする。
  ///
  /// 時刻表の再取得はここで面倒を見る。呼び出し側に任せると、選択だけ変わって
  /// 時刻表が古いままという組み合わせが作れてしまう。
  ///
  /// **並べ替えだけでも再取得する。** 並び順は `?stops=` に出る以上キャッシュの
  /// キーも変わり、順序がそのままタブの並びになるため意味のある違いとして扱う。
  Future<void> select(StopSelection selection) async {
    if (state.value == selection) return;
    await ref.read(stopSelectionRepositoryProvider).save(selection);
    state = AsyncData(selection);
    // scheduleRepositoryProvider は SharedPreferences を直接読むため、
    // state を変えるだけでは scheduleViewModelProvider は作り直されない
    ref.invalidate(scheduleViewModelProvider);
  }
}

final stopSelectionProvider =
    AsyncNotifierProvider<StopSelectionNotifier, StopSelection>(
  StopSelectionNotifier.new,
);
