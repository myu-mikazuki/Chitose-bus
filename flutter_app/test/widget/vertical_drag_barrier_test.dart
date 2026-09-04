import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/core/theme/text_scale.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';
import 'package:kagi_bus/domain/entities/stop_selection.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_result.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_viewmodel.dart';
import 'package:kagi_bus/presentation/viewmodels/stop_selection_viewmodel.dart';
import 'package:kagi_bus/presentation/views/home_screen.dart';
import 'package:kagi_bus/presentation/views/widgets/schedule_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_view_models.dart';
import '../helpers/test_theme.dart';

/// #260: 縦にスクロールしようとすると横（タブ）にスワイプされる、の再現・回帰テスト。
///
/// ## 診断（issue #260 本文・修正の前提として渡された内容）
///
/// `TabBarView`（内部は `PageView`）は `HorizontalDragGestureRecognizer` を持つ。
/// ジェスチャーアリーナに縦の recognizer が1つも居ないと、横の recognizer が
/// 唯一のメンバーになり、アリーナ close の時点で無条件に勝つ。修正前は縦ドラッグ
/// バリア（`_wrapVerticalDragBarrier`）が `_StopTab` の内側2箇所
/// （NEXT BUS カード・時刻表リスト）にしか掛かっておらず、
/// `SegmentedButton` の周り・見出しの行・フッタの余白のような**そもそもバリア
/// の対象外の場所**を起点にしたドラッグでは横に取られていた。
///
/// ## このファイルが立てる主張（**必ず斜めドラッグで確認する**）
///
/// `dx = 0` の純粋な縦ドラッグは修正前でも通ってしまう（横方向の recognizer が
/// そもそも反応しない）ため、**すべて横成分を含む斜めドラッグ**で確認する。
///
/// 1. 等倍で、フッタ／見出しの**余白**（文字の上ではない部分）を起点にした
///    斜め縦ドラッグでタブが変わらない
/// 2. 拡大 1.3 超（#240 の (c)・`useVerticalScroll` 経路）でも同じく変わらない
///    （中身が収まる場合／収まらない場合の両方）
/// 3. 等倍で、内側の `ScheduleList` は今までどおりスクロールできる
///    （バリアが内側のスクロールを壊していないこと）
/// 4. 横フリックでは今までどおりタブが切り替わる（等倍・(c) の両方）
///    ——「横スワイプでのタブ切り替えは残す」という修正方針の担保
///
/// ## タブが変わったかどうかの判定
///
/// **見出しテキストの有無では判定しない。** `TabBarView`（`PageView`）は
/// 隣接ページをキャッシュのため事前に構築していることがあり、見出しテキストが
/// ツリーに残っていても「表示中のタブ」とは限らない（実際にこの穴を踏んで
/// テストが偽の緑になったことがある）。**`TabController.index` を直接見る**
/// ことで、表示中のタブそのものを確定させる。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const stopMaster = [
    BusStop(id: 'chitose', label: '千歳駅前', shortLabel: '千歳駅'),
    BusStop(id: 'honbuto', label: '科技大本部棟', shortLabel: '本部棟'),
    BusStop(id: 'kenkyuto', label: '科技大研究棟', shortLabel: '研究棟'),
  ];

  // 時刻表リストが画面に収まらないくらいの件数を用意する（内側スクロールの
  // 主張・#260 のケース3、(c) で外側が実際にスクロールする主張・ケース2b に要る）。
  // 時間帯そのものに意味は無い
  List<BusEntry> manyEntries({
    required String boardingStopId,
    required String destination,
    required String arrivalStopId,
  }) =>
      [
        for (var h = 6; h < 21; h++)
          for (var m in [0, 20, 40])
            BusEntry(
              time: '${h.toString().padLeft(2, '0')}:'
                  '${m.toString().padLeft(2, '0')}',
              boardingStopId: boardingStopId,
              destination: destination,
              arrivals: {
                arrivalStopId:
                    '${h.toString().padLeft(2, '0')}:${(m + 5).toString().padLeft(2, '0')}',
              },
            ),
      ];

  // 研究棟だけ両方向を持たせ、SegmentedButton が出る条件（行き先2つ）を作る。
  // 「SegmentedButton の周り」の余白も #260 の穴として名指しされているため
  const kenkyutoBothWays = [
    BusEntry(
      time: '08:30',
      boardingStopId: 'kenkyuto',
      destination: '本部棟',
      terminusStopId: 'honbuto',
      arrivals: {'honbuto': '08:33'},
    ),
    BusEntry(
      time: '08:40',
      boardingStopId: 'kenkyuto',
      destination: '千歳駅',
      terminusStopId: 'chitose',
      arrivals: {'chitose': '09:00'},
    ),
  ];

  // 3停留所・盛りだくさんの時刻表（ケース 1・1b・2b・3・4a・4b・5 で使う）
  final heavyResult = ScheduleResult(
    data: ScheduleResponse(
      stopMaster: stopMaster,
      updatedAt: '2024-01-01',
      current: BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-12-31',
        schedules: [
          ...manyEntries(
              boardingStopId: 'chitose',
              destination: '科技大',
              arrivalStopId: 'honbuto'),
          ...manyEntries(
              boardingStopId: 'honbuto',
              destination: '千歳駅',
              arrivalStopId: 'chitose'),
          ...kenkyutoBothWays,
        ],
      ),
    ),
  );

  // 中身が軽い（1件ずつ）2停留所の時刻表（ケース 2a で使う）。
  // (c) の全体スクロール経路に入っても、画面に収まって `SingleChildScrollView`
  // が `setCanDrag(false)` になる（＝内側に縦の recognizer が無い）ことを狙う
  final lightResult = ScheduleResult(
    data: ScheduleResponse(
      stopMaster: stopMaster,
      updatedAt: '2024-01-01',
      current: const BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-12-31',
        schedules: [
          BusEntry(
            time: '09:00',
            boardingStopId: 'chitose',
            destination: '科技大',
            arrivals: {'honbuto': '09:30'},
          ),
          BusEntry(
            time: '09:10',
            boardingStopId: 'honbuto',
            destination: '千歳駅',
            arrivals: {'chitose': '09:40'},
          ),
        ],
      ),
    ),
  );

  Widget wrap({
    required ScheduleResult result,
    required List<String> stopIds,
    double scale = 1.0,
  }) =>
      ProviderScope(
        overrides: [
          scheduleViewModelProvider
              .overrideWith(() => FakeScheduleViewModel(result)),
          stopSelectionProvider.overrideWith(
            () => FakeStopSelectionNotifier(StopSelection(stopIds: stopIds)),
          ),
          countdownOverride(now: DateTime(2024, 6, 17, 8, 0)),
        ],
        child: MaterialApp(
          theme: buildTestTheme(),
          // MaterialApp の外に置いても効かない（MaterialApp が自前の
          // MediaQuery で上書きするため）。text_scaler_test.dart と同じ作法
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const HomeScreen(),
        ),
      );

  void usePhone(WidgetTester tester, {double height = 667}) {
    tester.view.physicalSize = Size(375 * 2, height * 2); // 375px 幅、論理 height
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// 表示中のタブ番号。**見出しテキストの有無では判定しない**——理由はファイル
  /// 冒頭のドキュメント参照。`TabBar` に渡した `TabController` を直接見る
  int currentTabIndex(WidgetTester tester) =>
      tester.widget<TabBar>(find.byType(TabBar)).controller!.index;

  /// 見出し行（`NEXT BUS` とタイトルの間の隙間）の**余白**の座標。文字の上では
  /// ない。(c) の全体スクロールでも常に画面の上のほうにあるので、スクロール
  /// 位置に関わらず必ず可視範囲に入る（フッタと違って安全に狙える）
  Offset headerMarginPoint(WidgetTester tester, String headerText) {
    final titleRight = tester.getTopRight(find.text('NEXT BUS'));
    final headerLeft = tester.getTopLeft(find.text(headerText));
    return Offset(
      (titleRight.dx + headerLeft.dx) / 2,
      (titleRight.dy + headerLeft.dy) / 2 + 6,
    );
  }

  /// 斜め縦ドラッグの既定量。**dx を必ず含めること**——dx=0 の純粋な縦ドラッグは
  /// 修正前でも横の recognizer がそもそも反応せず、バグを検知できない
  /// （偽の緑になる）。
  ///
  /// 縦優位（dy が dx の3倍）だが、量そのものは控えめな値（60,300）だと
  /// (c) の全体スクロール経路でだけ page の「確定」に届かず偽の緑になった
  /// （実際に踏んだ。等倍では同じ量で確実に確定する一方、(c) では確定に
  /// 必要な移動量が明らかに大きい——正確な原因は追い切れていないが、
  /// 現象としてこの量を下回ると (c) 側のテストが信用できなくなることは
  /// デバッグで確認済み）。**必ずこの量で送ること。**
  const diagonalDelta = Offset(-200, -600);

  /// 斜めドラッグを1回で送る。数ステップに分けて動かし、実際の指の動きに近づける
  Future<void> diagonalDrag(
    WidgetTester tester,
    Offset start, [
    Offset delta = diagonalDelta,
  ]) async {
    final gesture = await tester.startGesture(start);
    const steps = 10;
    for (var i = 1; i <= steps; i++) {
      await gesture.moveBy(delta / steps.toDouble());
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('#260: 縦ドラッグが横スワイプに奪われない', () {
    testWidgets('1. 等倍・フッタの余白を起点にした斜め縦ドラッグではタブが変わらない', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(wrap(
        result: heavyResult,
        stopIds: const ['chitose', 'honbuto', 'kenkyuto'],
      ));
      await tester.pumpAndSettle();

      expect(currentTabIndex(tester), 0, reason: '開始時は千歳駅タブ（index 0）');

      // フッタの「更新: ...」テキストの右肩（Padding の余白側。テキストの
      // 上ではない）を起点にする。Padding は自分自身をヒットテストしない
      // ので、この点は「文字の上ではなく何も無い余白」になる。等倍では
      // フッタは Expanded の外に固定表示されるので、常に画面内に収まる
      final footerTopRight = tester.getTopRight(find.textContaining('更新:'));
      final start = footerTopRight + const Offset(6, 2);

      await diagonalDrag(tester, start);

      expect(currentTabIndex(tester), 0, reason: '千歳駅タブのまま（index 0）');
    });

    testWidgets('1b. 等倍・見出し行の余白を起点にした斜め縦ドラッグでもタブが変わらない', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(wrap(
        result: heavyResult,
        stopIds: const ['chitose', 'honbuto', 'kenkyuto'],
      ));
      await tester.pumpAndSettle();

      final start = headerMarginPoint(tester, '千歳駅 発');

      await diagonalDrag(tester, start);

      expect(currentTabIndex(tester), 0, reason: '千歳駅タブのまま（index 0）');
    });

    testWidgets('2a. 拡大 1.3 超・中身が画面に収まる場合、見出し行の余白起点の斜め縦ドラッグでタブが変わらない',
        (tester) async {
      const scale = kVerticalScrollThreshold + 0.5;
      // 中身が「収まる」ことを狙うケースなので、代替フォントの水増し
      // （欧文・数字が実機よりかなり幅／高さを食う）を吸収できるだけ縦に
      // 余裕を持たせる。text_scaler_test.dart の「縦に余裕があれば」と同じ作法
      usePhone(tester, height: 2400);
      await tester.pumpWidget(wrap(
        result: lightResult,
        stopIds: const ['chitose', 'honbuto'],
        scale: scale,
      ));
      await tester.pumpAndSettle();

      expect(currentTabIndex(tester), 0);

      // (c) に入っている証拠
      final scrollViewFinder = find.ancestor(
        of: find.text('千歳駅 発'),
        matching: find.byType(SingleChildScrollView),
      );
      expect(scrollViewFinder, findsOneWidget, reason: '(c) の経路に入っていない');

      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(of: scrollViewFinder, matching: find.byType(Scrollable))
            .first,
      );
      // 中身が軽いので、スクロールする余地が無い（＝内側に縦の recognizer が
      // 登録されない）ことを確認しておく。これが今回の穴そのものの条件
      expect(scrollable.position.maxScrollExtent, 0,
          reason: 'このケースは「中身が収まる」ことが前提。収まっていなければ2bと同じ主張になってしまう');

      final start = headerMarginPoint(tester, '千歳駅 発');
      await diagonalDrag(tester, start);

      expect(currentTabIndex(tester), 0, reason: '千歳駅タブのまま（index 0）');
    });

    testWidgets(
        '2b. 拡大 1.3 超・中身が収まらない場合、見出し行の余白起点の斜め縦ドラッグでタブが変わらず、外側 SingleChildScrollView がスクロールする',
        (tester) async {
      const scale = kVerticalScrollThreshold + 0.5;
      usePhone(tester);
      await tester.pumpWidget(wrap(
        result: heavyResult,
        stopIds: const ['chitose', 'honbuto', 'kenkyuto'],
        scale: scale,
      ));
      await tester.pumpAndSettle();

      expect(currentTabIndex(tester), 0);

      final scrollViewFinder = find.ancestor(
        of: find.text('千歳駅 発'),
        matching: find.byType(SingleChildScrollView),
      );
      expect(scrollViewFinder, findsOneWidget, reason: '(c) の経路に入っていない');

      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(of: scrollViewFinder, matching: find.byType(Scrollable))
            .first,
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0),
          reason: 'このケースは「中身が収まらない」ことが前提。収まっていれば2aと同じ主張になってしまう');
      final before = scrollable.position.pixels;

      final start = headerMarginPoint(tester, '千歳駅 発');
      await diagonalDrag(tester, start);

      expect(currentTabIndex(tester), 0, reason: '千歳駅タブのまま（index 0）');
      // 「可能なら」の担保: 中身が収まらない以上、内側（外側 SingleChildScrollView
      // 自身）の recognizer がアリーナで先に勝ち、実際にスクロールしている
      expect(scrollable.position.pixels, greaterThan(before),
          reason: '外側 SingleChildScrollView が縦ドラッグを吸っているはず');
    });

    testWidgets('3. 等倍・内側の ScheduleList は今までどおりスクロールできる（バリアが壊していない）',
        (tester) async {
      usePhone(tester);
      await tester.pumpWidget(wrap(
        result: heavyResult,
        stopIds: const ['chitose', 'honbuto', 'kenkyuto'],
      ));
      await tester.pumpAndSettle();

      // 時刻表リストの中の行（文字の上）。**可視範囲に入れてから**座標を取る
      // ——そうしないと、初期表示の自動スクロール（NEXT を先頭に合わせる）で
      // 画面外に出ている行の座標を拾ってしまい、ドラッグが何にも当たらない
      final row = find
          .descendant(of: find.byType(ScheduleList), matching: find.text('科技大'))
          .first;
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();

      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
                of: find.byType(ScheduleList),
                matching: find.byType(Scrollable))
            .first,
      );
      final before = scrollable.position.pixels;

      await diagonalDrag(
        tester,
        tester.getCenter(row) + const Offset(20, 0),
        const Offset(-30, -300),
      );

      expect(scrollable.position.pixels, greaterThan(before),
          reason: '時刻表リストがスクロールしていない（内側のスクロールを壊した）');
      // タブも変わっていない
      expect(currentTabIndex(tester), 0);
    });

    testWidgets('4a. 等倍・横フリックでタブが切り替わる（横スワイプでの切り替えは残す）', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(wrap(
        result: heavyResult,
        stopIds: const ['chitose', 'honbuto', 'kenkyuto'],
      ));
      await tester.pumpAndSettle();

      expect(currentTabIndex(tester), 0);

      final start = headerMarginPoint(tester, '千歳駅 発');
      await tester.flingFrom(start, const Offset(-300, -10), 1500);
      await tester.pumpAndSettle();

      expect(currentTabIndex(tester), 1, reason: '横フリックでタブが切り替わっていない');
    });

    testWidgets('4b. 拡大 1.3 超（(c)）でも横フリックでタブが切り替わる', (tester) async {
      const scale = kVerticalScrollThreshold + 0.5;
      usePhone(tester);
      await tester.pumpWidget(wrap(
        result: heavyResult,
        stopIds: const ['chitose', 'honbuto', 'kenkyuto'],
        scale: scale,
      ));
      await tester.pumpAndSettle();

      expect(currentTabIndex(tester), 0);

      final start = headerMarginPoint(tester, '千歳駅 発');
      await tester.flingFrom(start, const Offset(-300, -10), 1500);
      await tester.pumpAndSettle();

      expect(currentTabIndex(tester), 1, reason: '横フリックでタブが切り替わっていない');
    });

    testWidgets('5. SegmentedButton の周りの余白を起点にした斜め縦ドラッグでもタブが変わらない（研究棟タブ）',
        (tester) async {
      usePhone(tester);
      await tester.pumpWidget(wrap(
        result: heavyResult,
        stopIds: const ['chitose', 'honbuto', 'kenkyuto'],
      ));
      await tester.pumpAndSettle();

      // 研究棟タブ（index 2）へ切り替える（行き先2つなので SegmentedButton が出る）
      await tester.tap(find.descendant(
        of: find.byType(TabBar),
        matching: find.text('研究棟'),
      ));
      await tester.pumpAndSettle();
      expect(currentTabIndex(tester), 2);

      final segmented = find.byType(SegmentedButton<String>);
      expect(segmented, findsOneWidget);

      // SegmentedButton の右、余白部分を起点にする（文字の上ではない）
      final topRight = tester.getTopRight(segmented);
      final start = Offset(topRight.dx + 40, topRight.dy + 8);

      // 研究棟はタブの最後尾（index 2）。**dx は正方向（右スワイプ）で送る**
      // ——左スワイプは「次のタブへ」の向きだが最後尾には次が無く、
      // バリアの有無に関わらず境界でクランプされて動かないため主張にならない
      // （実際に踏んだ）。右スワイプなら本部棟（index 1）へ「戻る」向きがあるので、
      // バグがあれば実際に戻ってしまう
      await diagonalDrag(
          tester, start, Offset(-diagonalDelta.dx, diagonalDelta.dy));

      expect(currentTabIndex(tester), 2, reason: '研究棟タブのまま（index 2）');
    });
  });
}
