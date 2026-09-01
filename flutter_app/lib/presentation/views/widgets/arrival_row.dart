import 'package:flutter/material.dart';
import '../../../core/theme/app_colors_theme.dart';
import '../../../domain/entities/bus_schedule.dart';

/// 到着行（`◯◯ 着` ＋ 時刻）。**NEXT BUS カードと時刻表リストの両方で使う。**
///
/// 同じ Row が `next_bus_display.dart` と `schedule_list.dart` に複製されていた
/// ものをここへ寄せた（#241）。#231 → #234 → #241 と3回続けて両方を触る
/// 羽目になったための切り出し。呼び出し側は `stopId` / `time` / `stopMaster`
/// の3つだけ渡す。**`BusEntry` を丸ごと渡さない**——この Widget の責務は
/// 1行ぶんの到着地と時刻を出すことに閉じており、便全体の情報は要らない。
///
/// ## 経緯（#231 → #234 → #241）
///
/// **#231**: 名前 13px / 時刻 18px では、短縮名を持たない停留所名
/// （`オフィス・アルカディア入口 着`）が 375px で 10px はみ出していた。
/// この Row は `spaceBetween` に素の `Text` を2つ並べるだけなので、名前が
/// 伸びると縮まずに溢れる。字を 12px / 14px に落として凌いだが、**倍率が
/// 同じなら同じように溢れる**ため拡大設定には原理的に効かなかった。
///
/// **#234**: `labelOf`（= `shortLabel ?? label`）が返す短縮名は、タブの幅が
/// 無いために作ったもので、現地の停留所の表記とは別物。#207 で31件すべてに
/// `shortLabel` が付いたことで、幅が足りているこの行にまで短縮名が及んでいた
/// （`古泉循環器内科クリニック前 着` → `古泉 着`）。降りる停留所を現地の
/// 表記と突き合わせる場所なので `officialLabelOf`（正式名）に寄せた。
/// 既定の4停留所の見え方も変わった（`本部棟 着` → `科技大本部棟 着`）。
///
/// **#241（今回）**: #237 で拡大設定を実測した結果、**この行が「Android の
/// 最大 (1.3) で実際に崩れる唯一の場所」**だと分かった。#234 は文字を
/// 正式名に伸ばした側なので、拡大が重なると当然余計に崩れる。
/// `Flexible` + ellipsis で黙って切る案は、#234 で「降りる停留所を正式名で
/// 突き合わせられるようにする」と決めたばかりの方針と噛み合わない
/// （切れて読めなくなる）。
///
/// そこで**既定は短縮名（`labelOf`）に戻し、タップした行の1行下に
/// 正式名＋時刻を出す**形にした。これなら
///
/// - 既定の幅は最長5文字（`O･A入口`）で済み、拡大しても溢れない
///   （正式名の13文字の半分以下）
/// - 正式名は「タップすれば必ず全部読める」形で残るので、#234 の
///   「現地表記と突き合わせる」という用途は失われない
///
/// 展開行は `spaceBetween` にせず、素直に折り返せる形にしてある
/// （下の `_buildExpandedRow` 参照）。**ここが「どの倍率でも溢れない」を
/// 担保する場所**で、ellipsis は付けていない——折り返しても構わないので、
/// 切って読めなくする理由が無い。
///
/// 画面には短縮名しか出さないため、読み上げ（`Semantics`）には最初から
/// 正式名を渡す（`_StopLabelPlaceholder` に前例がある）。
///
/// ## 幅の実測（375px・#231 / #234 由来、経路は変わっていない）
///
/// 到着行が出る3経路のうち、幅がいちばん狭いのは NEXT BUS カード。
///
/// | 経路 | 幅 |
/// |---|---|
/// | NEXT BUS カード | **300px**（外の `Padding(16)` ＋ カードの `horizontal: 20` ＋ 枠線 1.5） |
/// | 来週ダイヤの BottomSheet | 303px |
/// | ホームの時刻表リスト | 335px |
///
/// 字の大きさ（名前 12px / 時刻 14px）と `letterSpacing`・
/// `tabularFigures` は #231 で2箇所を揃えたものなので変えていない。
class ArrivalRow extends StatefulWidget {
  const ArrivalRow({
    super.key,
    required this.stopId,
    required this.time,
    required this.stopMaster,
  });

  /// 到着地の停留所 ID
  final String stopId;

  /// 到着時刻（HH:MM）
  final String time;

  /// 停留所の表示名の供給元（GAS の stopMaster）
  final List<BusStop> stopMaster;

  @override
  State<ArrivalRow> createState() => _ArrivalRowState();
}

class _ArrivalRowState extends State<ArrivalRow> {
  // 展開状態は行ごとに持つ。複数の到着地を持つ便で、他の行に影響しない
  bool _expanded = false;

  @override
  void didUpdateWidget(ArrivalRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 同じ位置の ArrivalRow が別の到着地・時刻を指すようになったら展開を
    // 閉じる（例: NEXT の便が繰り上がり、到着地の並びの同じ位置に別の
    // 停留所が来たとき）。**行き先を切り替えて戻ったときに開いたままになる
    // 件（NEXT BUS カードは `IndexedStack` で行き先ごとに State を保持する）
    // はこれでは直らない。** 隠れている側の ArrivalRow は stopId / time が
    // 変わらないまま再表示されるため didUpdateWidget 自体が呼ばれないか、
    // 呼ばれても値が同じで条件に掛からない。そちらは開いたままを許容する
    // ことにした（#241）。タップすれば必ず正式名が出るという保証は崩れず、
    // 開いたままでも「別の停留所の正式名が出る」といった誤った表示にはならない
    if (oldWidget.stopId != widget.stopId || oldWidget.time != widget.time) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final shortLabel = widget.stopMaster.labelOf(widget.stopId);
    final officialLabel = widget.stopMaster.officialLabelOf(widget.stopId);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Semantics(
                // 画面には短縮名しか出さないので、読み上げは正式名から
                // 始める。子の Text 自身の読み上げ（短縮名）は二重に
                // 読ませないよう除外する
                label: '$officialLabel 着',
                excludeSemantics: true,
                child: Text(
                  '$shortLabel 着',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
              ),
              Text(
                widget.time,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 14,
                  letterSpacing: 2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (_expanded) _buildExpandedRow(colors, officialLabel),
        ],
      ),
    );
  }

  /// タップで出す正式名の行。**`spaceBetween` にせず折り返せる形にする。**
  ///
  /// 正式名は最長13文字（`古泉循環器内科クリニック前` /
  /// `オフィス・アルカディア入口`）で、既定行の幅（300px 最狭）では
  /// 拡大設定次第でどのみち収まらないことがある。`Wrap` にしておけば、
  /// 収まらないぶんは2行目に流れるだけで**溢れない**。ellipsis は
  /// 付けていない——ここは「タップすれば必ず全部読める」ことを担保する
  /// 場所なので、切って読めなくする選択肢は採らない。
  ///
  /// 補足であることが分かるよう、字は既定行より小さく・色は
  /// `textTertiary` に落としてある。
  ///
  /// **`ExcludeSemantics` で包んでいる。** `GestureDetector` は既定で
  /// 子孫の `Semantics` ノードを自分の tap アクションのノードにマージする
  /// ため、ここを素の `Text` のままにすると、上の既定行が既に
  /// `Semantics(label: '$officialLabel 着')` で渡している正式名・時刻と、
  /// この行の正式名・時刻が両方マージされて**二重に読み上げられる**
  /// （実際に `debugDumpSemanticsTree()` で確認した）。読み上げには最初から
  /// 正式名を渡しているので、展開してもスクリーンリーダー側で新しく
  /// 読ませる情報は無い——この行は見える人向けの補足に閉じてよい
  Widget _buildExpandedRow(AppColorsTheme colors, String officialLabel) {
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Wrap(
          spacing: 8,
          children: [
            Text(
              officialLabel,
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 11,
                letterSpacing: 1,
              ),
            ),
            Text(
              widget.time,
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 11,
                letterSpacing: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
