import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/domain/entities/stop_selection.dart';

void main() {
  group('StopSelection', () {
    test('初期値は現行の4停留所（千歳駅・南千歳・研究棟・本部棟）', () {
      // この順序がそのままタブの並びになる。変えると既存ユーザーの見た目が変わる
      expect(StopSelection.initial.stopIds, [
        'chitose',
        'minamiChitose',
        'kenkyuto',
        'honbuto',
      ]);
    });

    test('query は GAS の ?stops= に渡すカンマ区切り', () {
      expect(
        StopSelection.initial.query,
        'chitose,minamiChitose,kenkyuto,honbuto',
      );
    });

    test('順序が違えば別の選択として扱う（タブの並びが変わるため）', () {
      const a = StopSelection(stopIds: ['chitose', 'honbuto']);
      const b = StopSelection(stopIds: ['honbuto', 'chitose']);
      expect(a, isNot(b));
      expect(a.query, isNot(b.query));
    });

    test('同じ並びなら等しい', () {
      const a = StopSelection(stopIds: ['chitose', 'honbuto']);
      const b = StopSelection(stopIds: ['chitose', 'honbuto']);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
