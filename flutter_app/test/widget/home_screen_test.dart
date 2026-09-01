import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';
import 'package:kagi_bus/domain/entities/favorite_tab.dart';
import 'package:kagi_bus/domain/entities/stop_selection.dart';
import 'package:kagi_bus/presentation/viewmodels/favorite_tab_viewmodel.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_result.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_viewmodel.dart';
import 'package:kagi_bus/presentation/viewmodels/stop_selection_viewmodel.dart';
import 'package:kagi_bus/presentation/views/home_screen.dart';
import 'package:kagi_bus/presentation/views/widgets/offline_cache_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_view_models.dart';
import '../helpers/test_theme.dart';

// ---------------------------------------------------------------------------
// Fake ViewModels
//
// 決まった結果を返す / ロード中 / 投げる、の3つは helpers/ にある
// （FakeScheduleViewModel・FakeLoadingScheduleViewModel・
// FakeErrorScheduleViewModel、#219 #223）
//
// ここに残しているのは**非同期の進み方そのものを操るもの**だけ。共有版は
// どれも「build() が何を返すか」しか変えられないので、途中経過は作れない。
// ---------------------------------------------------------------------------

class _FakeFavoriteTabNotifier extends FavoriteTabNotifier {
  final FavoriteTab _initial;
  String? lastToggleStopId;

  _FakeFavoriteTabNotifier(this._initial);

  @override
  Future<FavoriteTab> build() async => _initial;

  @override
  Future<void> toggleFavorite(String stopId) async {
    lastToggleStopId = stopId;
    final current = state.value!;
    state = AsyncData(
      current.stopId == stopId
          ? const FavoriteTab()
          : FavoriteTab(stopId: stopId),
    );
  }
}

/// スケジュールの解決を外部から制御できる VM。
/// favoriteTabProvider が先に解決した後に scheduleAsync が解決するシナリオを再現する。
///
/// **helpers に寄せられない。** 共有版は解決済みかロード中かのどちらかで、
/// 「いつ解決するか」を外から決められない（#223）。
class _DelayedScheduleViewModel extends ScheduleViewModel {
  _DelayedScheduleViewModel(this._result);

  final ScheduleResult _result;
  final _completer = Completer<void>();

  void complete() => _completer.complete();

  @override
  Future<ScheduleResult> build() async {
    await _completer.future;
    return _result;
  }

  @override
  Future<void> refresh() async {}
}

/// refresh() が本物と同じく AsyncLoading を入れる VM。
/// 入れたきり解決しないので、更新中のままの画面を確かめられる。
///
/// **helpers に寄せられない。** 共有版の `refresh()` は呼ばれたことを数えるだけで
/// state を触らない。ここが要るのは**更新中という途中の state** そのもの（#223）。
class _RefreshableViewModel extends ScheduleViewModel {
  _RefreshableViewModel(this._result);
  final ScheduleResult _result;

  @override
  Future<ScheduleResult> build() async => _result;

  @override
  Future<void> refresh() async {
    state = const AsyncLoading();
  }

  void fail() => state = AsyncError(Exception('test error'), StackTrace.empty);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _emptyTimetable = BusTimetable(
  validFrom: '2024-01-01',
  validTo: '2024-03-31',
  schedules: _kenkyutoBothWays,
);

final _mockResponse = ScheduleResult(
  data: ScheduleResponse(
    stopMaster: _stopMaster,
    updatedAt: '2024-01-01',
    current: _emptyTimetable,
  ),
);

final _mockResponseWithUpcoming = ScheduleResult(
  data: ScheduleResponse(
    stopMaster: _stopMaster,
    updatedAt: '2024-01-01',
    current: _emptyTimetable,
    upcoming: BusTimetable(
      validFrom: '2024-04-01',
      validTo: '2024-06-30',
      schedules: const [],
    ),
  ),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// 行き先の選択肢はデータから導くため、研究棟から両方向の便が要る。
// 既定で開くのは千歳駅タブなので、そちらにも1便入れておく
// （便が1本も無い停留所は _StopHasNoBus になり、見出しごと出なくなる）
const _kenkyutoBothWays = [
  BusEntry(
    time: '08:30',
    boardingStopId: 'chitose',
    destination: '科技大',
    terminusStopId: 'honbuto',
    arrivals: {'kenkyuto': '08:54', 'honbuto': '08:55'},
  ),
  BusEntry(
    time: '09:00',
    boardingStopId: 'kenkyuto',
    destination: '科技大',
    arrivals: {'honbuto': '09:03'},
  ),
  BusEntry(
    time: '09:10',
    boardingStopId: 'kenkyuto',
    destination: '千歳駅',
    arrivals: {'chitose': '09:30'},
  ),
];

const _stopMaster = [
  BusStop(id: 'chitose', label: '千歳駅前', shortLabel: '千歳駅'),
  BusStop(id: 'minamiChitose', label: '南千歳駅', shortLabel: '南千歳'),
  BusStop(id: 'kenkyuto', label: '科技大研究棟', shortLabel: '研究棟'),
  BusStop(id: 'honbuto', label: '科技大本部棟', shortLabel: '本部棟'),
];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('HomeScreen', () {
    testWidgets('loading状態: CircularProgressIndicatorが表示される', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scheduleViewModelProvider
                .overrideWith(() => FakeLoadingScheduleViewModel()),
            countdownOverride(),
          ],
          child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
        ),
      );

      // Don't pump further — the loading future never completes
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('error状態: 「エラー:」テキストと「再試行」ボタンが表示される', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scheduleViewModelProvider.overrideWith(
                () => FakeErrorScheduleViewModel(Exception('test error'))),
            countdownOverride(),
          ],
          child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
        ),
      );
      await tester.pump(); // let the failed future resolve

      expect(find.textContaining('エラー:'), findsOneWidget);
      expect(find.text('再試行'), findsOneWidget);
    });

    testWidgets('error状態で「再試行」タップ: refreshが呼ばれる', (tester) async {
      final vm = FakeErrorScheduleViewModel(Exception('test error'));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scheduleViewModelProvider.overrideWith(() => vm),
            countdownOverride(),
          ],
          child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
        ),
      );
      await tester.pump(); // let the failed future resolve

      await tester.tap(find.text('再試行'));
      await tester.pump();

      expect(vm.refreshCalled, isTrue);
    });

    testWidgets('data状態: 4つのタブ（千歳駅・南千歳・研究棟・本部棟）が表示される', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scheduleViewModelProvider
                .overrideWith(() => FakeScheduleViewModel(_mockResponse)),
            countdownOverride(),
          ],
          child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('千歳駅'), findsOneWidget);
      expect(find.text('南千歳'), findsOneWidget);
      expect(find.text('研究棟'), findsOneWidget);
      expect(find.text('本部棟'), findsOneWidget);
    });

    group('停留所名が届くまでのタブ', () {
      // 停留所名の供給元は GAS の stopMaster だけなので、初回起動では応答が
      // 届くまで出せる名前が無い。ID をそのまま出すとタブに chitose などの
      // 英字が並ぶ（#177）
      testWidgets('取得前は停留所の ID を出さない', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => FakeLoadingScheduleViewModel()),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );

        for (final id in StopSelection.initial.stopIds) {
          expect(find.text(id), findsNothing, reason: '$id が英字のまま出ている');
        }
        // タブそのものは既定の構成で組んでおく（届いたときに数が変わらない）
        expect(find.byType(Tab), findsNWidgets(4));
      });

      testWidgets('届いたら名前に入れ替わる', (tester) async {
        final scheduleVM = _DelayedScheduleViewModel(_mockResponse);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider.overrideWith(() => scheduleVM),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pump();

        expect(find.text('chitose'), findsNothing);
        expect(find.text('千歳駅'), findsNothing);

        scheduleVM.complete();
        await tester.pump();

        expect(find.text('千歳駅'), findsOneWidget);
        expect(find.text('本部棟'), findsOneWidget);
      });

      testWidgets('更新中は名前が消えない', (tester) async {
        // refresh() は state に AsyncLoading を入れる。Riverpod は直前の値を
        // 添えたまま持つ（AsyncLoading(value: ...)）ので、valueOrNull は残り、
        // 場所取りに戻らない。ここが崩れると更新のたびにタブが点滅する
        final scheduleVM = _RefreshableViewModel(_mockResponse);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider.overrideWith(() => scheduleVM),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pump();
        expect(find.text('千歳駅'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.refresh));
        await tester.pump();

        expect(find.text('千歳駅'), findsOneWidget);
      });

      // 場所取りの幅（_StopLabelPlaceholder.width）を選んだ理由がこれ。
      // タブは幅で並べ方（中央寄せ / 横並び / 縮小）を決めるので、場所取りが
      // 名前と違う幅だと、画面幅によっては名前が届いた瞬間に並べ方が切り替わり、
      // 星が跳ぶ。
      //
      // **画面幅を指定して確かめる。** 既定の 800px ではタブが広すぎて、幅が
      // どうであれ中央寄せに入り、星は右端に固定されて差が出ない。
      // 492px は中央寄せ ⇄ 横並びの境目で、幅を数 px 変えるだけで割れる
      for (final logicalWidth in [360.0, 375.0, 412.0, 492.0]) {
        testWidgets('名前に入れ替わっても星が動かない（幅 $logicalWidth）', (tester) async {
          tester.view.physicalSize = Size(logicalWidth * 2, 1334);
          tester.view.devicePixelRatio = 2.0;
          addTearDown(tester.view.reset);

          final scheduleVM = _DelayedScheduleViewModel(_mockResponse);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                scheduleViewModelProvider.overrideWith(() => scheduleVM),
                countdownOverride(),
              ],
              child: MaterialApp(
                  theme: buildTestTheme(), home: const HomeScreen()),
            ),
          );
          await tester.pump();

          final before =
              tester.getTopLeft(find.byIcon(Icons.star_border).first).dx;

          scheduleVM.complete();
          await tester.pump();

          final after =
              tester.getTopLeft(find.byIcon(Icons.star_border).first).dx;
          // 縮小経路では名前が 11px に縮むぶんだけずれる。見張っているのは
          // 並べ方で、そちらが切り替わると星は 10px 以上動く
          expect(after, closeTo(before, 6));
        });
      }

      // **拡大設定でも同じことが言えること**（#243）。
      //
      // 名前側の幅は `TextScaler` で伸びるが、場所取りは文字ではないので
      // **自動では伸びない**。片方だけ伸ばすと拡大時にだけ両者がずれ、
      // 上と同じ「名前が届いた瞬間に並べ方が切り替わって星が跳ぶ」が起きる。
      // 計測（`_buildTab`）と描画（`_StopLabelPlaceholder`）が同じ
      // `scaledWidth()` を呼ぶので、そこが崩れたらここが赤くなる。
      //
      // **幅は「並べ方が割れる窓」を狙って選んである。** 拡大すると中央寄せ ⇄
      // 横並びの境目も動くので、等倍の一覧（360〜492）をそのまま使っても
      // **両方とも縮小経路に落ちて差が出ない**（375px・1.3 では 2px 程度で、
      // 許容の 6px に収まってしまう）。1.3 では場所取りを伸ばさないと
      // **500〜530px で 7〜11px 跳ぶ**ので、そこを踏む。
      //
      // **`scaledWidth()` の拡大を外すと実際に赤くなることを確かめてある。**
      // 倍率を変えるときはこの窓も測り直すこと（窓の外だと素通りする）。
      //
      // 1.3 までしか上げないのは、1.5 で時刻表リストの行ヘッダが先に溢れ
      // （#242）、星とは無関係の理由で赤くなるため。#242 が直ったら上げてよい
      // （`text_scaler_test.dart` の表を参照）。
      for (final logicalWidth in [500.0, 530.0]) {
        testWidgets('名前に入れ替わっても星が動かない（拡大 1.3・幅 $logicalWidth・#243）',
            (tester) async {
          tester.view.physicalSize = Size(logicalWidth * 2, 1334);
          tester.view.devicePixelRatio = 2.0;
          addTearDown(tester.view.reset);

          final scheduleVM = _DelayedScheduleViewModel(_mockResponse);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                scheduleViewModelProvider.overrideWith(() => scheduleVM),
                countdownOverride(),
              ],
              child: MaterialApp(
                theme: buildTestTheme(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.3)),
                  child: child!,
                ),
                home: const HomeScreen(),
              ),
            ),
          );
          await tester.pump();

          final before =
              tester.getTopLeft(find.byIcon(Icons.star_border).first).dx;

          scheduleVM.complete();
          await tester.pump();

          final after =
              tester.getTopLeft(find.byIcon(Icons.star_border).first).dx;
          expect(after, closeTo(before, 6));
        });
      }

      // 上限（StopSelection.maxStops）そのものの妥当性を、数字ではなく描画で
      // 押さえる。375px で実測すると、ラベルに残るのは 5タブで 27.0px、
      // 6タブで 14.5px。6 では「…」だけになり、**どのタブかを名前では選べない**。
      // 上限を上げるとここが落ちる（#204 / PR #206 のレビュー指摘）
      testWidgets('上限まで選んでも、375px でタブの名前が1文字は残る', (tester) async {
        const extendedMaster = [
          ..._stopMaster,
          BusStop(id: 'morimoto', label: 'もりもと本店前'),
          BusStop(id: 'aeon', label: 'イオン千歳店前'),
        ];
        // 上限に足りるだけのマスタが要る。足りなければ上限を検算できていない
        expect(extendedMaster.length,
            greaterThanOrEqualTo(StopSelection.maxStops));

        tester.view.physicalSize = const Size(750, 1334); // 375px
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider.overrideWith(
                () => FakeScheduleViewModel(ScheduleResult(
                  data: ScheduleResponse(
                    stopMaster: extendedMaster,
                    updatedAt: '2024-01-01',
                    current: _emptyTimetable,
                  ),
                )),
              ),
              stopSelectionProvider.overrideWith(
                () => FakeStopSelectionNotifier(StopSelection(
                  stopIds: extendedMaster
                      .take(StopSelection.maxStops)
                      .map((s) => s.id)
                      .toList(),
                )),
              ),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // 短縮名を持つ停留所のうち最も短いもので測る。これが読めないなら、
        // 短縮名を持たない「古泉循環器内科クリニック前」はもっと読めない
        final label = find.descendant(
          of: find.byType(TabBar),
          matching: find.text('研究棟'),
        );
        final labelWidth = tester.getSize(label).width;
        final fontSize = tester.widget<Text>(label).style?.fontSize ?? 14;

        // 「1文字＋…」が入るか。入らなければ ellipsis だけが残る
        final oneChar = TextPainter(
          text: TextSpan(text: '研…', style: TextStyle(fontSize: fontSize)),
          textDirection: TextDirection.ltr,
        )..layout();

        expect(
          labelWidth,
          greaterThanOrEqualTo(oneChar.width),
          reason: 'ラベルに残るのが $labelWidth px では、'
              '${StopSelection.maxStops} タブで名前が「…」だけになる',
        );
      });

      testWidgets('更新に失敗しても名前は残る（バーに戻るのは初回起動だけ）', (tester) async {
        // AsyncError も直前の値を添えたまま持つ（AsyncLoading と同じ）。
        // 一度でも取得できていれば、失敗しても停留所名は分かっている
        final scheduleVM = _RefreshableViewModel(_mockResponse);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider.overrideWith(() => scheduleVM),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pump();

        scheduleVM.fail();
        await tester.pump();

        // 本文はエラー画面でも、タブは名前のまま
        expect(find.textContaining('エラー:'), findsOneWidget);
        expect(find.text('千歳駅'), findsOneWidget);
      });

      testWidgets('取得できたのに stopMaster に無い停留所は ID のまま出す', (tester) async {
        // GAS から消えた停留所。伏せても直らないので、どれのことか分かるように
        // ID を出す（labelOf の約束）
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider.overrideWith(
                () => FakeScheduleViewModel(
                  ScheduleResult(
                    data: ScheduleResponse(
                      stopMaster:
                          _stopMaster.where((s) => s.id != 'honbuto').toList(),
                      updatedAt: '2024-01-01',
                      current: _emptyTimetable,
                    ),
                  ),
                ),
              ),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pump();

        expect(find.text('honbuto'), findsOneWidget);
        expect(find.text('千歳駅'), findsOneWidget);
      });
    });

    testWidgets('data状態でupcoming非null: カレンダーアイコンが表示される', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scheduleViewModelProvider.overrideWith(
                () => FakeScheduleViewModel(_mockResponseWithUpcoming)),
            countdownOverride(),
          ],
          child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.calendar_month), findsOneWidget);
    });

    testWidgets('カレンダーアイコンタップ: ModalBottomSheetが表示され「来週のダイヤ」が含まれる',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scheduleViewModelProvider.overrideWith(
                () => FakeScheduleViewModel(_mockResponseWithUpcoming)),
            countdownOverride(),
          ],
          child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.calendar_month));
      await tester.pumpAndSettle();

      expect(find.textContaining('来週のダイヤ'), findsOneWidget);
    });

    testWidgets('リフレッシュボタンタップ: refreshが呼ばれる', (tester) async {
      final vm = FakeScheduleViewModel(_mockResponse);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scheduleViewModelProvider.overrideWith(() => vm),
            countdownOverride(),
          ],
          child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();

      expect(vm.refreshCalled, isTrue);
    });

    // 市路線バスは土日も一部運行するためバナーは現在非表示（WeekendWarningBanner._enabled = false）
    testWidgets('土曜日のdata状態: 土日バナーが表示されない（現在無効化中）', (tester) async {
      // 2024-01-06 = Saturday
      final saturday = DateTime(2024, 1, 6, 9, 0);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scheduleViewModelProvider
                .overrideWith(() => FakeScheduleViewModel(_mockResponse)),
            countdownOverride(now: saturday),
          ],
          child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
        ),
      );
      await tester.pump();

      expect(
        find.text('土日祝日はバスが運行していない場合があります'),
        findsNothing,
      );
    });

    testWidgets('平日のdata状態: 土日バナーが表示されない', (tester) async {
      // 2024-01-01 = Monday (kTestNow)
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scheduleViewModelProvider
                .overrideWith(() => FakeScheduleViewModel(_mockResponse)),
            countdownOverride(),
          ],
          child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
        ),
      );
      await tester.pump();

      expect(
        find.text('土日祝日はバスが運行していない場合があります'),
        findsNothing,
      );
    });

    testWidgets('フッタは更新日のみ表示し、有効期間は表示しない', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scheduleViewModelProvider
                .overrideWith(() => FakeScheduleViewModel(_mockResponse)),
            countdownOverride(),
          ],
          child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('更新: 2024-01-01'), findsOneWidget);
      expect(find.textContaining('有効期間'), findsNothing);
    });

    /// 本文に出す「いま見ている停留所」（#208 → #245）。
    ///
    /// タブは短縮名（#207）でもさらに省略される（375px・5タブでラベルに残るのは
    /// 27px）。**タブだけでは見ている停留所を確定できない**ので、#208 は本文に
    /// 常に正式名を出すことにした。#245 でこれをタップ式のトグルに変えた
    /// （既定は短縮名、タップでその場で正式名に切り替わる）——常時正式名を
    /// 出さなくても、タップで確実に読めれば同じ用は足りる、という判断
    /// （`ArrivalRow` の #241 と同じ）。
    group('いま見ている停留所の名前', () {
      Future<void> pump(WidgetTester tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => FakeScheduleViewModel(_mockResponse)),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pump();
      }

      testWidgets('本文は既定で短縮名を出す（#245）', (tester) async {
        await pump(tester);

        // 科技大本部棟 ではなく 千歳駅（本文もタブと同じ短縮名になる）
        expectNotTruncated(tester, '千歳駅 発');
        expect(find.text('千歳駅前 発'), findsNothing);
        // タブも短縮名のまま。ここを正式名にすると幅が足りない
        expect(
          find.descendant(
            of: find.byType(TabBar),
            matching: find.text('千歳駅'),
          ),
          findsOneWidget,
        );
      });

      testWidgets('本文をタップすると正式名に切り替わる（#245）', (tester) async {
        await pump(tester);

        await tester.tap(find.text('千歳駅 発'));
        await tester.pump();

        expect(find.text('千歳駅前 発'), findsOneWidget);
        expect(find.text('千歳駅 発'), findsNothing);
      });

      testWidgets('もう一度タップすると短縮名に戻る（#245）', (tester) async {
        await pump(tester);

        await tester.tap(find.text('千歳駅 発'));
        await tester.pump();
        await tester.tap(find.text('千歳駅前 発'));
        await tester.pump();

        expect(find.text('千歳駅 発'), findsOneWidget);
        expect(find.text('千歳駅前 発'), findsNothing);
      });

      testWidgets('タブを切り替えると追随する', (tester) async {
        await pump(tester);

        await tester.tap(find.descendant(
          of: find.byType(TabBar),
          matching: find.text('研究棟'),
        ));
        await tester.pumpAndSettle();

        expect(find.text('研究棟 発'), findsOneWidget);
        expect(find.text('千歳駅 発'), findsNothing);
      });

      testWidgets('タブを切り替えるとトグルが戻る（#245・3-8 の担保）', (tester) async {
        await pump(tester);

        // 千歳駅タブで正式名を開く
        await tester.tap(find.text('千歳駅 発'));
        await tester.pump();
        expect(find.text('千歳駅前 発'), findsOneWidget);

        // 研究棟タブへ切り替える
        await tester.tap(find.descendant(
          of: find.byType(TabBar),
          matching: find.text('研究棟'),
        ));
        await tester.pumpAndSettle();

        // 研究棟は開いた覚えが無いので短縮名のまま
        expect(find.text('研究棟 発'), findsOneWidget);
        expect(find.text('科技大研究棟 発'), findsNothing);

        // 千歳駅タブへ戻ると、トグルは開いた状態を持ち越さず短縮名に
        // 戻っている。`TabBarView` は既定では画面外のページを
        // `AutomaticKeepAlive` していないため `_StopTab`（延いては
        // `_StopSectionHeader`）ごと作り直される——`didUpdateWidget` に
        // 頼らずとも、この経路では毎回真っさらな State から始まる
        // （前の停留所で開いた状態が残ると混乱する、という 3-8 の要求を
        // 実測で確かめる）
        await tester.tap(find.descendant(
          of: find.byType(TabBar),
          matching: find.text('千歳駅'),
        ));
        await tester.pumpAndSettle();
        expect(find.text('千歳駅 発'), findsOneWidget);
        expect(find.text('千歳駅前 発'), findsNothing);
      });

      testWidgets('当日以外のダイヤ表示でも残る（NEXT BUS ごと消さない）', (tester) async {
        await pump(tester);

        await tester.tap(find.byIcon(Icons.event_repeat));
        await tester.pumpAndSettle();

        // NEXT BUS は消えるが、タブが省略されるのは同じなので名前は要る
        expect(find.text('NEXT BUS'), findsNothing);
        expect(find.text('千歳駅 発'), findsOneWidget);
      });

      testWidgets('SCHEDULE 側の見出しもタップでトグルする（#245・3-15）', (tester) async {
        await pump(tester);

        // 当日以外のダイヤ表示に切り替える。ここでは見出しが
        // 'NEXT BUS' ではなく 'SCHEDULE' の呼び出し（:1035）になる
        await tester.tap(find.byIcon(Icons.event_repeat));
        await tester.pumpAndSettle();
        expect(find.text('SCHEDULE'), findsOneWidget);
        expect(find.text('千歳駅 発'), findsOneWidget);

        await tester.tap(find.text('千歳駅 発'));
        await tester.pump();
        expect(find.text('千歳駅前 発'), findsOneWidget);

        await tester.tap(find.text('千歳駅前 発'));
        await tester.pump();
        expect(find.text('千歳駅 発'), findsOneWidget);
      });

      // #245 のレビュー（PR #250）で「判断がつかない」と挙がった点。
      // **確かめたうえで、持ち越してよいと決めた。**
      testWidgets('dayType を切り替えてもトグルは持ち越す（#245・意図した挙動）', (tester) async {
        await pump(tester);

        // NEXT BUS 側で正式名を出す
        await tester.tap(find.text('千歳駅 発'));
        await tester.pump();
        expect(find.text('千歳駅前 発'), findsOneWidget);

        // 当日以外のダイヤ表示へ。見出しの呼び出しは NEXT BUS 用から
        // SCHEDULE 用に変わるが、Column の同じ位置なので Element が
        // 使い回され、`didUpdateWidget` は stopId が同じなのでリセットしない
        await tester.tap(find.byIcon(Icons.event_repeat));
        await tester.pumpAndSettle();
        expect(find.text('SCHEDULE'), findsOneWidget);

        // **正式名のまま。** 停留所を切り替えたときは戻す（上のテスト）が、
        // ここは**同じ停留所を見続けている**ので戻す理由が無い。むしろ
        // 「正式名で見たい」という意思表示を、ダイヤ種別を変えただけで
        // 捨てるほうが不親切
        expect(find.text('千歳駅前 発'), findsOneWidget);
        expect(find.text('千歳駅 発'), findsNothing);
      });

      testWidgets('狭い端末でも見出しと同じ行に収まる', (tester) async {
        // iPhone SE 相当。見出し（NEXT BUS）と同居させているので、名前が
        // 伸びると行が溢れる。overflow はテストが失敗として拾う
        tester.view.physicalSize = const Size(750, 1334);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await pump(tester);

        expect(find.text('NEXT BUS'), findsOneWidget);
        expectNotTruncated(tester, '千歳駅 発');
      });

      testWidgets('読み上げは既定（短縮名）でも常に正式名（#245）', (tester) async {
        // `find.bySemanticsLabel` / `tester.getSemantics` はセマンティクス
        // ツリーが実際に組み立てられていないと何も見つからない
        // （`ArrivalRow` の #241 のテストと同じ作法）
        final handle = tester.ensureSemantics();
        await pump(tester);

        // 画面には短縮名（千歳駅 発）しか出ていないが、読み上げは正式名
        // （千歳駅前 発）で確定させる。`debugDumpSemanticsTree()` で
        // 実際に確かめた形をそのまま主張する
        final label = tester.getSemantics(find.text('千歳駅 発')).label;
        expect(label, '千歳駅前 発');

        // **`MergeSemantics` で自分だけの境界を作れているか**も確かめる。
        // これが無いと、GestureDetector 単体では tap アクションと
        // ラベルが一番近い既存の境界（この画面では TabBarView の各ページ）
        // までそのまま這い上がり、'NEXT BUS' のような周辺の静的テキストまで
        // ヘッダーと同じ読み上げ単位に巻き込まれる
        // （`debugDumpSemanticsTree()` で実際に確認して見つけた罠。
        // 修正前は 'NEXT BUS' のラベルが「NEXT BUS\n千歳駅前 発\n
        // TODAY'S SCHEDULE\n更新: 2024-01-01」になっていた）
        final nextBusLabel = tester.getSemantics(find.text('NEXT BUS')).label;
        expect(
          nextBusLabel,
          isNot(contains('発')),
          reason: 'ヘッダーの tap アクション・ラベルが周辺の静的テキストと'
              '同じ読み上げ単位に巻き込まれてはいけない',
        );

        handle.dispose();
      });

      testWidgets('タップして正式名を出しても読み上げは二重にならない（#245）', (tester) async {
        final handle = tester.ensureSemantics();
        await pump(tester);

        final collapsedLabel = tester.getSemantics(find.text('千歳駅 発')).label;
        expect(collapsedLabel, '千歳駅前 発');

        await tester.tap(find.text('千歳駅 発'));
        await tester.pump();

        // タップ後は画面の文字が正式名（千歳駅前 発）に変わるだけで、
        // 読み上げ側は元から正式名だったので増えない
        // （`GestureDetector` が子孫の `Semantics` を自分のタップ操作の
        // ノードにマージする既定の挙動により、`excludeSemantics` を外すと
        // ここが「千歳駅前 発千歳駅前 発」のように二重になる罠がある —
        // `ArrivalRow` の #241 で実際に確認済み）
        final expandedLabel = tester.getSemantics(find.text('千歳駅前 発')).label;
        expect(
          expandedLabel,
          collapsedLabel,
          reason: 'タップ後も読み上げのラベルはタップ前と同じであるべき（二重に読ませない）',
        );

        handle.dispose();
      });

      testWidgets('stopMaster に無い停留所は ID のまま出す', (tester) async {
        // 取得はできているのに引けない = GAS から消えた停留所。
        // 本文だけ空白にすると、どこの時刻表かが分からなくなる
        final result = ScheduleResult(
          data: ScheduleResponse(
            stopMaster: const [],
            updatedAt: '2024-01-01',
            current: _emptyTimetable,
          ),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => FakeScheduleViewModel(result)),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pump();

        expect(find.text('chitose 発'), findsOneWidget);
      });
    });

    group('当日以外のダイヤ表示', () {
      testWidgets('表示モード切替アイコンが表示される', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => FakeScheduleViewModel(_mockResponse)),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pump();

        expect(find.byIcon(Icons.event_repeat), findsOneWidget);
      });

      testWidgets('アイコンタップ: 平日/土日祝ダイヤの切替ボタンが表示され NEXT BUS が非表示になる',
          (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => FakeScheduleViewModel(_mockResponse)),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pump();

        // 当日表示: 切替ボタンなし・NEXT BUS あり
        expect(find.byType(SegmentedButton<DayType>), findsNothing);
        expect(find.text('NEXT BUS'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.event_repeat));
        await tester.pumpAndSettle();

        // 当日以外表示: 切替ボタンあり・NEXT BUS なし・SCHEDULE ラベル
        expect(find.byType(SegmentedButton<DayType>), findsOneWidget);
        expect(find.text('平日ダイヤ'), findsOneWidget);
        expect(find.text('土日祝ダイヤ'), findsOneWidget);
        expect(find.text('NEXT BUS'), findsNothing);
        expect(find.text('SCHEDULE'), findsOneWidget);
        // 期別（授業期 / 学休期）の切替ボタンも表示される
        expect(find.byType(SegmentedButton<SeasonType>), findsOneWidget);
        expect(find.text('授業期'), findsOneWidget);
        expect(find.text('学休期'), findsOneWidget);
      });

      testWidgets('切替ボタンでダイヤ種別を変更できる', (tester) async {
        // 平日限定・土日祝限定の便を含むタイムテーブル
        final result = ScheduleResult(
          data: ScheduleResponse(
            stopMaster: _stopMaster,
            updatedAt: '2024-01-01',
            current: BusTimetable(
              validFrom: '2024-01-01',
              validTo: '2024-12-31',
              schedules: const [
                BusEntry(
                  time: '09:00',
                  boardingStopId: 'chitose',
                  destination: '科技大',
                  weekdayOnly: true,
                ),
                BusEntry(
                  time: '10:00',
                  boardingStopId: 'chitose',
                  destination: '科技大',
                  weekendOnly: true,
                ),
              ],
            ),
          ),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => FakeScheduleViewModel(result)),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pump();

        await tester.tap(find.byIcon(Icons.event_repeat));
        await tester.pumpAndSettle();

        // 平日ダイヤを選択 → weekdayOnly の便のみ表示
        await tester.tap(find.text('平日ダイヤ'));
        await tester.pumpAndSettle();
        expect(find.text('09:00'), findsOneWidget);
        expect(find.text('10:00'), findsNothing);

        // 土日祝ダイヤへ切替 → weekendOnly の便のみ表示
        await tester.tap(find.text('土日祝ダイヤ'));
        await tester.pumpAndSettle();
        expect(find.text('09:00'), findsNothing);
        expect(find.text('10:00'), findsOneWidget);
      });

      testWidgets('アイコン再タップ: 当日表示に戻る', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => FakeScheduleViewModel(_mockResponse)),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pump();

        await tester.tap(find.byIcon(Icons.event_repeat));
        await tester.pumpAndSettle();
        expect(find.byType(SegmentedButton<DayType>), findsOneWidget);

        await tester.tap(find.byIcon(Icons.event_repeat));
        await tester.pumpAndSettle();
        expect(find.byType(SegmentedButton<DayType>), findsNothing);
        expect(find.text('NEXT BUS'), findsOneWidget);
      });
    });

    group('お気に入りタブ', () {
      testWidgets('お気に入り未設定: タブ4つ全てに star_border アイコンが表示される', (tester) async {
        final favNotifier = _FakeFavoriteTabNotifier(const FavoriteTab());
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => FakeScheduleViewModel(_mockResponse)),
              favoriteTabProvider.overrideWith(() => favNotifier),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pump();

        expect(find.byIcon(Icons.star_border), findsNWidgets(4));
        expect(find.byIcon(Icons.star), findsNothing);
      });

      testWidgets('タブ0がお気に入り: star 1個 + star_border 3個が表示される', (tester) async {
        final favNotifier =
            _FakeFavoriteTabNotifier(const FavoriteTab(stopId: 'chitose'));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => FakeScheduleViewModel(_mockResponse)),
              favoriteTabProvider.overrideWith(() => favNotifier),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pump();

        expect(find.byIcon(Icons.star), findsOneWidget);
        expect(find.byIcon(Icons.star_border), findsNWidgets(3));
      });

      testWidgets('タブ0のスタータップ: toggleFavorite(chitose) が呼ばれる', (tester) async {
        final favNotifier = _FakeFavoriteTabNotifier(const FavoriteTab());
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => FakeScheduleViewModel(_mockResponse)),
              favoriteTabProvider.overrideWith(() => favNotifier),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pump();

        // タブ0（千歳駅）の star_border をタップ
        await tester.tap(find.byIcon(Icons.star_border).first);
        await tester.pump();

        expect(favNotifier.lastToggleStopId, equals('chitose'));
      });

      testWidgets('タブ2のスタータップ: toggleFavorite(kenkyuto) が呼ばれる', (tester) async {
        final favNotifier = _FakeFavoriteTabNotifier(const FavoriteTab());
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => FakeScheduleViewModel(_mockResponse)),
              favoriteTabProvider.overrideWith(() => favNotifier),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pump();

        // タブ2（研究棟）の star_border をタップ（3番目 = index 2）
        await tester.tap(find.byIcon(Icons.star_border).at(2));
        await tester.pump();

        expect(favNotifier.lastToggleStopId, equals('kenkyuto'));
      });

      testWidgets('タブ2がお気に入り未設定でタブ2に切り替え: → 本部棟・→ 千歳駅の選択肢が見える', (tester) async {
        final favNotifier = _FakeFavoriteTabNotifier(const FavoriteTab());
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => FakeScheduleViewModel(_mockResponse)),
              favoriteTabProvider.overrideWith(() => favNotifier),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pump();

        // 研究棟タブをタップ
        await tester.tap(find.text('研究棟'));
        await tester.pumpAndSettle();

        expect(find.text('→ 本部棟'), findsOneWidget);
        expect(find.text('→ 千歳駅'), findsOneWidget);
      });

      testWidgets('タブ2がお気に入りで起動: 研究棟タブが表示され → 本部棟・→ 千歳駅の選択肢が見える',
          (tester) async {
        final favNotifier =
            _FakeFavoriteTabNotifier(const FavoriteTab(stopId: 'kenkyuto'));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => FakeScheduleViewModel(_mockResponse)),
              favoriteTabProvider.overrideWith(() => favNotifier),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('→ 本部棟'), findsOneWidget);
        expect(find.text('→ 千歳駅'), findsOneWidget);
      });

      testWidgets('タブ2がお気に入り: star 1個 + star_border 3個が表示される', (tester) async {
        final favNotifier =
            _FakeFavoriteTabNotifier(const FavoriteTab(stopId: 'kenkyuto'));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => FakeScheduleViewModel(_mockResponse)),
              favoriteTabProvider.overrideWith(() => favNotifier),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pump();

        expect(find.byIcon(Icons.star), findsOneWidget);
        expect(find.byIcon(Icons.star_border), findsNWidgets(3));
      });

      // 再現テスト: issue #126
      // favoriteTabProvider が先に解決して addPostFrameCallback が index=2 をセットした後、
      // scheduleAsync が遅れて解決して TabBarView が初めて作られるシナリオ。
      // find.text() はツリー存在のみ確認するため、サイズ 0 のバグを見逃す。
      // tester.getSize() で実際にレンダリングされた高さを検証する。
      testWidgets('SegmentedButton のサイズが 0 でない（build より前に index が変更される再現）',
          (tester) async {
        final scheduleVM = _DelayedScheduleViewModel(_mockResponse);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider.overrideWith(() => scheduleVM),
              favoriteTabProvider.overrideWith(
                () => _FakeFavoriteTabNotifier(
                    const FavoriteTab(stopId: 'kenkyuto')),
              ),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );

        // favoriteAsync 解決 → ref.listen 発火 → addPostFrameCallback 登録
        await tester.pump();
        // addPostFrameCallback 実行 → _tabController.index = 2（TabBarView 未生成）
        await tester.pump();

        // scheduleAsync を解決 → TabBarView が index=2 の状態で初めて生成される
        scheduleVM.complete();
        await tester.pump();

        final segmentedFinder = find.byType(SegmentedButton<String>);
        expect(segmentedFinder, findsOneWidget);

        // バグが再現すると高さが 0 になる
        final size = tester.getSize(segmentedFinder);
        expect(size.height, greaterThan(0));
      });

      testWidgets('タブ2がお気に入りで起動後: 千歳駅タブをタップするとタブ切り替えできる', (tester) async {
        final favNotifier =
            _FakeFavoriteTabNotifier(const FavoriteTab(stopId: 'kenkyuto'));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => FakeScheduleViewModel(_mockResponse)),
              favoriteTabProvider.overrideWith(() => favNotifier),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // タブ2（研究棟）のSegmentedButtonが表示されている
        expect(find.text('→ 本部棟'), findsOneWidget);

        // 千歳駅タブをタップ（ラベルをタップ）
        await tester.tap(find.text('千歳駅'));
        await tester.pumpAndSettle();

        // タブ0（千歳駅）に切り替わり、研究棟のSegmentedButtonは表示されない
        expect(find.text('→ 本部棟'), findsNothing);
      });
    });

    group('停留所の選択', () {
      testWidgets('選択に沿ったタブが、選択の順で出る', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => FakeScheduleViewModel(_mockResponse)),
              stopSelectionProvider.overrideWith(
                () => FakeStopSelectionNotifier(
                    const StopSelection(stopIds: ['honbuto', 'chitose'])),
              ),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(Tab), findsNWidgets(2));
        expect(find.text('研究棟'), findsNothing);
        // タブの並びは選択の並び
        final tabs = tester.widgetList<Tab>(find.byType(Tab)).toList();
        expect(tester.getTopLeft(find.byWidget(tabs[0])).dx,
            lessThan(tester.getTopLeft(find.byWidget(tabs[1])).dx));
        expect(find.text('本部棟'), findsOneWidget);
        expect(find.text('千歳駅'), findsOneWidget);
      });

      testWidgets('停留所を足すとタブが増え、見ていた停留所のまま残る', (tester) async {
        final selection = FakeStopSelectionNotifier(StopSelection.initial);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => FakeScheduleViewModel(_mockResponse)),
              stopSelectionProvider.overrideWith(() => selection),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // 研究棟（index 2）を開いておく
        await tester.tap(find.text('研究棟'));
        await tester.pumpAndSettle();
        expect(find.text('→ 本部棟'), findsOneWidget);

        // 設定で先頭に停留所を足す = index がずれる
        selection.setSelection(const StopSelection(stopIds: [
          'morimoto',
          'chitose',
          'minamiChitose',
          'kenkyuto',
          'honbuto'
        ]));
        await tester.pumpAndSettle();

        expect(find.byType(Tab), findsNWidgets(5));
        // 番号ではなく停留所で追いかけるので、研究棟のままでいる
        expect(find.text('→ 本部棟'), findsOneWidget);
      });

      testWidgets('見ていた停留所が外されたら先頭のタブに戻る', (tester) async {
        final selection = FakeStopSelectionNotifier(StopSelection.initial);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => FakeScheduleViewModel(_mockResponse)),
              stopSelectionProvider.overrideWith(() => selection),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('研究棟'));
        await tester.pumpAndSettle();
        expect(find.text('→ 本部棟'), findsOneWidget);

        selection
            .setSelection(const StopSelection(stopIds: ['chitose', 'honbuto']));
        await tester.pumpAndSettle();

        expect(find.byType(Tab), findsNWidgets(2));
        expect(find.text('→ 本部棟'), findsNothing);
      });
    });

    group('行き先の見出し', () {
      // 千歳駅は長都行き（系統3 復路）の途中停留所。イオン千歳店前を足しても
      // 見出しは終点のままでなければならない
      const master = [
        BusStop(id: 'chitose', label: '千歳駅前', shortLabel: '千歳駅'),
        BusStop(id: 'aeon', label: 'イオン千歳店前'),
        BusStop(id: 'honbuto', label: '科技大本部棟', shortLabel: '本部棟'),
        BusStop(id: 'osatsu', label: '長都駅東口'),
      ];

      ScheduleResult resultWith({required String? terminus}) => ScheduleResult(
            data: ScheduleResponse(
              stopMaster: master,
              updatedAt: '2024-01-01',
              current: BusTimetable(
                validFrom: '2024-01-01',
                validTo: '2024-12-31',
                schedules: [
                  const BusEntry(
                    time: '09:00',
                    boardingStopId: 'chitose',
                    destination: '科技大',
                    terminusStopId: 'honbuto',
                    arrivals: {'honbuto': '09:30'},
                  ),
                  BusEntry(
                    time: '09:10',
                    boardingStopId: 'chitose',
                    destination: '千歳駅',
                    terminusStopId: terminus,
                    // 選んだ停留所だけに絞られた到着地
                    arrivals: const {'aeon': '09:16'},
                  ),
                ],
              ),
            ),
          );

      Widget wrap(ScheduleResult result) => ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => FakeScheduleViewModel(result)),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          );

      testWidgets('終点を出す。途中で足した停留所には引きずられない', (tester) async {
        await tester.pumpWidget(wrap(resultWith(terminus: 'osatsu')));
        await tester.pumpAndSettle();

        expect(find.text('→ 長都駅東口'), findsOneWidget);
        expect(find.text('→ イオン千歳店前'), findsNothing);
        expect(find.text('→ 本部棟'), findsOneWidget);
      });

      testWidgets('終点が分からない供給元では到着地の末尾に頼る', (tester) async {
        // 未デプロイの GAS・#177 以前のキャッシュ
        await tester.pumpWidget(wrap(resultWith(terminus: null)));
        await tester.pumpAndSettle();

        expect(find.text('→ イオン千歳店前'), findsOneWidget);
      });
    });

    group('便が1本も無い停留所', () {
      // 停留所を1つだけ選ぶと、GAS は全便を stops 1要素で返す。降り先が
      // 無くなるので便は1本も引けない。以前は見出しだけが並んで下が無言の
      // 空白になっていた（#177）
      Widget wrapOne(List<BusEntry> schedules, List<String> stopIds) =>
          ProviderScope(
            overrides: [
              scheduleViewModelProvider.overrideWith(
                () => FakeScheduleViewModel(ScheduleResult(
                  data: ScheduleResponse(
                    stopMaster: _stopMaster,
                    updatedAt: '2024-01-01',
                    coveredStopIds: stopIds,
                    current: BusTimetable(
                      validFrom: '2024-01-01',
                      validTo: '2024-03-31',
                      schedules: schedules,
                    ),
                  ),
                )),
              ),
              stopSelectionProvider.overrideWith(
                () =>
                    FakeStopSelectionNotifier(StopSelection(stopIds: stopIds)),
              ),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          );

      testWidgets('引ける便が無ければ、次にどうするかを出す（無言の空白にしない）', (tester) async {
        await tester.pumpWidget(wrapOne(const [], ['chitose']));
        await tester.pumpAndSettle();

        expect(find.textContaining('もう1つ選んでください'), findsOneWidget);
        // 見出しだけが残らないこと
        expect(find.text('NEXT BUS'), findsNothing);
        expect(find.text("TODAY'S SCHEDULE"), findsNothing);
        // 取得はできているので「取得できていません」とは別物
        expect(find.textContaining('まだ取得できていません'), findsNothing);
      });

      testWidgets('降り先があれば今までどおり出る', (tester) async {
        await tester.pumpWidget(wrapOne(const [
          BusEntry(
            time: '08:30',
            boardingStopId: 'chitose',
            destination: '科技大',
            terminusStopId: 'honbuto',
            arrivals: {'honbuto': '08:55'},
          ),
        ], [
          'chitose',
          'honbuto'
        ]));
        await tester.pumpAndSettle();

        expect(find.text('NEXT BUS'), findsOneWidget);
        expect(find.textContaining('もう1つ選んでください'), findsNothing);
      });
    });

    group('取得していない停留所', () {
      // オフラインで停留所を足すと、その停留所の時刻を持たないキャッシュを
      // 表示することになる（#177）
      // isFromCache は付けない。バナーの分だけ縦が伸びてテスト画面（600px）に
      // 収まらなくなるだけで、出し分けの判定には効かない
      ScheduleResult cachedCovering(List<String> covered) => ScheduleResult(
            data: ScheduleResponse(
              stopMaster: _stopMaster,
              updatedAt: '2024-01-01',
              coveredStopIds: covered,
              current: _emptyTimetable,
            ),
          );

      Widget wrap(ScheduleResult result, {List<String>? stopIds}) =>
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => FakeScheduleViewModel(result)),
              if (stopIds != null)
                stopSelectionProvider.overrideWith(
                  () => FakeStopSelectionNotifier(
                      StopSelection(stopIds: stopIds)),
                ),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          );

      testWidgets('持っている停留所は今までどおり時刻を出す', (tester) async {
        await tester.pumpWidget(wrap(
          cachedCovering(['kenkyuto']),
          stopIds: ['kenkyuto', 'morimoto'],
        ));
        await tester.pumpAndSettle();

        expect(find.text('NEXT BUS'), findsOneWidget);
        expect(find.textContaining('このバス停の時刻はまだ取得できていません'), findsNothing);
      });

      testWidgets('持っていない停留所のタブだけ「取得できていません」を出す', (tester) async {
        await tester.pumpWidget(wrap(
          cachedCovering(['kenkyuto']),
          stopIds: ['kenkyuto', 'morimoto'],
        ));
        await tester.pumpAndSettle();

        // もりもと本店前のタブへ切り替える（stopMaster に無いので ID が出る）
        await tester.tap(find.text('morimoto'));
        await tester.pumpAndSettle();

        expect(find.textContaining('このバス停の時刻はまだ取得できていません'), findsOneWidget);
        // 「時刻表データなし」（便が1本も無い）とは別物として出す
        expect(find.text('時刻表データなし'), findsNothing);
      });

      testWidgets('「再試行」で取り直す', (tester) async {
        final vm = FakeScheduleViewModel(cachedCovering(['kenkyuto']));
        await tester.pumpWidget(ProviderScope(
          overrides: [
            scheduleViewModelProvider.overrideWith(() => vm),
            stopSelectionProvider.overrideWith(
              () => FakeStopSelectionNotifier(
                  const StopSelection(stopIds: ['kenkyuto', 'morimoto'])),
            ),
            countdownOverride(),
          ],
          child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.text('morimoto'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('再試行'));
        await tester.pump();

        expect(vm.refreshCalled, isTrue);
      });

      testWidgets('coveredStopIds が空なら全部持っているとみなす', (tester) async {
        // #177 以前のキャッシュには記録が無い
        await tester.pumpWidget(wrap(cachedCovering(const [])));
        await tester.pumpAndSettle();

        expect(find.textContaining('このバス停の時刻はまだ取得できていません'), findsNothing);
      });
    });

    group('OfflineCacheBanner', () {
      testWidgets('isFromCache: true のとき OfflineCacheBanner が表示される',
          (tester) async {
        final cachedResult = ScheduleResult(
          data: ScheduleResponse(
            stopMaster: _stopMaster,
            updatedAt: '2024-01-01',
            current: _emptyTimetable,
          ),
          isFromCache: true,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => FakeScheduleViewModel(cachedResult)),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pump();

        expect(find.byType(OfflineCacheBanner), findsOneWidget);
        expect(find.textContaining('キャッシュデータを表示中'), findsOneWidget);
      });

      testWidgets('isFromCache: false のとき OfflineCacheBanner が表示されない',
          (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => FakeScheduleViewModel(_mockResponse)),
              countdownOverride(),
            ],
            child:
                MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pump();

        expect(find.byType(OfflineCacheBanner), findsNothing);
      });
    });
  });
}
