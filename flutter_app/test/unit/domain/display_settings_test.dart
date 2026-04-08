import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/domain/entities/display_settings.dart';

void main() {
  group('DisplaySettings', () {
    test('デフォルト値: showLectureTags=true', () {
      const s = DisplaySettings();
      expect(s.showLectureTags, isTrue);
    });

    test('copyWith: showLectureTags=false に変更', () {
      const s = DisplaySettings();
      final s2 = s.copyWith(showLectureTags: false);
      expect(s2.showLectureTags, isFalse);
    });

    test('copyWith: 省略すると元の値を保持', () {
      const s = DisplaySettings(showLectureTags: false);
      final s2 = s.copyWith();
      expect(s2.showLectureTags, isFalse);
    });

    test('== と hashCode: 同じ値は等しい', () {
      const a = DisplaySettings(showLectureTags: true);
      const b = DisplaySettings(showLectureTags: true);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('== : 異なる値は不等', () {
      const a = DisplaySettings(showLectureTags: true);
      const b = DisplaySettings(showLectureTags: false);
      expect(a, isNot(equals(b)));
    });
  });
}
