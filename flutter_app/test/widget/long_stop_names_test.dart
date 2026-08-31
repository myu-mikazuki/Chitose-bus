import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// 既定の4停留所の外を選んだときの表示を守る（#177）。
///
/// #177 以前は GAS が4停留所に絞っていたため、長い名前も未知の ID も画面に
/// 出てこなかった。設定でバス停を選べるようになって初めて露出する。
///
/// overflow はテストが自動で失敗として拾うので、「例外なく pump できること」
/// 自体が検査になっている。

/// 停留所名の fixture は `test/helpers/test_theme.dart` の [kLongStopMaster]。
/// **`text_scaler_test.dart` と共有している**ので、実データが伸びたときに
/// 片方だけ古くならないよう向こうに置いてある。
const _result = ScheduleResult(
  data: ScheduleResponse(
    stopMaster: kLongStopMaster,
    updatedAt: '2024-01-01',
    current: BusTimetable(
      validFrom: '2024-01-01',
      validTo: '2024-12-31',
      schedules: [
        BusEntry(
          time: '09:00',
          boardingStopId: 'koizumi',
          destination: '科技大',
          // 既定の4停留所に無い到着地。対応表を引いていた頃は `null 着` になった
          arrivals: {
            'arcadia': '09:05',
            'hoyukai': '09:12',
            'honbuto': '09:30',
          },
        ),
      ],
    ),
  ),
);

/// 時刻表リストの行を開く。
///
/// **`find.text('09:00').first` では開かない。** NEXT BUS カードが同じ時刻を
/// 出しているため、そちらを叩いてしまう。リスト側を名指しする。
Future<void> _expandScheduleRow(WidgetTester tester) async {
  final row = find.descendant(
    of: find.byType(ScheduleList),
    matching: find.text('09:00'),
  );
  // 狭い幅では行が画面外にあり、そのまま叩くと外れる
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Widget _wrap(List<String> stopIds) => ProviderScope(
      overrides: [
        scheduleViewModelProvider
            .overrideWith(() => FakeScheduleViewModel(_result)),
        stopSelectionProvider.overrideWith(
          () => FakeStopSelectionNotifier(StopSelection(stopIds: stopIds)),
        ),
        // 2024-01-01 は年末年始（12/31〜1/3）で全便運休になり、便が1つも出ない
        countdownOverride(now: DateTime(2024, 6, 17, 8, 0)),
      ],
      child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('長い名前・既定外の停留所', () {
    testWidgets('タブが overflow しない（狭い端末）', (tester) async {
      // iPhone SE 相当。タブ1つあたり約94px しかない
      tester.view.physicalSize = const Size(750, 1334);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester
          .pumpWidget(_wrap(['koizumi', 'arcadia', 'hoyukai', 'chitose']));
      await tester.pumpAndSettle();
    });

    // #231。到着行は `spaceBetween` に素の Text を2つ並べるだけなので、
    // 名前が伸びると縮まずに溢れる。**幅の主張はここでしかできない**
    // （既定の4停留所は正式名でも6文字までで、溢れる長さにならない）。
    //
    // 「タブが overflow しない（狭い端末）」では拾えなかった。あちらは
    // 停留所を4つ選ぶため `_retuneTabs` が既定の先頭 `chitose` を追いかけ、
    // その停留所を発つ便が無いので `_StopHasNoBus` が出てカード自体が
    // 描かれない。1停留所だけ選ばせるとカードに辿り着く。
    //
    // **320px 級の端末（iPhone SE 第1世代など）はこの2幅では見ていない**
    // （既知）。
    //
    // **文字を大きくする設定（`TextScaler`）は #241 で別に手当てした。**
    // 以前はここで「比率が変わらないので字を小さくしても同じ倍率で同じよう
    // に溢れる」と書いていたが、それは #237 で拡大設定を実測して初めて
    // 分かった話で、直しはこの overflow テストの範囲外（`text_scaler_test.dart`
    // 側）。#241 で既定表示を短縮名（最長5文字）に戻し、正式名はタップで
    // 折り返し可能な形で出すようにしたことで、**倍率が上がっても構造的に
    // 溢れない**形になった。詳しい経緯は `ArrivalRow`（`arrival_row.dart`）の
    // ドキュメントコメントを見ること。
    //
    // **到着行が出る3経路のうち、いちばん狭いのはカード**（375px で実測）。
    //
    // | 経路 | 到着行の幅（375px） |
    // |---|---|
    // | NEXT BUS カード | **300px**（外の `Padding(16)` ＋ カードの `horizontal: 20` ＋ 枠線 1.5） |
    // | 来週ダイヤの BottomSheet | 303px（シートの `all(16)` ＋ 行の `horizontal: 16` ＋ `left: 8`） |
    // | ホームの時刻表リスト | 335px（`Padding` の外にあるので `375 - 32 - 8`） |
    //
    // つまり**カードが通ればリストも通る**。ただし**最狭は入れ替わりうる**
    // （シートの余白を増やす／カードの余白を減らす）ので、幅を守る場所を
    // 決めるときは3経路とも測り直すこと（#237）。
    // 下のリストのテストはその意味で
    // 冗長だが、リスト側の余白が変わったときに気づけるので残す。
    // 当初は「リストの方が 8px 狭い」と書いていたが逆だった（#234 のレビュー指摘）。
    for (final width in [375.0, 360.0]) {
      testWidgets('NEXT BUS の到着行が overflow しない（幅 $width・#231 / #234 / #241）',
          (tester) async {
        tester.view.physicalSize = Size(width * 2, 1334);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_wrap(['koizumi']));
        await tester.pumpAndSettle();

        // #241 で既定表示は短縮名（`labelOf`）に戻した。実データの最長13文字
        // （正式名）は既定では出ず、`O･A入口` のような短縮名（最長5文字）が
        // 出るので、そもそも overflow の的にならない幅になっている
        expect(find.text('O･A入口 着'), findsOneWidget);
      });

      // #241 で時刻表リストの到着行も既定は短縮名に戻した。**上の表のとおり
      // カードより広いので、カードが通ればここも通る。**余白が変わったときの
      // 検知として残している。
      testWidgets('時刻表リストの到着行が overflow しない（幅 $width・#241）', (tester) async {
        tester.view.physicalSize = Size(width * 2, 1334);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_wrap(['koizumi']));
        await tester.pumpAndSettle();

        await _expandScheduleRow(tester);

        // カードとリストの2箇所に出る
        expect(find.text('O･A入口 着'), findsNWidgets(2));
      });
    }

    testWidgets('見出しの停留所名は削らずに正式名を出す', (tester) async {
      await tester.pumpWidget(_wrap(['koizumi']));
      await tester.pumpAndSettle();

      // タブでは1〜2文字しか読めない名前を、ここでは丸ごと出す（#208）。
      // find.text だけでは ellipsis で切れていても通るので、省略の有無まで見る
      expect(find.text('古泉循環器内科クリニック前 発'), findsOneWidget);
      expectNotTruncated(tester, '古泉循環器内科クリニック前 発');
    });

    testWidgets('到着地のラベルが null にならない', (tester) async {
      await tester.pumpWidget(_wrap(['koizumi']));
      await tester.pumpAndSettle();

      // NEXT BUS カード。#241 で既定表示は短縮名に戻したので `O･A入口 着`
      expect(find.textContaining('null'), findsNothing);
      expect(find.text('O･A入口 着'), findsOneWidget);

      // 時刻表の行を開く
      await _expandScheduleRow(tester);

      expect(find.textContaining('null'), findsNothing);
      expect(find.text('豊友会 着'), findsWidgets);
    });

    // #241 で意図をもう一度反転させた（#234 → #241）。#234 は「短縮名は現地の
    // 停留所の表記とは別物なので、降りる場所を確かめる到着行では使わない」と
    // 判断して正式名に寄せたが、#237 で拡大設定を実測すると**その到着行こそが
    // Android の「最大」(1.3) で実際に崩れる唯一の場所**だった。
    //
    // 正式名のまま拡大に耐えさせるより、**既定は短縮名（最長5文字）にして
    // 構造的に幅の問題を消し、正式名はタップで確実に読める形で残す**ことにした
    // （`ArrivalRow` のドキュメントコメントに詳しい経緯がある）。
    //
    // **既定の4停留所の見え方が v1.3.1 からもう一度変わることを承知で
    // 受け入れている**（`科技大本部棟 着` → `本部棟 着`）。
    testWidgets('到着行は既定で短縮名を出す（#241）', (tester) async {
      await tester.pumpWidget(_wrap(['koizumi']));
      await tester.pumpAndSettle();

      // 科技大本部棟 ではなく 本部棟
      expect(find.text('本部棟 着'), findsOneWidget);
      expect(find.text('科技大本部棟 着'), findsNothing);
    });

    testWidgets('到着行をタップすると正式名が出る（NEXT BUS カード・#241）', (tester) async {
      await tester.pumpWidget(_wrap(['koizumi']));
      await tester.pumpAndSettle();

      // NEXT BUS カード側の到着行を名指しでタップする（時刻表リストは
      // まだ開いていないので、この時点で '本部棟 着' はカードにしか無い）
      await tester.tap(find.text('本部棟 着'));
      await tester.pumpAndSettle();

      expect(find.text('科技大本部棟'), findsOneWidget);
    });

    testWidgets('時刻表リストの到着行も既定で短縮名を出す（#241）', (tester) async {
      await tester.pumpWidget(_wrap(['koizumi']));
      await tester.pumpAndSettle();

      await _expandScheduleRow(tester);

      // NEXT BUS カードと時刻表リストで同じ便の到着地が違う名前にならないこと
      expect(find.text('本部棟 着'), findsNWidgets(2));
      expect(find.text('科技大本部棟 着'), findsNothing);
    });

    testWidgets('到着行をタップすると正式名が出る（時刻表リスト・#241）', (tester) async {
      await tester.pumpWidget(_wrap(['koizumi']));
      await tester.pumpAndSettle();

      await _expandScheduleRow(tester);

      // 時刻表リスト側の '本部棟 着' はカードと合わせて2つあるので、
      // ScheduleList 配下に絞ってからタップする
      final listRow = find.descendant(
        of: find.byType(ScheduleList),
        matching: find.text('本部棟 着'),
      );
      expect(listRow, findsOneWidget);
      await tester.ensureVisible(listRow);
      await tester.pumpAndSettle();
      await tester.tap(listRow);
      await tester.pumpAndSettle();

      // 正式名がリスト側に出る（カード側には出ていない）
      expect(
        find.descendant(
          of: find.byType(ScheduleList),
          matching: find.text('科技大本部棟'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('到着行をタップしても時刻表リストの親の行は閉じない（#241）', (tester) async {
      await tester.pumpWidget(_wrap(['koizumi']));
      await tester.pumpAndSettle();

      await _expandScheduleRow(tester);
      expect(find.text('本部棟 着'), findsNWidgets(2));

      final listRow = find.descendant(
        of: find.byType(ScheduleList),
        matching: find.text('本部棟 着'),
      );
      await tester.ensureVisible(listRow);
      await tester.pumpAndSettle();
      await tester.tap(listRow);
      await tester.pumpAndSettle();

      // 親行が閉じていれば到着行そのものが消えるはず。
      // 内側のタップに親が反応せず、到着行はまだ出ている
      expect(find.text('本部棟 着'), findsNWidgets(2));
    });

    testWidgets('stopMaster に無い ID は ID をそのまま出す', (tester) async {
      // GAS から停留所が消えても null にはしない
      const result = ScheduleResult(
        data: ScheduleResponse(
          stopMaster: kLongStopMaster,
          updatedAt: '2024-01-01',
          current: BusTimetable(
            validFrom: '2024-01-01',
            validTo: '2024-12-31',
            schedules: [
              BusEntry(
                time: '09:00',
                boardingStopId: 'koizumi',
                destination: '科技大',
                arrivals: {'ghost': '09:05'},
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          scheduleViewModelProvider
              .overrideWith(() => FakeScheduleViewModel(result)),
          stopSelectionProvider.overrideWith(
            () => FakeStopSelectionNotifier(
                const StopSelection(stopIds: ['koizumi'])),
          ),
          countdownOverride(now: DateTime(2024, 6, 17, 8, 0)),
        ],
        child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('ghost 着'), findsOneWidget);
    });
  });
}
