import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/stop_selection_repository.dart';
import '../../domain/entities/stop_selection.dart';

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
  /// TODO(#177): 呼び出し側は時刻表の再取得も促すこと。
  /// scheduleRepositoryProvider は SharedPreferences を直接読むため、
  /// ここで state を変えても scheduleViewModelProvider は再構築されない。
  /// 乗車地選択の UI を入れる際に ref.invalidate(scheduleViewModelProvider) が要る。
  Future<void> select(StopSelection selection) async {
    if (state.value == selection) return;
    await ref.read(stopSelectionRepositoryProvider).save(selection);
    state = AsyncData(selection);
  }
}

final stopSelectionProvider =
    AsyncNotifierProvider<StopSelectionNotifier, StopSelection>(
  StopSelectionNotifier.new,
);
