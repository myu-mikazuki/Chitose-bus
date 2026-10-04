import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';
import 'package:kagi_bus/domain/entities/stop_selection.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_result.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_viewmodel.dart';
import 'package:kagi_bus/presentation/viewmodels/stop_selection_viewmodel.dart';
import 'package:kagi_bus/presentation/views/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_view_models.dart';
import '../helpers/test_theme.dart';

/// 横画面対応。縦が短い横画面では、拡大時と同じ全体スクロール（#240 の (c)）に
/// 切り替わり、縦に溢れないこと。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const stopMaster = [
    BusStop(id: 'chitose', label: '千歳駅前', shortLabel: '千歳駅'),
    BusStop(id: 'honbuto', label: '科技大本部棟', shortLabel: '本部棟'),
  ];

  final timetable = BusTimetable(
    validFrom: '2024-01-01',
    validTo: '2024-12-31',
    pdfUrl: '',
    schedules: [
      for (var h = 6; h < 22; h++)
        BusEntry(
          time: '${h.toString().padLeft(2, '0')}:00',
          boardingStopId: 'chitose',
          destination: BusDestination.campus,
          arrivals: {'honbuto': '${h.toString().padLeft(2, '0')}:10'},
        ),
    ],
  );

  Future<void> pumpHome(WidgetTester tester, Size logical) async {
    tester.view.physicalSize = logical * 2;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleViewModelProvider.overrideWith(
            () => FakeScheduleViewModel(ScheduleResult(
              data: ScheduleResponse(
                stopMaster: stopMaster,
                updatedAt: '2024-01-01',
                current: timetable,
              ),
            )),
          ),
          stopSelectionProvider.overrideWith(
            () => FakeStopSelectionNotifier(
                const StopSelection(stopIds: ['chitose', 'honbuto'])),
          ),
          countdownOverride(),
        ],
        child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('横画面では NEXT BUS が左、TODAY\'S SCHEDULE が右に並び、溢れない', (tester) async {
    await pumpHome(tester, const Size(667, 375));

    expect(tester.takeException(), isNull);
    final next = tester.getTopLeft(find.text('NEXT BUS'));
    final schedule = tester.getTopLeft(find.text("TODAY'S SCHEDULE"));
    expect(next.dx, lessThan(schedule.dx));
    // 同じ高さの段に並ぶ（縦に積まれていない）
    expect((next.dy - schedule.dy).abs(), lessThan(40));
  });

  testWidgets('縦画面(375x667)は従来どおり縦に積む', (tester) async {
    await pumpHome(tester, const Size(375, 667));

    expect(tester.takeException(), isNull);
    final next = tester.getTopLeft(find.text('NEXT BUS'));
    final schedule = tester.getTopLeft(find.text("TODAY'S SCHEDULE"));
    expect(next.dy, lessThan(schedule.dy));
  });

  testWidgets('横画面でタブを切り替えても隣へ飛ばない', (tester) async {
    await pumpHome(tester, const Size(667, 375));

    await tester.tap(
        find.descendant(of: find.byType(TabBar), matching: find.text('本部棟')));
    await tester.pumpAndSettle();

    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
  });
}
