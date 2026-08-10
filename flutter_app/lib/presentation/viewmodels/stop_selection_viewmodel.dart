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

  /// AsyncNotifierBase.update と名前が衝突するため select とする
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
