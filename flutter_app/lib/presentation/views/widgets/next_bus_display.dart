import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_colors_theme.dart';
import '../../../domain/entities/bus_schedule.dart';
import '../../viewmodels/schedule_viewmodel.dart';

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

  /// 到着行。**降りる停留所を確かめる場所なので正式名を出す**（#234）。
  /// 字の大きさは**時刻表リスト（`schedule_list.dart`）と揃える**（#231）。
  ///
  /// `labelOf`（= `shortLabel ?? label`）はタブの幅が無いために作った短縮名を
  /// 返す。#207 で31件すべてに `shortLabel` が付いた結果、**幅が足りている
  /// この行にまで短縮名が及んでいた**（`古泉循環器内科クリニック前 着` →
  /// `古泉 着`）。短縮名は現地の停留所の表記とは別物なので、ここで突き合わせ
  /// られない。**既定の4停留所の見え方も変わる**（`本部棟 着` →
  /// `科技大本部棟 着`）が、それを承知で正式名に寄せている。
  ///
  /// 正式名は最長でも13文字（`古泉循環器内科クリニック前` /
  /// `オフィス・アルカディア入口`）で、下の幅の実測はその13文字で採ってある。
  /// **短縮名から正式名に変えても最長は伸びない。**
  ///
  /// 名前 13px / 時刻 18px では、短縮名を持たない停留所名（`オフィス・
  /// アルカディア入口 着`）が 375px で **10px はみ出していた**（#231）。
  /// この Row は `spaceBetween` に素の `Text` を2つ並べるだけなので、
  /// 名前が伸びると縮まずに溢れる。
  ///
  /// 同じ「◯◯ 着 ＋ 時刻」を出す時刻表リストが元から 12px / 14px で、
  /// そちらは溢れていない。**2箇所で字の大きさを変える理由が無い**ので揃えた。
  /// 375px で 300px 中 265px、360px でも収まる。
  List<Widget> _buildArrivalRows(BusEntry entry, BuildContext context) {
    final colors = context.appColors;
    final order = entry.arrivals.keys.toList();
    return order
        .map((key) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${stopMaster.officialLabelOf(key)} 着',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    entry.arrivals[key]!,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 14,
                      letterSpacing: 2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
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
            ..._buildArrivalRows(entry, context),
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
