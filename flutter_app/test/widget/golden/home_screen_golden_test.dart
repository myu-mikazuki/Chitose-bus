import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';
import 'package:kagi_bus/domain/entities/stop_selection.dart';
import 'package:kagi_bus/presentation/viewmodels/banner_ad_viewmodel.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_result.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_viewmodel.dart';
import 'package:kagi_bus/presentation/viewmodels/stop_selection_viewmodel.dart';
import 'package:kagi_bus/presentation/views/home_screen.dart';
import 'package:kagi_bus/presentation/views/widgets/offline_cache_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_view_models.dart';
import '../../helpers/test_theme.dart';

// タブの骨格（_StopTab）を固定するための golden。単体の golden は
// NextBusCard / ScheduleList しか覆っておらず、タブの組み立てを差し替える変更が
// 検知できなかった（#192、PR #189 で実際に 8px の余白変化を取りこぼした）。
//
// タブの中身は同じ階層で4通りに分かれる。1枚ずつ押さえる。
//
// | 状態 | 出るもの |
// |---|---|
// | 行き先1つ | _StopTab（SegmentedButton なし） |
// | 行き先2つ以上 | _StopTab（SegmentedButton あり） |
// | 便が1本も無い | _StopHasNoBus |
// | キャッシュに無い | _StopNotFetched |
//
// 後ろ2つの**振る舞い**は home_screen_test で押さえてある。ここで足すのは
// 見た目の固定だけ（#220）。

// kTestNow は 2024-06-17（月）09:00。すべて未来の便にして、どのタブでも
// NEXT BUS が「次のバスなし」に落ちないようにする。過去便を混ぜると
// カウントダウンではなく空状態が写り、骨格ではなく状態の golden になる。
const _schedules = [
  BusEntry(
    time: '09:30',
    boardingStopId: 'chitose',
    destination: '科技大',
    terminusStopId: 'honbuto',
    arrivals: {
      'minamiChitose': '09:41',
      'kenkyuto': '09:54',
      'honbuto': '09:55'
    },
  ),
  // 研究棟に行き先を2つ持たせる（SegmentedButton が出る条件）
  BusEntry(
    time: '09:20',
    boardingStopId: 'kenkyuto',
    destination: '科技大',
    terminusStopId: 'honbuto',
    arrivals: {'honbuto': '09:23'},
  ),
  BusEntry(
    time: '09:40',
    boardingStopId: 'kenkyuto',
    destination: '千歳駅',
    terminusStopId: 'chitose',
    arrivals: {'chitose': '10:00'},
  ),
];

/// golden 4枚の土台。**違うところだけを引数で渡す。**
///
/// `ScheduleResponse` は freezed ではないので copyWith が無く、丸ごと書くと
/// 複製が並ぶ。片方にだけ `updatedAt` や `upcoming` を足したときに
/// golden どうしの前提が黙ってずれるのを防ぐため、1箇所にまとめている。
ScheduleResult _resultWith({
  List<String> coveredStopIds = const [],
  bool isFromCache = false,
}) =>
    ScheduleResult(
      isFromCache: isFromCache,
      data: ScheduleResponse(
        stopMaster: kTestStopMaster,
        updatedAt: '2024-01-01',
        coveredStopIds: coveredStopIds,
        current: BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-12-31',
          schedules: _schedules,
        ),
      ),
    );

final _result = _resultWith();

/// 本部棟の時刻を持たないキャッシュ。オフラインで停留所を足すと起きる状態で、
/// `covers()` が false になったタブに `_StopNotFetched` が出る。
///
/// **`isFromCache` は落とさない。** `_StopNotFetched` が出る経路は2つあり、
/// バナーの有無が変わる。
///
/// | 経路 | isFromCache | 覆えないのは |
/// |---|---|---|
/// | キャッシュ返却（`build()` / `refresh()`） | true（バナーあり） | 足した停留所 |
/// | 旧形式応答（GAS 未デプロイ・#201） | false（バナーなし） | 足した停留所 |
///
/// **この fixture が写せるのは前者だけ。** 旧形式応答が覆えないのは既定の4停留所の
/// 外だけなので、本部棟を外したこの形は旧形式では起こらない。落とすと、
/// どちらの経路にも無い組み合わせを焼くことになる。
///
/// 目に触れるのも大半はキャッシュ経路（旧形式は GAS をロールバックした間だけ）
/// なので、バナー込みの縦の積み方まで固定する。
///
/// 既定の4停留所から選ぶので、タブのラベルは日本語のまま（`morimoto` のように
/// ID が出ると、この golden がラベルの見た目まで巻き込む）。
final _partiallyCoveredResult = _resultWith(
  coveredStopIds: const ['chitose', 'minamiChitose', 'kenkyuto'],
  isFromCache: true,
);

Future<void> _pumpHomeScreen(WidgetTester tester,
    {ScheduleResult? result}) async {
  // 375x812（iPhone X 相当）に固定する。既定の4タブが縮小経路に入らない幅。
  // 既存の golden 2ファイルと同じ setSurfaceSize を使う。matchesGoldenFile は
  // 論理サイズで 1:1 に切り出すので、dpr を触っても PNG の解像度は変わらない。
  await tester.binding.setSurfaceSize(const Size(375, 812));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        scheduleViewModelProvider
            .overrideWith(() => FakeScheduleViewModel(result ?? _result)),
        stopSelectionProvider.overrideWith(
            () => FakeStopSelectionNotifier(StopSelection.initial)),
        countdownOverride(),
        // 広告は golden の対象外。読み込み結果が環境で変わるうえ、テストには
        // プラグインの実装が無いため（#192）
        bannerAdBuilderProvider
            .overrideWithValue((_) => const SizedBox.shrink()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTestTheme(),
        home: const HomeScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// [label] のタブを開く。
///
/// **必ず TabBar 配下に絞る。** 停留所の短縮名は見出し（`→ 本部棟`）や到着行にも
/// 出るので、素の `find.text` は画面の作りが変わった途端に複数当たる。
/// 一意な停留所でも揃えておくと、壊れたときに golden 不一致ではなく
/// 「タップ先が一意でない」として原因が読める形で落ちる。
Future<void> _tapStopTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(
    of: find.byType(TabBar),
    matching: find.text(label),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('既定の4タブ構成・行き先が1つのタブ（千歳駅）', (tester) async {
    await _pumpHomeScreen(tester);

    // 起動直後に開くのは先頭の千歳駅タブ。行き先は本部棟のみなので
    // SegmentedButton は出ない
    expect(find.byType(SegmentedButton<String>), findsNothing);

    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_screen_default.png'),
    );
  });

  testWidgets('行き先が複数あるタブ（研究棟・SegmentedButton あり）', (tester) async {
    await _pumpHomeScreen(tester);

    await _tapStopTab(tester, '研究棟');

    // この golden の主題。出ていなければ骨格を固定できていない
    expect(find.byType(SegmentedButton<String>), findsOneWidget);

    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_screen_multi_destination.png'),
    );
  });

  testWidgets('便が1本も無いタブ（南千歳）', (tester) async {
    await _pumpHomeScreen(tester);

    // 南千歳を発つ便が _schedules に無いので、降り先が引けない。
    // 取得はできているので「取得できていません」ではない
    await _tapStopTab(tester, '南千歳');

    // この golden の主題。出ていなければ別の状態を写している
    expect(find.textContaining('もう1つ選んでください'), findsOneWidget);
    expect(find.textContaining('まだ取得できていません'), findsNothing);

    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_screen_no_bus.png'),
    );
  });

  testWidgets('キャッシュに無いタブ（本部棟・取得できていません）', (tester) async {
    await _pumpHomeScreen(tester, result: _partiallyCoveredResult);

    await _tapStopTab(tester, '本部棟');

    // この golden の主題。「再試行」まで含めて骨格
    expect(find.textContaining('このバス停の時刻はまだ取得できていません'), findsOneWidget);
    expect(find.text('再試行'), findsOneWidget);
    expect(find.textContaining('もう1つ選んでください'), findsNothing);
    // キャッシュ経路なので、実機と同じくバナーが上に乗る
    expect(find.byType(OfflineCacheBanner), findsOneWidget);

    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_screen_not_fetched.png'),
    );
  });
}
