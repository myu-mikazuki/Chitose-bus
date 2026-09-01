import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/core/theme/text_scale.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';
import 'package:kagi_bus/domain/entities/stop_selection.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_result.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_viewmodel.dart';
import 'package:kagi_bus/presentation/viewmodels/stop_selection_viewmodel.dart';
import 'package:kagi_bus/presentation/views/home_screen.dart';
import 'package:kagi_bus/presentation/views/widgets/next_bus_display.dart';
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
/// ## 実測した限界（375px・#237）
///
/// **どちらの列も「溢れ始める（切れ始める）倍率」。**このファイルのテストが
/// 踏むのはその**1段下**（`_deviceLimit` / `_arrivalLimit` / `_tabLimit`）なので、
/// 表の値とテストの定数は一致しない。
///
/// **実機の目安は「実フォント」の列。**テスト用フォントの列は**実機よりかなり
/// 厳しく出る**（下の「測り方」を参照）が、下のテストが踏んでいるのはこちらなので
/// 両方載せる。
///
/// | 場所 | 軸 | テスト用フォント | **実フォント** | 名前に依存 | 直し |
/// |---|---|---|---|---|---|
/// | ~~節の見出し（`◯◯ 発`）が切れる（既定＝短縮名）~~ | 横 | ~~1.0~~ | **2.0 まで無傷** | ~~する~~ | **#245 で解消** |
/// | ~~NEXT BUS カードの到着行（300px）~~ | 横 | ~~1.15~~ | **2.0 まで無傷** | ~~する~~ | **#241 で解消** |
/// | ~~タブ（`Tab` の中の `Row`・4タブ）~~ | 横 | ~~1.4~~ | ~~1.4~~ | しない | **#243 で解消** |
/// | ~~`_StopTab` の Column（375×667・**閉じた状態**）~~ | 縦 | ~~1.1~~ | **2.0 まで無傷** | しない | **#240 で解消** |
/// | ~~`_StopTab` の Column（**到着行を1つ開いた状態**）~~ | 縦 | ~~—~~ | **2.0 まで無傷** | しない | **#240 で解消** |
/// | ~~`_StopTab` の Column（**到着行を全部開いた状態**）~~ | 縦 | ~~—~~ | **2.0 まで無傷** | しない | **#240 で解消** |
/// | ~~ホームの時刻表リストの到着行（335px）~~ | 横 | ~~1.25~~ | **2.0 まで無傷** | ~~する~~ | **#241 で解消** |
/// | ~~ホームの時刻表リストの行ヘッダ（343px）~~ | 横 | ~~1.5 ／ 1.35~~※ | **2.0 まで無傷** | しない | **#242 で解消** |
/// | ~~来週シートの到着行（303px）~~ | 横 | ~~1.15~~ | ~~未計測~~ | ~~する~~ | **#241 で解消** |
/// | ~~来週シートの行ヘッダ（311px）~~ | 横 | ~~1.18~~ | 未計測 | しない | **#242 で解消** |
///
/// ※ **行ヘッダの代替フォントの値は測り方で変わる。** 1.5 は #237 の時点の値、
/// 1.35 は `_result` で `HomeScreen` を丸ごと pump したときの値だった。
/// 講義タグが出るかどうかなど、行の中身で変わる。**#242 で中間3つを `Wrap` に
/// 入れて 1.7 まで上がった**（1.8 で 4.5px 溢れる。二分して確かめた）。
/// **この欄の数字を信じず、触るときは自分で測り直すこと。**
///
/// > **「実機では等倍（1.0）で壊れる場所は無い」は誤りだった（#251）。**
/// > **研究棟タブは 375×667・等倍・無操作で 17px 縦に溢れる。**2方向ある
/// > 停留所は `SegmentedButton` が出て縦を約40px 食うが、**このファイルの
/// > テストも `text_scale_probe_test.dart` も乗車地を `koizumi`（1方向）でしか
/// > 採っておらず、その分が勘定に入っていなかった。** v1.3.1 にも存在する。
/// > **#251 では2方向の停留所を両方のテストに足すこと。**
///
/// 下の表は**拡大設定に関する限界**で、等倍の話（#251）はこの表の外にある。
/// **`_StopTab` の縦は #240 で解消し、到着行を全部開いた状態でも
/// 2.0 まで overflow が出ない**（詳しくは下）。
///
/// **到着行（#241）・タブ（#243）・節の見出し（#245）は解消済み。**表には
/// 経緯として残してある。**「溢れる」の主張自体が意味を失った**——3つとも
/// 既定表示を短縮名（最長5文字）に戻したので、もう「名前に依存して溢れる」
/// 場所ではない。実フォントで **2.0 まで横の overflow は出ない**（到着行は
/// 開いた状態を含む）。
///
/// **節の見出し（#245）は「タップした後」を別に測っている。**既定（短縮名）は
/// 2.0 まで無傷だが、**タップして正式名を出した状態は元のまま 1.15 から
/// 切れる**（`text_scale_probe_test.dart` で確認）。これは**意図した仕様**——
/// 正式名は「タップすれば必ず全部読める」ことだけを約束していて、
/// 高倍率まで1行に収まることは約束していない（`_StopSectionHeader` の
/// ドキュメントコメント参照）。
///
/// **入れ替わりに2つが動いた。**
///
/// 1. **代替フォントでは、行ヘッダ（#242）が `_arrivalLimit` を主張する
///    テストの中でいちばん先に負けるようになった**（1.18）。**#242 で
///    解消し、いまは 1.7 まで持つ**（詳しくは `_arrivalLimit` のコメント）
/// 2. **実フォントでは、`_StopTab` の縦（#240）が下がった。**
///    タップで出す行のぶん縦が伸びるので、1つ開くと 1.5 → **1.4**、
///    全部（カード3行＋リスト3行）開くと **1.3**。**Android の「最大」に
///    ちょうど届いていた**ので、#240 の優先度はこの計測で上がり、
///    このPRで解消した（下の [kVerticalScrollThreshold] を参照）。
///
/// **どちらも #241 が作った穴ではなく、#241 が横を塞いだ結果として
/// 表に出たもの。**縦（#240）は元から 1.5 で負けていたが、**このPRで
/// 1.3 まで余白を詰め（(a)）、それを超えたら `_StopTab` ごとスクロールに
/// 切り替える（(c)）ことで、2.0 まで溢れなくなった。**
///
/// issue の一覧に無かったものが4つ出た（#237 は検知までしか持たない）。
///
/// - **タブは `Flexible` + ellipsis があるのに溢れていた**（#243・**解消済み**）。
///   `_buildTab` が並べ方を決めるのに使う `TextPainter`（`home_screen.dart`）に
///   `textScaler` を渡しておらず、拡大時は等倍の幅で「横並びで収まる」と誤判定して
///   `Flexible` を通らない枝を選んでいた。**渡すようにしたので溢れなくなり、
///   限界は「読めなくなる」（2.5 で `古…`）に変わった**
/// - **節の見出しは溢れずに黙って切れる**（#245・**解消済み**）。
///   `Expanded` + ellipsis なので **overflow では原理的に拾えない**。既定を
///   短縮名に戻し、正式名はタップで出す形にしたことで、#208 の「削らずに
///   正式名を出す」は「常に出す」から「タップすれば必ず出る」に置き換わった
/// - **行ヘッダ（`_ScheduleRow` の折りたたみ時の `Row`）は停留所名と無関係**
///   （#242・**解消済み**）。時刻・講義タグ・行き先・`◀ NEXT`・ベルを固定幅で
///   並べていて縮む余地が無く、既定の4停留所でも同じ倍率で溢れていた。
///   **中間の3つ（系統タグ・講義タグ・行き先）を `Wrap` に入れ、`Spacer` を
///   `Expanded` に置き換えた**ので、等倍の見え方を変えずに折り返せるように
///   なった（`◀ NEXT` とベルは右端のまま）
/// - **縦にも溢れる**（#240・**解消済み**）。issue は「幅が詰まっている場所」を
///   想定していたが、`_StopTab` の `Column` は縦にも溢れていた。拡大時だけ
///   余白を詰め（1.3 まで）、それでも足りない分は `_StopTab` ごと
///   スクロールに切り替えることで直した
/// - **到着行は解消済み**（#241）。#231 → #234 と2回続けて字を小さくする／
///   正式名にする、と対症療法を重ねていたが、拡大設定そのものには効いて
///   いなかった。既定を短縮名に戻し、正式名をタップで出す形にしたことで、
///   幅の問題が構造的に消えた
///
/// **上の実フォントの列は #241 / #245 / #240 / #242 をすべて入れた後に
/// 測り直したもの**（Meiryo・375px）。**4件が揃った結果、probe の範囲では
/// 2.0 まで overflow が1つも出ない。** probe には「到着行を開く」
/// 「見出しをタップして正式名を見る」の2手を足してある
/// （`text_scale_probe_test.dart`）。
/// **来週シートの行ヘッダ（311px）だけは実フォント未計測** — probe が
/// カレンダーアイコンを叩かないため。#202 でシートが復活したら測ること。
///
/// ## 測り方（表を測り直すときはこれ）
///
/// **`flutter test` にはフォントが無く、1文字 = 1em の代替フォントで測る。**
/// 欧文と数字は実機よりかなり幅を食う（`NEXT BUS` が 82px → 120px。
/// `expectNotTruncated` の注記と同じ制約）。CJK は全角固定なので停留所名そのものの
/// 幅はほぼ正しく、**ずれるのは欧文・数字を含む行**。節の見出しは `NEXT BUS` と
/// 同じ行にあるため影響がいちばん大きく、**PR #244 では「375px では等倍でも
/// 切れている」と誤って読んでいた**（実フォントでは 1.15 まで持つ）。
///
/// 実フォントの列は `test/tools/text_scale_probe_test.dart` で採る。手順は
/// `doc/text-scale-measurement.md`。**Android の Noto Sans CJK / iOS のヒラギノとは
/// 完全には一致しない**ので、実フォントの列もあくまで目安。
///
/// ## 下のテストは「いまの限界」を留める
///
/// **どれも通る倍率でしか主張していない。**直せば限界は上がるが、テストは
/// 緑のままでよい（下限の主張なので）。逆に**赤くなったら限界が下がった**
/// ということなので、上の表を測り直すこと。
///
/// **裏を返すと、上の表そのものはテストで固定していない。**「1段上で本当に
/// 溢れる」ことは誰も見ていないので、**#240〜#243 を直したときに定数と表を
/// 更新し忘れても緑のまま通る**。直したら必ずここを測り直すこと。
/// 上限側も主張すると直した瞬間に赤くなるので、あえて入れていない。

/// 375×667 の実機並びで、閉じたままなら何も溢れない上限（#240）。
///
/// #240 で余白を詰めるようになったので、**Android の「最大」(1.3) まで
/// そのまま踏める。**
///
/// **これ以上は上げられない**——[kVerticalScrollThreshold] が 1.3 なので、
/// 1.3 を超えると (c) の全体スクロールに切り替わる。**この定数を使うテストは
/// 「`SingleChildScrollView` が無いこと」＝ (a) だけで足りていることを
/// 主張している**ので、上げると自己矛盾になる。しきい値より上は
/// 「しきい値を超えたら (c) が働く」の側のテストで見ている。
const _deviceLimit = 1.3;

/// 375×667 の実機並びで、**到着行を1つ開いた状態**でも何も溢れない上限
/// （#240・「到着行を1つ開いた状態でも溢れない」ことの担保）。
///
/// #241 でタップすると1行下に正式名を出すようになった分、縦が伸びる。
/// #240 の余白詰めはこの伸びた分も含めて 1.3 まで吸収するよう調整してある
/// ので、[_deviceLimit]（閉じたまま）と同じ値まで踏める。これ以上上げられない
/// 理由も [_deviceLimit] と同じ（しきい値を超えると (c) に切り替わる）。
const _deviceLimitArrivalOpen = 1.3;

/// 縦の余裕を与えたときに、**ホーム画面の横**が耐えられる上限。
///
/// **名前は「到着行」だが、いま実際に限界を決めているのは行ヘッダのほう。**
/// #241 で到着行の既定表示を短縮名（最長5文字）に戻して以来、到着行はここで
/// 先に負けなくなった。**残っているのは `_ScheduleRow` の行ヘッダで、
/// 時刻(18px)・`◀ NEXT`(12px)・ベル(24px アイコン)という縮まない3つ**が
/// 幅を決めている。
///
/// **#242 で 1.35 → 1.7 まで上がった。**中間の3つ（系統タグ・講義タグ・
/// 行き先）を `Wrap` に入れて折り返すようにしたため。1.8 で 4.5px 溢れる。
///
/// **この値は系統タグ（`routeLabel`）を持つ便で測ったもの。** 実データ
/// （`gas/Code.gs`）の便は `空港経由` / `直通` / `長都発` / `長都行き` の
/// いずれかを持つが、**fixture がタグ無しだったため実態より甘い条件で
/// 測っていた**（PR #254 のレビュー指摘）。`_result` に持たせて測り直した
/// 結果、**溢れ始める倍率は 1.8 のまま変わらなかった**——`Wrap` は
/// 折り返せるので、タグが増えても overflow の側には効かない。
/// **効いていたのは見た目のほう**で、1.65 あたりからタグの中の文字が
/// 2行に割れていた（`maxLines: 1` + ellipsis で直した。下の
/// 「系統タグと行き先は高倍率でも1行のまま」で留めている）。
///
/// **1.8 以上を狙って `◀ NEXT` も `Wrap` に入れるのはやめた**（#242）。
/// 右端から離れて**等倍の見え方が変わる**のに対し、Android の上限は 1.3 で
/// 1.7 はすでに遥かに超えている。**実機が到達しない倍率のために等倍の
/// 見た目を崩すのは割に合わない。**
///
/// 高倍率で `ArrivalRow` 自体が溢れないことは、行ヘッダに邪魔されない
/// `NextBusDisplay` 単体のテスト（下の「到着行の展開は高倍率でも溢れない」）
/// で別に見ている。
const _arrivalLimit = 1.7;

/// タブが耐えられる上限（4タブ）。**#243 を直してから溢れなくなった**ので、
/// いま留めているのは**読めるかどうか**のほう。2.5 で `古泉` が `古…` になる。
/// 溢れるほうは 3.0 まで確認して出ていない
const _tabLimit = 2.0;

BusTimetable _timetable(String validFrom, String validTo) => BusTimetable(
      validFrom: validFrom,
      validTo: validTo,
      schedules: const [
        BusEntry(
          time: '09:00',
          // **実データは系統タグを持つ**（`gas/Code.gs` の `空港経由` /
          // `直通` / `長都発` / `長都行き`）。**タグの無い便で幅の限界を測ると
          // 実態より甘く出る**ので fixture にも持たせる（PR #254 の指摘・#242）
          routeLabel: '空港経由',
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
          // **実データは系統タグを持つ**（`gas/Code.gs` の `空港経由` /
          // `直通` / `長都発` / `長都行き`）。**タグの無い便で幅の限界を測ると
          // 実態より甘く出る**ので fixture にも持たせる（PR #254 の指摘・#242）
          routeLabel: '空港経由',
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

/// 節の見出し**だけ**を見るための応答（#245）。
///
/// `_result` をそのまま使うと、`NEXT BUS` の下に `ScheduleList` の行
/// （`_ScheduleRow`）も一緒に描かれる。この行は時刻・講義タグ・行き先・
/// `◀ NEXT`・ベルを固定幅で並べていて縮む余地が無く、**停留所名と無関係に**
/// 溢れていた（#242 を直す前は代替フォントの 1.18 あたりから）。節の見出しの
/// 主張（1.5 倍まで省略されない）を確かめたいだけなのに、無関係な行ヘッダの
/// overflow 例外に巻き込まれてテストごと落ちてしまう（実際に踏んだ）。
///
/// **#242 を直して 1.7 まで持つようになったので、いまなら `_result` でも
/// 1.5 は通る。**それでも分けたままにしてあるのは、**ここで見たいのが
/// 見出しだけ**だから——行ヘッダの限界が将来また下がったときに、
/// 見出しのテストが巻き添えで赤くなるのは筋が悪い。
///
/// **`weekendOnly: true` で回避する。** `_StopTab.destinations`
/// （`home_screen.dart`）は `runsOn` を見ずに生の `schedules` を走査するだけ
/// なので、これでも見出しは変わらず出る。一方 `NextBusDisplay` /
/// `ScheduleList` は `runsOn` で絞るので、平日固定の `kTestNow`
/// （2024-06-17・月曜）では**当日の便が無い**扱いになり、`_ScheduleRow` も
/// `ArrivalRow` も描かれない（「本日の運行は終了しました」/
/// 「時刻表データなし」のような静的な置き換え文言だけになる）。
final _headerOnlyResult = ScheduleResult(
  data: ScheduleResponse(
    stopMaster: kLongStopMaster,
    updatedAt: '2024-01-01',
    current: const BusTimetable(
      validFrom: '2024-01-01',
      validTo: '2024-12-31',
      schedules: [
        BusEntry(
          time: '09:00',
          // **実データは系統タグを持つ**（`gas/Code.gs` の `空港経由` /
          // `直通` / `長都発` / `長都行き`）。**タグの無い便で幅の限界を測ると
          // 実態より甘く出る**ので fixture にも持たせる（PR #254 の指摘・#242）
          routeLabel: '空港経由',
          boardingStopId: 'koizumi',
          destination: '科技大',
          weekendOnly: true,
          arrivals: {'honbuto': '09:30'},
        ),
      ],
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

      // ここが赤くなったら縦がいちばん先に負ける。#240 で余白を詰めるように
      // なる前は 1.1 で `_StopTab` の Column が 14px 溢れていた。
      // **画面の高さを削る変更を拾うのが役目**。
      // #241 で到着行の既定表示は短縮名に戻したので `O･A入口 着`
      expect(find.text('O･A入口 着'), findsOneWidget);

      // **節見出し（`◯◯ 発`）はここでは見ない。**`Expanded` + ellipsis なので
      // 溢れずに黙って切れる＝ overflow では原理的に拾えない。#245 で既定を
      // 短縮名に戻したので、その主張は下の別テストで倍率ごとに切って見る

      // $_deviceLimit は #240 のしきい値（[kVerticalScrollThreshold]）ちょうど
      // ——この範囲は (a) 余白を詰めるだけで凌ぐ。(c) の全体スクロールへの
      // 切り替えはまだ起きていないはず。**`SingleChildScrollView` の有無では
      // 判定できない**——`ScheduleList` は有界（`Expanded` 配下）でも自前の
      // `SingleChildScrollView` を使うため、(a)/(c) どちらでも1つは見つかる。
      // ここでは「`NextBusDisplay` が `SingleChildScrollView` の中に無い」
      // ことで判定する（(c) なら `_StopTab` 全体を包む外側のものの中に入る）
      expect(
        find.ancestor(
          of: find.byType(NextBusDisplay),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );
    });

    // #240 で増えた主張。「閉じたまま」だけでなく**到着行を1つ開いた状態**
    // （#241 でタップすると出るようになった正式名の行）でも 667px の縦に
    // 収まることを見る。開くのは NEXT BUS カードの `ArrivalRow` 1つだけ——
    // `text_scale_probe_test.dart` の実測（「到着行を1つ開く」）と同じ操作。
    // 時刻表リストの行も一緒に開こうとすると、伸びた分でスクロール位置が
    // ずれて `_expandRow` の tap 座標が外れることがあった（実際に踏んだ）ため、
    // ここでは1手に絞る。時刻表リスト側は倍率が (a) の範囲内なら影響しない
    // （行そのものの高さは変わらない。伸びるのはタップして開いたときだけ）。
    testWidgets(
        '到着行を1つ開いた状態でも倍率 $_deviceLimitArrivalOpen までは 375×667 で何も溢れない（#240）',
        (tester) async {
      _usePhone(tester);

      await tester
          .pumpWidget(_wrap(_result, ['koizumi'], _deviceLimitArrivalOpen));
      await tester.pumpAndSettle();
      _expectScaleApplied(tester, _deviceLimitArrivalOpen);

      // NEXT BUS カードの到着行を1つ開く
      final cardArrival = find
          .descendant(
            of: find.byType(NextBusDisplay),
            matching: find.text('O･A入口 着'),
          )
          .first;
      await tester.tap(cardArrival);
      await tester.pumpAndSettle();
      expect(find.text('オフィス・アルカディア入口'), findsOneWidget);

      // ここも (a) の範囲（しきい値ちょうど）。まだ (c) には切り替わっていない
      // （上のテストと同じ理由で `NextBusDisplay` の祖先で判定する）
      expect(
        find.ancestor(
          of: find.byType(NextBusDisplay),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );
    });

    // #240 の (c)。しきい値（[kVerticalScrollThreshold]）を超えたら、余白を
    // 詰めるのをやめて `_StopTab` ごとスクロールに切り替わる。上の2件が
    // しきい値「以下」（(a) だけで凌ぐ）を見ているのに対し、こちらは
    // しきい値の「上」を見る（4-17: 上と下の両方をテストする）。
    //
    // #240 を直す前は、実フォントで 2.0 のとき 323px、代替フォントではもっと
    // 早い段階から数十〜百px級で `_StopTab` の Column が縦に溢れていた
    // （`kVerticalScrollThreshold` のドキュメントコメント参照）。
    //
    // **`_headerOnlyResult`（中身が軽い）を使うため、ここでは overflow の
    // 有無では (c) が働いたかどうかを判定できない**——中身が軽いと、(c) が
    // 働かず (a) の余白詰めだけでもこの倍率では溢れない可能性がある
    // （`_result` を使わない理由は下）。**判定は `SingleChildScrollView` の
    // 有無でする。**なお `Column` は `SingleChildScrollView` の中でしか
    // 無限の高さを許されない（`Expanded` は使えない）ので、構造として
    // 「(c) に切り替わっていれば縦に溢れない」は変わらず成り立つ。
    //
    // **`_headerOnlyResult` を使う。**`_result`（ScheduleList に行がある）を
    // 使うと、この倍率では #242（時刻表リストの行ヘッダ・未着手）が
    // 停留所名と無関係に横へ溢れ、無関係な例外に巻き込まれてテストごと
    // 落ちる（`_arrivalLimit` の上のテストが `_headerOnlyResult` を使う
    // 理由と同じ）。ここで見たいのは `_StopTab` が (c) に切り替わって
    // 縦に溢れないことだけなので、行ヘッダの無い応答を使う。
    testWidgets(
        '倍率が $kVerticalScrollThreshold を超えたら画面ごとスクロールに切り替わり溢れない（#240 の (c)）',
        (tester) async {
      const scale = kVerticalScrollThreshold + 0.2;
      _usePhone(tester);

      await tester.pumpWidget(_wrap(_headerOnlyResult, ['koizumi'], scale));
      await tester.pumpAndSettle();
      _expectScaleApplied(tester, scale);

      // (c) が働いている証拠。`NextBusDisplay` が `SingleChildScrollView`
      // の中に入っている——(a) だけの範囲（$_deviceLimit 以下）ではこうならない
      // （上の2件と対になる判定。`ScheduleList` 自前の `SingleChildScrollView`
      // と混同しないための立て方は上のテストの注記を参照）
      expect(
        find.ancestor(
          of: find.byType(NextBusDisplay),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      expect(find.text('古泉 発'), findsOneWidget);
    });

    // #124 の「800x600 で溢れる」を踏まえて、拡大時もそこを見ておく。
    // `_usePhone` を呼ばなければ `flutter test` の既定の論理サイズ（800x600）
    // のまま pump される。375×667 より幅は広いが高さは低く、横に余裕がある分
    // 縦の伸びは375px幅より小さいはずだが、**縦が低い**ことに変わりはないので
    // 別に見ておく。
    testWidgets('800x600（#124）でも到着行を1つ開いた状態で倍率 $_deviceLimitArrivalOpen まで溢れない',
        (tester) async {
      await tester
          .pumpWidget(_wrap(_result, ['koizumi'], _deviceLimitArrivalOpen));
      await tester.pumpAndSettle();
      _expectScaleApplied(tester, _deviceLimitArrivalOpen);

      final cardArrival = find
          .descendant(
            of: find.byType(NextBusDisplay),
            matching: find.text('O･A入口 着'),
          )
          .first;
      await tester.tap(cardArrival);
      await tester.pumpAndSettle();
      expect(find.text('オフィス・アルカディア入口'), findsOneWidget);
    });

    // #245 で新しく足した主張。**この計画の前の版では「代替フォントだと
    // 等倍でも切れるので `expectNotTruncated` を置けない」としていたが、
    // 既定を短縮名に戻したことでこれが解ける。** 代替フォントでも
    // `NEXT BUS`(120px) + `SizedBox(12)` + `古泉 発`(短縮名・約70px) ≒ 202px
    // で、375px の行（左右16ずつを引いて343px）に対し **1.5倍でも 297px
    // で収まる**。
    //
    // **2.0 は入れない。**(120+70)×2.0 + 12 = 392px > 343px で
    // **代替フォントでは落ちる**（実フォントなら通る。実測は
    // doc/roadmap.md の「#237 で分かったこと」）。ここを足すと「実機は
    // 無事なのにテストだけ赤い」状態になる
    //
    // **高さは 667px（実機並び）を使わない。**#240 を直す前は 1.1 で
    // `_StopTab` の Column が縦に溢れ、1.15 / 1.5 で高さ 667 のまま pump すると
    // 見出しとは無関係な縦の overflow 例外に巻き込まれてテストごと落ちていた
    // （実際に踏んだ）。#240 で 1.3 まで（このテストなら中身が軽いのでもっと
    // 上まで）溢れなくなったが、ここで見たいのは横だけなので、`_arrivalLimit`
    // のテストと同じく引き続き縦に余裕を持たせておく
    //
    // **`_result` も使わない。**`HomeScreen` を丸ごと pump すると
    // `ScheduleList` の行ヘッダが停留所名と無関係に溢れ、見出しとは無関係な
    // 例外に巻き込まれてテストごと落ちていた（実際に踏んだ）。見出しは出したいが
    // 行は出したくないので、`_headerOnlyResult`（`weekendOnly: true` で当日の便を
    // 意図的に0件にしたもの）を使う——`destinations` は `runsOn` を見ないので
    // 見出しは出る。
    //
    // **#242 で行ヘッダは 1.35 → 1.7 まで持つようになったので、いまなら
    // `_result` でも 1.5 は通る。**それでも分けたままにしてあるのは、
    // **ここで見たいのが見出しだけ**だから——行ヘッダの限界が将来また
    // 下がったときに、見出しのテストが巻き添えで赤くなるのは筋が悪い
    // （`_arrivalLimit` の側で別に見ている）
    for (final scale in [1.0, 1.15, 1.5]) {
      testWidgets('節の見出しは既定（短縮名）なら倍率 $scale で省略されない（#245）', (tester) async {
        _usePhone(tester, height: 1200);

        await tester.pumpWidget(_wrap(_headerOnlyResult, ['koizumi'], scale));
        await tester.pumpAndSettle();
        _expectScaleApplied(tester, scale);

        expect(find.text('古泉 発'), findsOneWidget);
        expectNotTruncated(tester, '古泉 発');
      });
    }

    testWidgets('縦に余裕があれば到着行は倍率 $_arrivalLimit まで持つ（3経路・#237）', (tester) async {
      _usePhone(tester, height: 1200);

      await tester.pumpWidget(_wrap(_result, ['koizumi'], _arrivalLimit));
      await tester.pumpAndSettle();
      _expectScaleApplied(tester, _arrivalLimit);

      // 1. NEXT BUS カードの到着行（300px・3経路でいちばん狭い）。
      // #241 で既定表示は短縮名に戻したので `O･A入口 着`
      expect(find.text('O･A入口 着'), findsOneWidget);

      // 2. ホームの時刻表リストの到着行（335px・#241）と行ヘッダ（343px・#242）
      await _expandRow(tester, '09:00');
      expect(find.text('O･A入口 着'), findsNWidgets(2));

      // 3. 来週シートの到着行（303px・#241）と行ヘッダ（311px・#242）。
      // **到着行はカード（300px）が最狭**だが、**行ヘッダはこちらが最狭**
      // （ホームのリストは 343px）。ホームだけ見ても #242 には届かない
      await tester.tap(find.byIcon(Icons.calendar_month));
      await tester.pumpAndSettle();
      expect(find.textContaining('来週のダイヤ'), findsOneWidget);
      await _expandRow(tester, '09:40');
      // **数えないと素通りする。**`_expandRow` は行があることしか見ておらず、
      // タップが外れても警告止まりなので、シートの到着行が描かれないまま
      // 緑で通ってしまう。カード1 ＋ ホームのリスト1 ＋ シート1 で3つ
      expect(find.text('O･A入口 着'), findsNWidgets(3));
    });

    // **「溢れない」と「読める」は別**（#242 / PR #254 のレビュー指摘）。
    //
    // `Wrap` の子は「その行に入るところまで」の幅しか貰えないので、拡大時に
    // 系統タグの `空港経由` が `空港経` / `由` の2行に割れ、**タグの枠が
    // 崩れていた**。`Wrap` は折り返せてしまうぶん overflow 例外を出さないので、
    // **テストは緑のまま見た目だけ壊れる**——`_arrivalLimit` の側では
    // 原理的に拾えない。`maxLines: 1` + ellipsis で直したが、
    // **消されても気づけないので、ここで1行に収まっていることを主張する。**
    testWidgets('系統タグと行き先は高倍率でも1行のまま（#242）', (tester) async {
      _usePhone(tester, height: 1200);
      await tester.pumpWidget(_wrap(_result, ['koizumi'], _arrivalLimit));
      await tester.pumpAndSettle();

      final scaler =
          MediaQuery.textScalerOf(tester.element(find.byType(HomeScreen)));

      // 系統タグ（10px）。2行になっていれば高さが2倍近くになる
      final tag = tester.renderObject<RenderParagraph>(
        find
            .descendant(
              of: find.byType(ScheduleList),
              matching: find.text('空港経由'),
            )
            .first,
      );
      expect(tag.size.height, lessThan(scaler.scale(10) * 2),
          reason: '系統タグが2行に割れている');

      // 行き先（14px）
      final dest = tester.renderObject<RenderParagraph>(
        find
            .descendant(
              of: find.byType(ScheduleList),
              matching: find.text('科技大'),
            )
            .first,
      );
      expect(dest.size.height, lessThan(scaler.scale(14) * 2),
          reason: '行き先が2行に割れている');

      // 講義タグ（10px）。**系統タグと同じ構えなので同じ壊れ方をする。**
      // ラベルは最長3文字（`昼休み` / `放課後`）で系統タグの4文字
      // （`空港経由`）より短いぶん余裕はあるが、**保護は3つとも別々に
      // 書いてあるので1つずつ見る**（PR #254 のレビュー指摘）
      final lecture = tester.renderObject<RenderParagraph>(
        find
            .descendant(
              of: find.byType(ScheduleList),
              matching: find.text('2講'),
            )
            .first,
      );
      expect(lecture.size.height, lessThan(scaler.scale(10) * 2),
          reason: '講義タグが2行に割れている');
    });

    // #241 の「どの倍率でも溢れない」を主張する場所。`_arrivalLimit` の上の
    // テストは `HomeScreen` 経由なので、**行ヘッダ（#242）が先に溢れて
    // それより上を試せない**（#242 を直した後でも 1.8 が上限）。ここは
    // `NextBusDisplay` を単体で pump するので行ヘッダの制約を受けず、
    // **展開行（`ArrivalRow` がタップで出す正式名の行）そのものが高倍率でも
    // 溢れないこと**だけを見られる。
    //
    // 300px（3経路でいちばん狭い）に、最長13文字の正式名
    // （`オフィス・アルカディア入口`）を持つ停留所を当てて、2.0 まで見る。
    // 展開行は `Wrap` にしてあるので、収まらなければ2行目に流れるだけで
    // 例外にはならない——ここで拾いたいのはそれが本当に効いているかどうか
    testWidgets('到着行の展開は高倍率でも溢れない（NEXT BUS カード単体・#241）', (tester) async {
      final timetable = _timetable('2024-01-01', '2024-12-31');

      await tester.pumpWidget(MaterialApp(
        theme: buildTestTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2.0)),
          child: child!,
        ),
        home: ProviderScope(
          overrides: [countdownOverride(now: DateTime(2024, 6, 17, 8, 0))],
          child: Scaffold(
            body: Padding(
              // NEXT BUS カードの実測どおり、外の Padding(16) を再現する
              padding: const EdgeInsets.all(16),
              child: NextBusDisplay(
                timetable: timetable,
                stopId: 'koizumi',
                stopMaster: kLongStopMaster,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // 既定は短縮名
      final row = find.text('O･A入口 着');
      expect(row, findsOneWidget);

      // タップして正式名の行を展開する。ここで overflow していれば
      // tester が例外として拾う
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(find.text('オフィス・アルカディア入口'), findsOneWidget);
    });

    // タブは #177 で `Flexible` + ellipsis の枝を用意してあるが、**その枝を
    // 選ぶかどうかの判定が拡大を見ていなかった**（`_buildTab` の `TextPainter`
    // に `textScaler` を渡していない）。1.4 で誤判定して溢れていた（#243）。
    //
    // **直したので、タブの限界は「溢れる」から「読めなくなる」に変わった。**
    // 縮小経路（11px + ellipsis）に正しく落ちるようになり、**3.0 まで
    // 溢れない**（確認した範囲）。代わりに 2.5 で `古泉` が `古…` になる。
    // ここで留めているのは**溢れないこと**と**読めること**の両方。
    //
    // 便を持たせないのは、カードと時刻表リストが先に溢れてここまで届かない
    // ため。`_StopHasNoBus` になればタブだけが残る。
    // **しきい値を超えたら余白を詰めるのをやめる**（#240 / PR #252 のレビュー指摘）。
    //
    // `kVerticalScrollThreshold` を超えると `_StopTab` は全体スクロール（(c)）に
    // 切り替わる。**縦はいくらでも使えるので、そこで余白を詰める理由が無い。**
    // ところが `_NextBusCard` は `verticalSqueezeFactor` を直に呼んでいたため、
    // 下限（35%）で頭打ちになった倍率をそのまま使い続けていた——**タブ側の
    // 余白は元に戻るのに、カードの中だけ詰まったまま**という状態になっていた。
    //
    // 判定を `verticalSqueezeOf` に引き取って直したが、**直しただけでは
    // 検知できない**（このファイル全体と同じ性質）ので、ここで留める。
    //
    // **`HomeScreen` 経由では見られない。** 1.5 まで上げると行ヘッダ（#242・
    // 未着手）の overflow に巻き込まれて落ちる。カードの余白は `MediaQuery` の
    // 倍率だけで決まるので、`NextBusDisplay` を単体で pump すれば足りる
    // （「到着行の展開は高倍率でも溢れない」と同じ作法）。
    testWidgets('しきい値を超えたらカードの余白は詰めない（#240）', (tester) async {
      double cardVerticalPadding() {
        final container = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(NextBusDisplay),
                matching: find.byType(Container),
              )
              .first,
        );
        return (container.padding! as EdgeInsets).vertical;
      }

      Future<void> pumpAt(double scale) async {
        await tester.pumpWidget(MaterialApp(
          theme: buildTestTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: ProviderScope(
            overrides: [countdownOverride(now: DateTime(2024, 6, 17, 8, 0))],
            child: Scaffold(
              body: SingleChildScrollView(
                child: NextBusDisplay(
                  timetable: _timetable('2024-01-01', '2024-12-31'),
                  stopId: 'koizumi',
                  stopMaster: kLongStopMaster,
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
      }

      // 等倍。詰めないので素の 24*2
      await pumpAt(1.0);
      final atOne = cardVerticalPadding();
      expect(atOne, 48.0, reason: '等倍では 24*2 のまま');

      // しきい値の下。詰まっていること
      await pumpAt(1.2);
      expect(cardVerticalPadding(), lessThan(atOne), reason: 'しきい値の下では詰まる');

      // しきい値の上。**等倍と同じに戻る**——スクロールに切り替わるので
      // 詰める理由が無い
      await pumpAt(1.5);
      expect(cardVerticalPadding(), atOne, reason: 'しきい値の上ではスクロールに任せ、余白は詰めない');
    });

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

      // **溢れないことと読めることは別。**#243 を直すと縮小経路
      // （`Flexible` + ellipsis・11px）に落ちるので、溢れなくなった代わりに
      // `古…` になる、という結果を分けて見られるようにしておく
      expectNotTruncated(tester, '古泉');
    });
  });
}
