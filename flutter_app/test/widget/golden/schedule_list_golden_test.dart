import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kagi_bus/domain/entities/bus_schedule.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_viewmodel.dart';
import 'package:kagi_bus/presentation/views/widgets/schedule_list.dart';

import '../../helpers/test_theme.dart';

// NEXTハイライト用：23:59 が次のバスとなるスケジュール
// 00:01 は常に過去、23:59 は常に未来（通常の運用時間内）
final _timetableForNextHighlight = BusTimetable(
  validFrom: '2024-01-01',
  validTo: '2024-12-31',
  schedules: [
    BusEntry(
      time: '00:01',
      direction: BusDirection.fromChitose,
      destination: '千歳科技大',
    ),
    BusEntry(
      time: '23:59',
      direction: BusDirection.fromChitose,
      destination: '千歳科技大',
    ),
  ],
);

// 過去バスグレーアウト用：過去の時刻のみ（次のバスなし）
final _timetableAllPast = BusTimetable(
  validFrom: '2024-01-01',
  validTo: '2024-12-31',
  schedules: [
    BusEntry(
      time: '00:01',
      direction: BusDirection.fromChitose,
      destination: '千歳科技大',
    ),
    BusEntry(
      time: '00:02',
      direction: BusDirection.fromChitose,
      destination: '千歳科技大',
    ),
    BusEntry(
      time: '00:03',
      direction: BusDirection.fromChitose,
      destination: '千歳科技大',
    ),
  ],
);

Widget _buildTestApp({required Widget child}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildTestTheme(),
    home: Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  );
}

void main() {
  testWidgets('NEXTハイライト付きScheduleList', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          countdownProvider.overrideWith(
            (ref) => CountdownNotifier(ref)..state = DateTime(2024, 1, 1, 9, 0),
          ),
        ],
        child: _buildTestApp(
          child: ScheduleList(
            timetable: _timetableForNextHighlight,
            direction: BusDirection.fromChitose,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ScheduleList),
      matchesGoldenFile('goldens/schedule_list_with_next.png'),
    );
  });

  testWidgets('過去バスグレーアウト付きScheduleList', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 250));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          countdownProvider.overrideWith(
            (ref) =>
                CountdownNotifier(ref)..state = DateTime(2024, 1, 1, 23, 59),
          ),
        ],
        child: _buildTestApp(
          child: ScheduleList(
            timetable: _timetableAllPast,
            direction: BusDirection.fromChitose,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ScheduleList),
      matchesGoldenFile('goldens/schedule_list_past_grayed.png'),
    );
  });
}
