import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kagi_bus/domain/entities/bus_schedule.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_viewmodel.dart';
import 'package:kagi_bus/presentation/views/widgets/next_bus_display.dart';

import '../../helpers/test_theme.dart';

// 次のバスあり：常に未来の時刻（23:59）を使う
final _timetableWithNextBus = BusTimetable(
  validFrom: '2024-01-01',
  validTo: '2024-12-31',
  schedules: [
    BusEntry(
      time: '23:59',
      direction: BusDirection.fromChitose,
      destination: '千歳科技大',
      arrivals: {'kenkyuto': '00:10', 'honbuto': '00:15'},
    ),
  ],
);

// 次のバスなし：スケジュールが空
final _timetableNoMoreBus = BusTimetable(
  validFrom: '2024-01-01',
  validTo: '2024-12-31',
  schedules: const [],
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
  testWidgets('次のバスあり状態のカード外観', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          countdownProvider.overrideWith(
            (ref) => CountdownNotifier(ref)..state = DateTime(2024, 1, 1, 9, 0),
          ),
        ],
        child: _buildTestApp(
          child: NextBusDisplay(
            timetable: _timetableWithNextBus,
            direction: BusDirection.fromChitose,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(NextBusDisplay),
      matchesGoldenFile('goldens/next_bus_card.png'),
    );
  });

  testWidgets('次のバスなし状態のカード外観', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 150));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          countdownProvider.overrideWith(
            (ref) => CountdownNotifier(ref)..state = DateTime(2024, 1, 1, 23, 59),
          ),
        ],
        child: _buildTestApp(
          child: NextBusDisplay(
            timetable: _timetableNoMoreBus,
            direction: BusDirection.fromChitose,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(NextBusDisplay),
      matchesGoldenFile('goldens/no_more_bus_card.png'),
    );
  });
}
