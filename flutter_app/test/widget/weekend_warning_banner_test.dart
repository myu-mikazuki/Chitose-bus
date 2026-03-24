import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chitose_bus/presentation/views/widgets/weekend_warning_banner.dart';

import '../helpers/test_theme.dart';

Widget _wrap(Widget child, {required DateTime now}) => ProviderScope(
      overrides: [countdownOverride(now: now)],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  group('WeekendWarningBanner', () {
    testWidgets('土曜日: バナーが表示される', (tester) async {
      // 2024-01-06 = Saturday
      final saturday = DateTime(2024, 1, 6, 9, 0);
      await tester.pumpWidget(_wrap(const WeekendWarningBanner(), now: saturday));

      expect(
        find.text('土日祝日は一部の便のみ運行します（系統2は運休）'),
        findsOneWidget,
      );
    });

    testWidgets('日曜日: バナーが表示される', (tester) async {
      // 2024-01-07 = Sunday
      final sunday = DateTime(2024, 1, 7, 9, 0);
      await tester.pumpWidget(_wrap(const WeekendWarningBanner(), now: sunday));

      expect(
        find.text('土日祝日は一部の便のみ運行します（系統2は運休）'),
        findsOneWidget,
      );
    });

    testWidgets('月曜日: バナーが表示されない', (tester) async {
      // 2024-01-01 = Monday (kTestNow default)
      final monday = DateTime(2024, 1, 1, 9, 0);
      await tester.pumpWidget(_wrap(const WeekendWarningBanner(), now: monday));

      expect(
        find.text('土日祝日は一部の便のみ運行します（系統2は運休）'),
        findsNothing,
      );
    });

    testWidgets('金曜日: バナーが表示されない', (tester) async {
      // 2024-01-05 = Friday
      final friday = DateTime(2024, 1, 5, 9, 0);
      await tester.pumpWidget(_wrap(const WeekendWarningBanner(), now: friday));

      expect(
        find.text('土日祝日は一部の便のみ運行します（系統2は運休）'),
        findsNothing,
      );
    });
  });
}
