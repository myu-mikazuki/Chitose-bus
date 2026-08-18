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

import '../helpers/test_theme.dart';

/// 既定の4停留所の外を選んだときの表示を守る（#177）。
///
/// #177 以前は GAS が4停留所に絞っていたため、長い名前も未知の ID も画面に
/// 出てこなかった。設定でバス停を選べるようになって初めて露出する。
///
/// overflow はテストが自動で失敗として拾うので、「例外なく pump できること」
/// 自体が検査になっている。

class _FakeScheduleViewModel extends ScheduleViewModel {
  _FakeScheduleViewModel(this._result);
  final ScheduleResult _result;

  @override
  Future<ScheduleResult> build() async => _result;

  @override
  Future<void> refresh() async {}
}

class _FakeStopSelectionNotifier extends StopSelectionNotifier {
  _FakeStopSelectionNotifier(this._initial);
  final StopSelection _initial;

  @override
  Future<StopSelection> build() async => _initial;
}

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
            .overrideWith(() => _FakeScheduleViewModel(_result)),
        stopSelectionProvider.overrideWith(
          () => _FakeStopSelectionNotifier(StopSelection(stopIds: stopIds)),
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
    // **この2幅までしか守れていない（既知）。** 直し方が「字を小さくする」
    // なので構造的な保証ではなく、次の2つは依然として溢れる:
    //
    // - **320px 級の端末**（iPhone SE 第1世代など）
    // - **文字を大きくする設定**（`TextScaler`）。比率が変わらないので
    //   字を小さくしても同じ倍率で同じように溢れる
    //
    // 名前側を `Flexible` + ellipsis にすれば「切れるが溢れない」形にできるが、
    // #208 で「見出しの停留所名は削らずに正式名を出す」と決めた直後に到着行を
    // 省略し始めると噛み合わないため見送っている（PR #236）。**拡大設定で
    // どこが壊れるかを先に可視化してから決める**（#237）。
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
      testWidgets('NEXT BUS の到着行が overflow しない（幅 $width・#231 / #234）',
          (tester) async {
        tester.view.physicalSize = Size(width * 2, 1334);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_wrap(['koizumi']));
        await tester.pumpAndSettle();

        // 実データの最長13文字。**この停留所は短縮名（`O･A入口`）を持つ**ので、
        // `officialLabelOf` を `labelOf` に戻すとここが落ちる。いちばん狭い
        // 経路で #234 の主張と幅の主張を同時に押さえている
        expect(find.text('オフィス・アルカディア入口 着'), findsOneWidget);
      });

      // #234 で時刻表リストの到着行も正式名にしたため、こちらにも最長の名前が
      // 出るようになった。**上の表のとおりカードより広いので、カードが通れば
      // ここも通る。**余白が変わったときの検知として残している。
      testWidgets('時刻表リストの到着行が overflow しない（幅 $width・#234）', (tester) async {
        tester.view.physicalSize = Size(width * 2, 1334);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_wrap(['koizumi']));
        await tester.pumpAndSettle();

        await _expandScheduleRow(tester);

        // カードとリストの2箇所に出る
        expect(find.text('オフィス・アルカディア入口 着'), findsNWidgets(2));
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

      // NEXT BUS カード
      expect(find.textContaining('null'), findsNothing);
      expect(find.text('オフィス・アルカディア入口 着'), findsOneWidget);

      // 時刻表の行を開く
      await _expandScheduleRow(tester);

      expect(find.textContaining('null'), findsNothing);
      expect(find.text('千歳豊友会病院前 着'), findsWidgets);
    });

    // #234 で意図を反転させた。以前は「短縮名があればそちらを出す（既定の4
    // 停留所の見え方は不変）」を固定していた。
    //
    // #207 で31件すべてに `shortLabel` が付いたことで、**幅が足りている到着行に
    // まで短縮名が及んだ**（`古泉循環器内科クリニック前 着` → `古泉 着`）。
    // 短縮名はタブで見分けがつくことだけを狙って削ってあり、現地の停留所の
    // 表記とは別物なので、降りる場所を確かめる行には使わない。
    //
    // **既定の4停留所の見え方が変わることを承知で受け入れている**
    // （`本部棟 着` → `科技大本部棟 着`）。
    testWidgets('到着行は短縮名があっても正式名を出す（#234）', (tester) async {
      await tester.pumpWidget(_wrap(['koizumi']));
      await tester.pumpAndSettle();

      // 本部棟 ではなく 科技大本部棟
      expect(find.text('科技大本部棟 着'), findsOneWidget);
      expect(find.text('本部棟 着'), findsNothing);
    });

    testWidgets('時刻表リストの到着行も正式名を出す（#234）', (tester) async {
      await tester.pumpWidget(_wrap(['koizumi']));
      await tester.pumpAndSettle();

      await _expandScheduleRow(tester);

      // NEXT BUS カードと時刻表リストで同じ便の到着地が違う名前にならないこと
      expect(find.text('科技大本部棟 着'), findsNWidgets(2));
      expect(find.text('本部棟 着'), findsNothing);
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
              .overrideWith(() => _FakeScheduleViewModel(result)),
          stopSelectionProvider.overrideWith(
            () => _FakeStopSelectionNotifier(
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
