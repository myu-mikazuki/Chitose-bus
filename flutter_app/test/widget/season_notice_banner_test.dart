import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_viewmodel.dart';
import 'package:kagi_bus/presentation/views/widgets/season_notice_banner.dart';

import '../helpers/test_theme.dart';

Widget _wrap({required DateTime now, DayType? dayTypeOverride}) =>
    ProviderScope(
      overrides: [
        countdownOverride(now: now),
        if (dayTypeOverride != null)
          dayTypeOverrideProvider.overrideWith((ref) => dayTypeOverride),
      ],
      child: MaterialApp(
        theme: buildTestTheme(),
        home: const Scaffold(body: SeasonNoticeBanner()),
      ),
    );

void main() {
  group('SeasonNoticeBanner', () {
    testWidgets('授業期の平日: 何も表示されない', (tester) async {
      await tester.pumpWidget(_wrap(now: DateTime(2026, 6, 17, 9, 0)));
      await tester.pump();

      expect(find.byType(Icon), findsNothing);
      expect(find.textContaining('学休期'), findsNothing);
    });

    testWidgets('学休期（2026-08-03）: 学休期ダイヤの案内が表示される', (tester) async {
      await tester.pumpWidget(_wrap(now: DateTime(2026, 8, 3, 9, 0)));
      await tester.pump();

      expect(find.textContaining('学休期ダイヤで運行中'), findsOneWidget);
    });

    testWidgets('冬季学休期（2026-02-02）でも表示される', (tester) async {
      await tester.pumpWidget(_wrap(now: DateTime(2026, 2, 2, 9, 0)));
      await tester.pump();

      expect(find.textContaining('学休期ダイヤで運行中'), findsOneWidget);
    });

    testWidgets('年末年始（2026-01-01）: 全便運休の案内が表示される', (tester) async {
      await tester.pumpWidget(_wrap(now: DateTime(2026, 1, 1, 9, 0)));
      await tester.pump();

      expect(find.textContaining('全便運休'), findsOneWidget);
      expect(find.textContaining('学休期ダイヤで運行中'), findsNothing);
    });

    testWidgets('当日以外のダイヤ表示中は表示されない', (tester) async {
      await tester.pumpWidget(_wrap(
        now: DateTime(2026, 8, 3, 9, 0),
        dayTypeOverride: DayType.weekday,
      ));
      await tester.pump();

      expect(find.textContaining('学休期'), findsNothing);
    });
  });
}
