import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_colors_theme.dart';
import '../../../domain/entities/bus_schedule.dart';
import '../../viewmodels/schedule_viewmodel.dart';
import 'arrival_row.dart';

class NextBusDisplay extends ConsumerWidget {
  const NextBusDisplay({
    super.key,
    required this.timetable,
    required this.stopId,
    required this.stopMaster,
    this.destination,
  });

  final BusTimetable timetable;

  /// 停留所の表示名の供給元（GAS の stopMaster）。
  /// アプリ側に対応表を持つと、停留所が増えるたびにリリースが要る（#177）
  final List<BusStop> stopMaster;

  /// 乗車地
  final String stopId;

  /// 行き先（科技大 / 千歳駅）。指定しなければ絞らない。
  /// 途中の停留所は上下両方向のバスが通るため、画面では指定する
  final String? destination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(countdownProvider);

    final next = timetable.nextBus(stopId, destination: destination, now: now);
    if (next == null) {
      return const _NoMoreBusCard();
    }
    return _NextBusCard(
      stopMaster: stopMaster,
      entry: next,
      now: now,
    );
  }
}

/// NEXT BUS に出す行き先の表示名。**終点の名前を出す。**
///
/// 便の destination（科技大 / 千歳駅）をそのまま出すと、研究棟から乗る人に
/// 「科技大」と出てしまう。実際に向かうのは本部棟なので噛み合わない。
///
/// 以前は `kenkyuto` を名指しで「本部棟」に読み替えていたが、任意の停留所を
/// 選べる今はその対応表を持てない。行き先の見出し（`_StopTab.terminusLabel`）が
/// 同じく終点を出しているので、**同じ画面の2箇所で違う行き先が出ないよう**
/// こちらも終点に揃える（#177）。
///
/// 終点が分からない供給元（未デプロイの GAS・#177 以前のキャッシュ）だけ
/// destination をそのまま出す。
/// **ここは常に短縮名**（#234 で到着行を正式名にしたときも揃えなかった。
/// #241 で到着行が既定は短縮名・タップで正式名に変わり、既定表示は
/// 見た目上揃ったが、**それは結果であって意図して揃えたわけではない**。
/// 行き先は「どこ行きか」が分かればよく、降りる停留所を現地の表記と
/// 突き合わせる到着行とは用途が違うので、今後どちらかの表示が変わっても
/// このまま短縮名を使い続けてよい）。
String destinationLabelOf(BusEntry entry, List<BusStop> stopMaster) {
  final terminus = entry.terminusStopId;
  return terminus != null ? stopMaster.labelOf(terminus) : entry.destination;
}

class _NextBusCard extends StatelessWidget {
  const _NextBusCard({
    required this.entry,
    required this.now,
    required this.stopMaster,
  });
  final BusEntry entry;
  final DateTime now;
  final List<BusStop> stopMaster;

  /// 到着行。**中身は `ArrivalRow`（`arrival_row.dart`）に切り出した。**
  ///
  /// 同じ Row が時刻表リスト（`schedule_list.dart`）にも複製されていて、
  /// #231 → #234 → #241 と3回続けて両方を直す羽目になったため、1箇所に
  /// まとめた（#241）。既定表示・タップで正式名を出す判断の経緯・幅の実測は
  /// すべて `ArrivalRow` のドキュメントコメントを見ること。
  ///
  /// この Widget（`_NextBusCard`）は StatelessWidget のまま。展開状態
  /// （タップして正式名を出すかどうか）は行ごとに `ArrivalRow` 自身が持つ。
  List<Widget> _buildArrivalRows(BusEntry entry) {
    final order = entry.arrivals.keys.toList();
    return order
        .map((key) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: ArrivalRow(
                stopId: key,
                time: entry.arrivals[key]!,
                stopMaster: stopMaster,
              ),
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final minutes = entry.minutesFromNow(now: now);
    final minLabel = _formatCountdown(minutes);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.secondary, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Row(children: [
                const Text(
                  '→ ',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  destinationLabelOf(entry, stopMaster),
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    letterSpacing: 2,
                  ),
                ),
              ]),
              if (entry.routeLabel != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.primary),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    entry.routeLabel!,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            entry.time,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 64,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          // のりばは v=4 で停留所ごとの属性になった（StopTimeModel.platform）。
          // 以前は「千歳駅のときだけ出す」と乗車地を名指ししていたが、GAS が
          // 他の停留所にのりばを足したら出す、が正しい（#177）
          if (entry.platformNumber != null) ...[
            const SizedBox(height: 4),
            Text(
              '${entry.platformNumber}のりば',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                letterSpacing: 1,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            minLabel,
            style: TextStyle(
              color: minutes <= 5 ? AppColors.error : AppColors.warning,
              fontSize: 20,
              letterSpacing: 2,
            ),
          ),
          // 到着時刻（arrivalsが空でない場合のみ表示）
          if (entry.arrivals.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(color: colors.divider, height: 1),
            const SizedBox(height: 10),
            ..._buildArrivalRows(entry),
          ],
        ],
      ),
    );
  }
}

/// カウントダウン分数を文字列に変換する
/// 0分以下: '発車中', 1–59分: 'あと m 分', 60分以上: 'あと h:mm'
String _formatCountdown(int minutes) {
  if (minutes <= 0) return '発車中';
  if (minutes < 60) return 'あと $minutes 分';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return 'あと $h:${m.toString().padLeft(2, '0')}';
}

class _NoMoreBusCard extends StatelessWidget {
  const _NoMoreBusCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: colors.divider),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        '本日の運行は終了しました',
        style: TextStyle(
          color: colors.textTertiary,
          fontSize: 16,
          letterSpacing: 2,
        ),
      ),
    );
  }
}
