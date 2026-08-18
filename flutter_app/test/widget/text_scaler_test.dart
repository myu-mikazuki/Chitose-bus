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

/// 端末の「文字を大きくする」設定（`TextScaler`）で壊れる場所を検知する（#237）。
///
/// #231 は NEXT BUS の到着行の overflow を**字を小さくして**直したが、それは
/// **拡大設定には原理的に効かない**（倍率が同じなら同じように溢れる）。
/// 拡大を見るテストが1件も無かったため、その効かなさを誰も検知できなかった。
///
/// ## 実測した限界（375×667・#237 で実測）
///
/// **いま拡大に耐えるのは 1.05 まで。1.1 で縦が溢れる。**
///
/// | 場所 | 軸 | 溢れ始める倍率 | 停留所名の長さに依存するか |
/// |---|---|---|---|
/// | `_StopTab` の Column（節見出し＋カード＋リスト） | 縦 | **1.1** | しない |
/// | NEXT BUS カードの到着行（300px） | 横 | 1.15 | する（13文字。既定名なら 2.0） |
/// | 来週シートの到着行（303px） | 横 | 1.15 | する |
/// | 来週シートの行ヘッダ（311px） | 横 | 1.2 | しない |
/// | ホームの時刻表リストの到着行（335px） | 横 | 1.25 | する（既定名なら 2.0） |
/// | タブ（`Tab` の中の `Row`・4タブ） | 横 | **1.4** | しない |
/// | ホームの時刻表リストの行ヘッダ（343px） | 横 | 1.5 | しない |
///
/// **拡大を1段上げるだけで 1.05 を超える**（Android の「大」で 1.15）。
/// つまり実質、拡大設定を触った時点でどこかが溢れる。
///
/// issue の一覧に無かったものが3つ出た。直しはそれぞれ別 issue に切る
/// （#237 は検知までしか持たない）。
///
/// - **縦の溢れがいちばん先に来る。**issue は「幅が詰まっている場所」を
///   想定していたが、375×667 では横より縦が先に負ける
/// - **行ヘッダ（`_ScheduleRow` の折りたたみ時の `Row`）は停留所名と無関係。**
///   時刻・講義タグ・行き先・`◀ NEXT`・ベルを固定幅で並べていて縮む余地が
///   無いため、既定の4停留所でも同じ倍率で溢れる
/// - **タブは `Flexible` + ellipsis があるのに溢れる。**`_buildTab` が並べ方を
///   決めるのに使う `TextPainter`（`home_screen.dart`）に `textScaler` を
///   渡していないので、拡大時は等倍の幅で「横並びで収まる」と誤判定し、
///   `Flexible` を通らない枝を選んでしまう
///
/// ## この倍率は実機の倍率ではない
///
/// テストにはフォントが無く、1文字 = 1em の代替フォントで測る。欧文と数字は
/// 実機よりかなり幅を食う（`expectNotTruncated` の注記と同じ制約）。とくに
/// 行ヘッダは `◀ NEXT` と `09:00` が効くので、**実機で崩れ始める倍率はもっと
/// 上**のはず。ここで守っているのは「縮む余地があるか」という構造の話で、
/// 実機の限界そのものではない。
///
/// ## 下のテストは「いまの限界」を留める
///
/// **どれも通る倍率でしか主張していない。**直せば限界は上がるが、テストは
/// 緑のままでよい（下限の主張なので）。逆に**赤くなったら限界が下がった**
/// ということなので、上の表を測り直すこと。

/// 375×667 の実機並びで、まだ何も溢れない上限。1.1 で `_StopTab` の Column が
/// 縦に 14px 溢れるので、**限界のすぐ下**を踏んでいる
const _deviceLimit = 1.05;

/// 縦の余裕を与えたときに、到着行3経路が耐えられる上限。
/// 1.15 で NEXT BUS の到着行（300px・最狭）が 12px 溢れる
const _arrivalLimit = 1.1;

/// タブが耐えられる上限（4タブ）。1.4 で `Tab` の中の `Row` が 1.6px 溢れる
const _tabLimit = 1.3;

BusTimetable _timetable(String validFrom, String validTo) => BusTimetable(
      validFrom: validFrom,
      validTo: validTo,
      schedules: const [
        BusEntry(
          time: '09:00',
          boardingStopId: 'koizumi',
          destination: '科技大',
          arrivals: {
            'arcadia': '09:05',
            'hoyukai': '09:12',
            'honbuto': '09:30',
          },
        ),
        // 来週シートは選択ではなく**既定の4停留所を名指し**で並べる
        // （`_showUpcomingSheet`）。千歳駅発の便が無いとシートに行が出ず、
        // 303px / 311px の経路を素通りしてしまう
        BusEntry(
          time: '09:40',
          boardingStopId: 'chitose',
          destination: '科技大',
          arrivals: {
            'arcadia': '09:45',
            'hoyukai': '09:52',
            'honbuto': '09:58',
          },
        ),
      ],
    );

/// 到着行が出る3経路すべてを含む応答。
///
/// `upcoming` は**本番では常に null** で、カレンダーアイコンも出ないため
/// 来週シートは今のところ開けない（`_showUpcomingSheet` の TODO(#202)）。
/// それでも 303px / 311px はコード上いちばん狭い部類なので、復活したときに
/// 気づけるよう埋めてある。
final _result = ScheduleResult(
  data: ScheduleResponse(
    stopMaster: kLongStopMaster,
    updatedAt: '2024-01-01',
    current: _timetable('2024-01-01', '2024-12-31'),
    upcoming: _timetable('2025-01-01', '2025-12-31'),
  ),
);

/// 便が1本も無い応答。**タブだけを見るために使う。**
///
/// 便があるとカードと時刻表リストが先に溢れて、タブの主張まで届かない。
/// 行き先が無い停留所は `_StopHasNoBus` になり、カードもリストも描かれない
/// （`long_stop_names_test.dart` が4停留所を選んで踏んでいるのと同じ道）。
const _noBusResult = ScheduleResult(
  data: ScheduleResponse(
    stopMaster: kLongStopMaster,
    updatedAt: '2024-01-01',
    current: BusTimetable(
      validFrom: '2024-01-01',
      validTo: '2024-12-31',
      schedules: [],
    ),
  ),
);

Widget _wrap(ScheduleResult result, List<String> stopIds, double scale) =>
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
        // **MaterialApp の外に置いても効かない。**MaterialApp が自前の
        // MediaQuery を作って上書きするため、builder で内側に差し込む。
        // Navigator より上なので、来週シート（modal route）にも掛かる
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const HomeScreen(),
      ),
    );

/// [height] だけ論理ピクセルの高さを持つ 375px 幅の端末にする。
///
/// 幅を見たいテストは**わざと縦を伸ばす**。実機並びの 667px では
/// `_StopTab` の Column が 1.1 で先に縦に溢れ、横の主張まで届かない。
/// 縦と横を別のテストに分けておかないと、片方を直しても
/// もう片方に隠れて効果が見えない。
void _usePhone(WidgetTester tester, {double height = 667}) {
  tester.view.physicalSize = Size(375 * 2, height * 2);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 拡大が本当に掛かっているか見る。
///
/// **これが無いと素通りする。**MediaQuery の差し込み方を間違えると倍率 1.0 の
/// まま全部緑になり、「拡大しても壊れない」と読めてしまう。
void _expectScaleApplied(WidgetTester tester, double scale) {
  final context = tester.element(find.byType(HomeScreen));
  expect(
    MediaQuery.textScalerOf(context).scale(10),
    closeTo(10 * scale, 0.01),
    reason: 'TextScaler が HomeScreen まで届いていない',
  );
}

/// 時刻表リストの [time] の行を開く。
///
/// **`find.text(time).first` では開かない。** NEXT BUS カードが同じ時刻を
/// 出しているため、そちらを叩いてしまう。リスト側を名指しする。
Future<void> _expandRow(WidgetTester tester, String time) async {
  final row = find.descendant(
    of: find.byType(ScheduleList),
    matching: find.text(time),
  );
  expect(row, findsWidgets, reason: '時刻表リストに $time の行が無い');
  await tester.ensureVisible(row.first);
  await tester.pumpAndSettle();
  await tester.tap(row.first);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // overflow はテストが自動で失敗として拾うので、「例外なく pump できること」
  // 自体が検査になっている（`long_stop_names_test.dart` と同じ立て方）。
  group('文字拡大設定（TextScaler）', () {
    testWidgets('倍率 $_deviceLimit までは 375×667 で何も溢れない（#237）', (tester) async {
      _usePhone(tester);

      await tester.pumpWidget(_wrap(_result, ['koizumi'], _deviceLimit));
      await tester.pumpAndSettle();
      _expectScaleApplied(tester, _deviceLimit);

      // ここが赤くなったら縦がいちばん先に負ける（1.1 で `_StopTab` の
      // Column が 14px 溢れる）。**画面の高さを削る変更を拾うのが役目**
      expect(find.text('オフィス・アルカディア入口 着'), findsOneWidget);
    });

    testWidgets('縦に余裕があれば到着行は倍率 $_arrivalLimit まで持つ（3経路・#237）', (tester) async {
      _usePhone(tester, height: 1200);

      await tester.pumpWidget(_wrap(_result, ['koizumi'], _arrivalLimit));
      await tester.pumpAndSettle();
      _expectScaleApplied(tester, _arrivalLimit);

      // 1. NEXT BUS カードの到着行（300px・3経路でいちばん狭い）
      expect(find.text('オフィス・アルカディア入口 着'), findsOneWidget);

      // 2. ホームの時刻表リストの到着行（335px）と行ヘッダ（343px）
      await _expandRow(tester, '09:00');
      expect(find.text('オフィス・アルカディア入口 着'), findsNWidgets(2));

      // 3. 来週シートの到着行（303px）と行ヘッダ（311px）。
      // **カードより狭いのはこちら**なので、カードだけ見ても足りない
      await tester.tap(find.byIcon(Icons.calendar_month));
      await tester.pumpAndSettle();
      expect(find.textContaining('来週のダイヤ'), findsOneWidget);
      await _expandRow(tester, '09:40');
    });

    // タブは #177 で `Flexible` + ellipsis の枝を用意してあるが、**その枝を
    // 選ぶかどうかの判定が拡大を見ていない**（`_buildTab` の `TextPainter` に
    // `textScaler` を渡していない）。1.4 で誤判定して溢れる。
    //
    // 便を持たせないのは、カードと時刻表リストが先に溢れてここまで届かない
    // ため。`_StopHasNoBus` になればタブだけが残る。
    testWidgets('タブは倍率 $_tabLimit まで持つ（4タブ・#237）', (tester) async {
      _usePhone(tester, height: 1200);

      await tester.pumpWidget(_wrap(
        _noBusResult,
        ['koizumi', 'arcadia', 'hoyukai', 'osatsu'],
        _tabLimit,
      ));
      await tester.pumpAndSettle();
      _expectScaleApplied(tester, _tabLimit);

      // タブが4つ描かれていること（`_StopHasNoBus` でタブごと消えていない）
      expect(find.byType(Tab), findsNWidgets(4));
    });
  });
}
