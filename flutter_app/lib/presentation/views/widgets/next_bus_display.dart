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
    this.showPlatform = false,
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
  final bool showPlatform;

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
      showPlatform: showPlatform,
    );
  }
}

/// NEXT BUS に出す行き先の表示名。
///
/// 便の destination（科技大 / 千歳駅）をそのまま出すと、研究棟から乗る場合に
/// 「科技大」となって現在の表示と変わる。実際に向かうのは本部棟なので、
/// 現在は乗車地との組で決めている。
///
/// TODO(#177): 乗車地選択の UI を入れる際に見直す。任意の停留所では
/// この対応表を持てないため、行き先の出し方そのものを決め直す必要がある。
String destinationLabelOf(BusEntry entry) {
  if (entry.boardingStopId == 'kenkyuto' && entry.destination == BusDestination.campus) {
    return '本部棟';
  }
  return entry.destination;
}

class _NextBusCard extends StatelessWidget {
  const _NextBusCard({
    required this.entry,
    required this.now,
    required this.showPlatform,
    required this.stopMaster,
  });
  final BusEntry entry;
  final DateTime now;
  final bool showPlatform;
  final List<BusStop> stopMaster;

  List<Widget> _buildArrivalRows(BusEntry entry, BuildContext context) {
    final colors = context.appColors;
    final order = entry.arrivals.keys.toList();
    return order.map((key) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${stopMaster.labelOf(key)} 着',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    entry.arrivals[key]!,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 18,
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
                  destinationLabelOf(entry),
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
          if (showPlatform && entry.platformNumber != null) ...[
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
