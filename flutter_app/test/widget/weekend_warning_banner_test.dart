import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/presentation/views/widgets/weekend_warning_banner.dart';

import '../helpers/test_theme.dart';

Widget _wrap(Widget child, {required DateTime now}) => ProviderScope(
      overrides: [countdownOverride(now: now)],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  group('WeekendWarningBanner', () {
    // 市路線バスは土日も一部運行するためバナーは現在非表示（_enabled = false）
    testWidgets('土曜日: バナーが表示されない（現在無効化中）', (tester) async {
      // 2024-01-06 = Saturday
      final saturday = DateTime(2024, 1, 6, 9, 0);
      await tester.pumpWidget(_wrap(const WeekendWarningBanner(), now: saturday));

      expect(
        find.text('土日祝日はバスが運行していない場合があります'),
        findsNothing,
      );
    });

    testWidgets('日曜日: バナーが表示されない（現在無効化中）', (tester) async {
      // 2024-01-07 = Sunday
      final sunday = DateTime(2024, 1, 7, 9, 0);
      await tester.pumpWidget(_wrap(const WeekendWarningBanner(), now: sunday));

      expect(
        find.text('土日祝日はバスが運行していない場合があります'),
        findsNothing,
      );
    });

    testWidgets('月曜日: バナーが表示されない', (tester) async {
      // 2024-01-01 = Monday (kTestNow default)
      final monday = DateTime(2024, 1, 1, 9, 0);
      await tester.pumpWidget(_wrap(const WeekendWarningBanner(), now: monday));

      expect(
        find.text('土日祝日はバスが運行していない場合があります'),
        findsNothing,
      );
    });

    testWidgets('金曜日: バナーが表示されない', (tester) async {
      // 2024-01-05 = Friday
      final friday = DateTime(2024, 1, 5, 9, 0);
      await tester.pumpWidget(_wrap(const WeekendWarningBanner(), now: friday));

      expect(
        find.text('土日祝日はバスが運行していない場合があります'),
        findsNothing,
      );
    });
  });
}
