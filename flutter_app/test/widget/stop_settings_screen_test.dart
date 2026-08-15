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
/// 適用の呼び出しだけを見る。再取得そのものは stop_selection_viewmodel_test で検証する。
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

/// 設定画面から push して開く。戻る操作を試すため、下に別の画面を置いておく
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
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StopSettingsScreen()),
              ),
              child: const Text('開く'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester,
    {required _FakeStopSelectionNotifier selection,
    List<BusStop> master = _master}) async {
  await tester.pumpWidget(_wrap(selection: selection, master: master));
  await tester.pumpAndSettle();
  await tester.tap(find.text('開く'));
  await tester.pumpAndSettle();
}

_FakeStopSelectionNotifier _sel([List<String>? ids]) =>
    _FakeStopSelectionNotifier(
        ids == null ? StopSelection.initial : StopSelection(stopIds: ids));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StopSettingsScreen 表示', () {
    testWidgets('選択中の停留所が正式名で並ぶ', (tester) async {
      await _open(tester, selection: _sel(['chitose', 'honbuto']));

      expect(find.text('千歳駅前'), findsOneWidget);
      expect(find.text('科技大本部棟'), findsOneWidget);
      // タブでの見え方が正式名と違うことは添える
      expect(find.text('タブ表示: 千歳駅'), findsOneWidget);
    });

    testWidgets('未選択の停留所が「追加する」に出る', (tester) async {
      await _open(tester, selection: _sel(['chitose']));

      expect(find.text('もりもと本店前'), findsOneWidget);
      expect(find.text('科技大研究棟'), findsOneWidget);
    });

    testWidgets('boardable=false の停留所は選択肢に出ない', (tester) async {
      await _open(tester, selection: _sel(['chitose']));

      // ラピダス前は工場敷地内で一般利用できない
      expect(find.text('ラピダス前'), findsNothing);
    });

    testWidgets('stopMaster が空: 取得できていない旨を出す', (tester) async {
      await _open(tester, selection: _sel(), master: const []);

      expect(find.textContaining('停留所の一覧を取得できていません'), findsOneWidget);
      expect(find.byType(ReorderableListView), findsNothing);
    });

    testWidgets('stopMaster に無い ID は ID のまま出す', (tester) async {
      // GAS から停留所が消えても選択に残る。名前が引けなくても操作はできる
      await _open(tester, selection: _sel(['chitose', 'ghost']));

      expect(find.text('ghost'), findsOneWidget);
    });
  });

  group('StopSettingsScreen 下書きと適用', () {
    testWidgets('編集しても「適用」を押すまで反映しない', (tester) async {
      final selection = _sel(['chitose']);
      await _open(tester, selection: selection);

      await tester.tap(find.text('もりもと本店前'));
      await tester.pumpAndSettle();

      // 画面上は足されているが、まだ select() は呼ばれていない
      expect(find.text('「適用」を押すと時刻表を取り直します'), findsOneWidget);
      expect(selection.selected, isEmpty);

      await tester.tap(find.text('適用'));
      await tester.pumpAndSettle();

      expect(selection.selected.single.stopIds, ['chitose', 'morimoto']);
    });

    testWidgets('適用すると画面を閉じる', (tester) async {
      final selection = _sel(['chitose']);
      await _open(tester, selection: selection);

      await tester.tap(find.text('もりもと本店前'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('適用'));
      await tester.pumpAndSettle();

      expect(find.byType(StopSettingsScreen), findsNothing);
      expect(find.text('開く'), findsOneWidget);
    });

    testWidgets('複数の編集をまとめて1回だけ適用する', (tester) async {
      final selection = _sel(['chitose']);
      await _open(tester, selection: selection);

      await tester.tap(find.text('もりもと本店前'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('科技大研究棟'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('科技大本部棟'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('適用'));
      await tester.pumpAndSettle();

      // 3回足しても取り直しは1回
      expect(selection.selected, hasLength(1));
      expect(selection.selected.single.stopIds,
          ['chitose', 'morimoto', 'kenkyuto', 'honbuto']);
    });

    testWidgets('編集していなければ「適用」は押せない', (tester) async {
      await _open(tester, selection: _sel(['chitose', 'honbuto']));

      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '適用'),
      );
      expect(button.onPressed, isNull);
      expect(find.text('「適用」を押すと時刻表を取り直します'), findsNothing);
    });

    testWidgets('外すと下書きから消え、「追加する」に戻る', (tester) async {
      final selection = _sel(['chitose', 'honbuto']);
      await _open(tester, selection: selection);

      await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
      await tester.pumpAndSettle();

      expect(find.text('千歳駅前'), findsOneWidget); // 「追加する」側に移った
      expect(find.text('タブ表示: 千歳駅'), findsNothing);

      await tester.tap(find.text('適用'));
      await tester.pumpAndSettle();
      expect(selection.selected.single.stopIds, ['honbuto']);
    });

    testWidgets('最後の1つは外せない（0個だと時刻表が出せなくなるため）', (tester) async {
      final selection = _sel(['chitose']);
      await _open(tester, selection: selection);

      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.remove_circle_outline),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pumpAndSettle();

      expect(find.text('千歳駅前'), findsOneWidget);
      expect(selection.selected, isEmpty);
    });

    testWidgets('並べ替えると順序が下書きに入り、適用で保存される', (tester) async {
      final selection = _sel(['chitose', 'minamiChitose', 'honbuto']);
      await _open(tester, selection: selection);

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

      expect(selection.selected, isEmpty);

      await tester.tap(find.text('適用'));
      await tester.pumpAndSettle();

      expect(selection.selected.single.stopIds,
          ['minamiChitose', 'honbuto', 'chitose']);
    });
  });

  group('StopSettingsScreen 適用せずに戻る', () {
    testWidgets('未適用の変更があると確認を出し、「編集に戻る」で留まる', (tester) async {
      final selection = _sel(['chitose']);
      await _open(tester, selection: selection);

      await tester.tap(find.text('もりもと本店前'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('変更を破棄しますか'), findsOneWidget);

      await tester.tap(find.text('編集に戻る'));
      await tester.pumpAndSettle();

      expect(find.byType(StopSettingsScreen), findsOneWidget);
      expect(selection.selected, isEmpty);
    });

    testWidgets('「破棄」を選ぶと反映せずに閉じる', (tester) async {
      final selection = _sel(['chitose']);
      await _open(tester, selection: selection);

      await tester.tap(find.text('もりもと本店前'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('破棄'));
      await tester.pumpAndSettle();

      expect(find.byType(StopSettingsScreen), findsNothing);
      expect(selection.selected, isEmpty);
    });

    testWidgets('編集していなければ確認を出さずに閉じる', (tester) async {
      await _open(tester, selection: _sel(['chitose', 'honbuto']));

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('変更を破棄しますか'), findsNothing);
      expect(find.byType(StopSettingsScreen), findsNothing);
    });
  });

  // 上限が無いと乗車可能な30停留所すべてをタブにでき、1タブ約 12.5px になって
  // 名前も星も判別できない（#204）
  group('StopSettingsScreen 選択数の上限', () {
    // 上限（6）まで選んでもまだ余る数のマスタ
    const master = [
      BusStop(id: 'chitose', label: '千歳駅前', shortLabel: '千歳駅'),
      BusStop(id: 'minamiChitose', label: '南千歳駅', shortLabel: '南千歳'),
      BusStop(id: 'morimoto', label: 'もりもと本店前'),
      BusStop(id: 'shiyakusho', label: '市役所前'),
      BusStop(id: 'aeon', label: 'イオン千歳店前'),
      BusStop(id: 'kenkyuto', label: '科技大研究棟', shortLabel: '研究棟'),
      BusStop(id: 'honbuto', label: '科技大本部棟', shortLabel: '本部棟'),
    ];

    const full = [
      'chitose',
      'minamiChitose',
      'kenkyuto',
      'honbuto',
      'morimoto',
      'shiyakusho',
    ];

    /// 上限まで並べると既定の 600px に収まらず、タップ対象が画面外になる
    Future<void> open(
      WidgetTester tester,
      _FakeStopSelectionNotifier selection,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _open(tester, selection: selection, master: master);
    }

    testWidgets('見出しに 選択数 / 上限 が出る', (tester) async {
      // 押せなくなってから知らせるのでは遅いので、達する前から見せる
      await open(tester, _sel(['chitose', 'honbuto']));

      expect(find.text('タブに表示する（2 / ${StopSelection.maxStops}）'),
          findsOneWidget);
    });

    testWidgets('上限未満なら「追加する」に候補が出る', (tester) async {
      await open(tester, _sel(full.take(StopSelection.maxStops - 1).toList()));

      expect(find.text('イオン千歳店前'), findsOneWidget);
      expect(find.textContaining('件までです'), findsNothing);
    });

    testWidgets('上限に達すると候補が消え、外すよう促す', (tester) async {
      await open(tester, _sel(full));

      expect(
          find.text(
              'タブに表示する（${StopSelection.maxStops} / ${StopSelection.maxStops}）'),
          findsOneWidget);
      expect(find.textContaining('${StopSelection.maxStops} 件までです'),
          findsOneWidget);
      // 未選択だが候補として出さない
      expect(find.text('イオン千歳店前'), findsNothing);
    });

    testWidgets('上限で1つ外すと再び追加できる', (tester) async {
      final selection = _sel(full);
      await open(tester, selection);

      await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
      await tester.pumpAndSettle();

      expect(find.textContaining('件までです'), findsNothing);
      expect(find.text('イオン千歳店前'), findsOneWidget);

      await tester.tap(find.text('イオン千歳店前'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('適用'));
      await tester.pumpAndSettle();

      expect(selection.selected.single.stopIds.length,
          StopSelection.maxStops);
      expect(selection.selected.single.stopIds, contains('aeon'));
    });
  });
}
