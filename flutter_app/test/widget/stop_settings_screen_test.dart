import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';
import 'package:kagi_bus/domain/entities/stop_selection.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_result.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_viewmodel.dart';
import 'package:kagi_bus/presentation/viewmodels/stop_selection_viewmodel.dart';
import 'package:kagi_bus/presentation/views/stop_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_theme.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeScheduleViewModel extends ScheduleViewModel {
  _FakeScheduleViewModel(this._master);
  final List<BusStop> _master;

  @override
  Future<ScheduleResult> build() async => ScheduleResult(
        data: ScheduleResponse(
          updatedAt: '2024-01-01',
          stopMaster: _master,
          current: const BusTimetable(
            validFrom: '2024-01-01',
            validTo: '2024-12-31',
            schedules: [],
          ),
        ),
      );
}

/// select() の副作用（scheduleViewModelProvider の invalidate）を持ち込まずに
/// 選択の変化だけを見る。再取得そのものは stop_selection_viewmodel_test で検証する。
class _FakeStopSelectionNotifier extends StopSelectionNotifier {
  _FakeStopSelectionNotifier(this._initial);
  final StopSelection _initial;

  final selected = <StopSelection>[];

  @override
  Future<StopSelection> build() async => _initial;

  @override
  Future<void> select(StopSelection selection) async {
    selected.add(selection);
    state = AsyncData(selection);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _master = [
  BusStop(id: 'chitose', label: '千歳駅前', shortLabel: '千歳駅'),
  BusStop(id: 'minamiChitose', label: '南千歳駅', shortLabel: '南千歳'),
  BusStop(id: 'morimoto', label: 'もりもと本店前'),
  BusStop(id: 'rapidus', label: 'ラピダス前', boardable: false),
  BusStop(id: 'kenkyuto', label: '科技大研究棟', shortLabel: '研究棟'),
  BusStop(id: 'honbuto', label: '科技大本部棟', shortLabel: '本部棟'),
];

Widget _wrap({
  required _FakeStopSelectionNotifier selection,
  List<BusStop> master = _master,
}) {
  return ProviderScope(
    overrides: [
      stopSelectionProvider.overrideWith(() => selection),
      scheduleViewModelProvider
          .overrideWith(() => _FakeScheduleViewModel(master)),
    ],
    child: MaterialApp(
      theme: buildTestTheme(),
      home: const StopSettingsScreen(),
    ),
  );
}

_FakeStopSelectionNotifier _sel([List<String>? ids]) =>
    _FakeStopSelectionNotifier(
        ids == null ? StopSelection.initial : StopSelection(stopIds: ids));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StopSettingsScreen', () {
    testWidgets('選択中の停留所が正式名で並ぶ', (tester) async {
      await tester.pumpWidget(_wrap(selection: _sel(['chitose', 'honbuto'])));
      await tester.pumpAndSettle();

      expect(find.text('千歳駅前'), findsOneWidget);
      expect(find.text('科技大本部棟'), findsOneWidget);
      // タブでの見え方が正式名と違うことは添える
      expect(find.text('タブ表示: 千歳駅'), findsOneWidget);
    });

    testWidgets('未選択の停留所が「追加する」に出る', (tester) async {
      await tester.pumpWidget(_wrap(selection: _sel(['chitose'])));
      await tester.pumpAndSettle();

      expect(find.text('もりもと本店前'), findsOneWidget);
      expect(find.text('科技大研究棟'), findsOneWidget);
    });

    testWidgets('boardable=false の停留所は選択肢に出ない', (tester) async {
      await tester.pumpWidget(_wrap(selection: _sel(['chitose'])));
      await tester.pumpAndSettle();

      // ラピダス前は工場敷地内で一般利用できない
      expect(find.text('ラピダス前'), findsNothing);
    });

    testWidgets('タップで追加され、末尾に入る', (tester) async {
      final selection = _sel(['chitose']);
      await tester.pumpWidget(_wrap(selection: selection));
      await tester.pumpAndSettle();

      await tester.tap(find.text('もりもと本店前'));
      await tester.pumpAndSettle();

      expect(selection.selected.last.stopIds, ['chitose', 'morimoto']);
      // 追加した停留所は選択肢から消える
      expect(find.widgetWithIcon(ListTile, Icons.add), findsNWidgets(3));
    });

    testWidgets('外すと選択から消え、「追加する」に戻る', (tester) async {
      final selection = _sel(['chitose', 'honbuto']);
      await tester.pumpWidget(_wrap(selection: selection));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
      await tester.pumpAndSettle();

      expect(selection.selected.last.stopIds, ['honbuto']);
      expect(find.text('千歳駅前'), findsOneWidget); // 「追加する」側に移った
      expect(find.text('タブ表示: 千歳駅'), findsNothing);
    });

    testWidgets('最後の1つは外せない（0個だと時刻表が出せなくなるため）', (tester) async {
      final selection = _sel(['chitose']);
      await tester.pumpWidget(_wrap(selection: selection));
      await tester.pumpAndSettle();

      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.remove_circle_outline),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pumpAndSettle();

      expect(selection.selected, isEmpty);
    });

    testWidgets('並べ替えると順序が保存される', (tester) async {
      final selection = _sel(['chitose', 'minamiChitose', 'honbuto']);
      await tester.pumpWidget(_wrap(selection: selection));
      await tester.pumpAndSettle();

      // 先頭（千歳駅前）を長押しして最後尾までドラッグする。
      // ReorderableListView は移動のたびに入れ替えを判定するので、
      // 一息に動かさず刻んで運ぶ
      final handle = find.byIcon(Icons.drag_handle).first;
      final drag = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(seconds: 1));
      for (var i = 0; i < 10; i++) {
        await drag.moveBy(const Offset(0, 20));
        await tester.pump();
      }
      await drag.up();
      await tester.pumpAndSettle();

      expect(selection.selected.last.stopIds,
          ['minamiChitose', 'honbuto', 'chitose']);
    });

    testWidgets('stopMaster が空: 取得できていない旨を出す', (tester) async {
      await tester.pumpWidget(_wrap(selection: _sel(), master: const []));
      await tester.pumpAndSettle();

      expect(find.textContaining('停留所の一覧を取得できていません'), findsOneWidget);
      expect(find.byType(ReorderableListView), findsNothing);
    });

    testWidgets('stopMaster に無い ID は ID のまま出し、外せる', (tester) async {
      // GAS から停留所が消えても選択に残る。名前が引けなくても操作はできる
      final selection = _sel(['chitose', 'ghost']);
      await tester.pumpWidget(_wrap(selection: selection));
      await tester.pumpAndSettle();

      expect(find.text('ghost'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.remove_circle_outline).last);
      await tester.pumpAndSettle();

      expect(selection.selected.last.stopIds, ['chitose']);
    });
  });
}
