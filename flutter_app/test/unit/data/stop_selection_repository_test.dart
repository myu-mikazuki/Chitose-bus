import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kagi_bus/data/repositories/stop_selection_repository.dart';
import 'package:kagi_bus/domain/entities/stop_selection.dart';

void main() {
  late StopSelectionRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = StopSelectionRepository();
  });

  group('StopSelectionRepository', () {
    test('未設定なら初期値（現行の4停留所）を返す', () async {
      expect(await repo.load(), StopSelection.initial);
    });

    test('save したものが load で戻る', () async {
      const s = StopSelection(stopIds: ['chitose', 'morimoto', 'honbuto']);
      await repo.save(s);
      expect(await repo.load(), s);
    });

    test('順序が保存される', () async {
      const s = StopSelection(stopIds: ['honbuto', 'chitose']);
      await repo.save(s);
      expect((await repo.load()).stopIds, ['honbuto', 'chitose']);
    });

    test('空の選択を保存しても、読み込み時は初期値に戻る', () async {
      // 停留所が0個だと時刻表が全く出せなくなるため、保存できても復帰させる
      await repo.save(const StopSelection(stopIds: []));
      expect(await repo.load(), StopSelection.initial);
    });

    test('保存済みの値を上書きできる', () async {
      await repo.save(const StopSelection(stopIds: ['chitose']));
      await repo.save(const StopSelection(stopIds: ['honbuto']));
      expect((await repo.load()).stopIds, ['honbuto']);
    });
  });
}
