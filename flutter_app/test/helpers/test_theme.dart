import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kagi_bus/core/theme/app_theme.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_viewmodel.dart';

/// テスト用共通テーマ
ThemeData buildTestTheme() => AppTheme.dark();

/// テスト用固定時刻 (2024-06-17 月曜 09:00)
///
/// 平日・授業期・年末年始以外、という「特例なし」の日を選んでいる。
/// 以前は 2024-01-01 だったが、年末年始（12/31〜1/3）が全便運休となったため
/// 全便が絞り込みで消える日付になった（Issue #132）。
final kTestNow = DateTime(2024, 6, 17, 9, 0);

/// countdownProviderを固定時刻にオーバーライドするOverride
Override countdownOverride({DateTime? now}) => countdownProvider.overrideWith(
      (ref) => CountdownNotifier(ref)..state = now ?? kTestNow,
    );

/// [now] から [minutesAhead] 分後のHH:MM文字列を返す（日付跨ぎを23:58にキャップ）
/// [now] を省略すると kTestNow を使用する（countdownOverride と整合させるため）
String safeFutureHhmm(int minutesAhead, {DateTime? now}) {
  final base = now ?? kTestNow;
  final totalMins = base.hour * 60 + base.minute + minutesAhead;
  final capped = totalMins < 24 * 60 ? totalMins : 23 * 60 + 58;
  return '${(capped ~/ 60).toString().padLeft(2, '0')}:${(capped % 60).toString().padLeft(2, '0')}';
}

/// 表示名の供給元。ハードコードの対応表を置き換えたもの（#177）。
/// **既定の4停留所の見え方は変えない**ため、旧対応表と同じ文字列を返す
const kTestStopMaster = [
  BusStop(id: 'chitose', label: '千歳駅前', shortLabel: '千歳駅'),
  BusStop(id: 'minamiChitose', label: '南千歳駅', shortLabel: '南千歳'),
  BusStop(id: 'kenkyuto', label: '科技大研究棟', shortLabel: '研究棟'),
  BusStop(id: 'honbuto', label: '科技大本部棟', shortLabel: '本部棟'),
];

/// [text] がその場で**省略されずに**出ていることを見る。
///
/// `find.text` は `Text.data` を照合するので、`ellipsis` で `古泉循環器…` に
/// 切れていても通ってしまう。幅が足りているかを主張したいテストはこちらを使う
/// （#208 の PR #232 レビュー指摘）。
///
/// `maxLines` が null でも、`softWrap: false` + `ellipsis` で1行に収まらなければ
/// `didExceedMaxLines` が true になる。
///
/// **幅は実機と一致しない。** テストにはフォントが無く、1文字 = 1em の代替
/// フォントで測るため、欧文は実機よりかなり幅を食う（`NEXT BUS` が 82px →
/// 120px）。実データで最も長い名前を 375px で通す、といった**限界の主張には
/// 使えない**。構造が壊れて幅が潰れたことを拾うのが役目。
void expectNotTruncated(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: '「$text」が省略されている（幅が足りていない）',
  );
}
