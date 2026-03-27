import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/bus_schedule.dart';
import '../../viewmodels/schedule_viewmodel.dart';

class NextBusDisplay extends ConsumerWidget {
  const NextBusDisplay({
    super.key,
    required this.timetable,
    required this.direction,
    this.showPlatform = false,
  });

  final BusTimetable timetable;
  final BusDirection direction;
  final bool showPlatform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(countdownProvider);

    final next = timetable.nextBus(direction, now: now);
    if (next == null) {
      return const _NoMoreBusCard();
    }
    return _NextBusCard(entry: next, now: now, showPlatform: showPlatform);
  }
}

class _NextBusCard extends StatelessWidget {
  const _NextBusCard({
    required this.entry,
    required this.now,
    required this.showPlatform,
  });
  final BusEntry entry;
  final DateTime now;
  final bool showPlatform;

  static const _stopLabels = {
    'kenkyuto': '研究棟',
    'honbuto': '本部棟',
    'minamiChitose': '南千歳',
    'chitose': '千歳駅',
  };

  List<String> _getArrivalOrder(BusEntry entry) {
    final isRoute2 = entry.routeLabel == '直通';
    switch (entry.direction) {
      case BusDirection.fromChitose:
        return isRoute2
            ? ['kenkyuto', 'honbuto']
            : ['minamiChitose', 'kenkyuto', 'honbuto'];
      case BusDirection.fromMinamiChitose:
        return ['kenkyuto', 'honbuto'];
      case BusDirection.fromKenkyutoToHonbuto:
        return ['honbuto'];
      case BusDirection.fromKenkyutoToStation:
        return isRoute2 ? ['chitose'] : ['minamiChitose', 'chitose'];
      case BusDirection.fromHonbuto:
        return isRoute2
            ? ['kenkyuto', 'chitose']
            : ['kenkyuto', 'minamiChitose', 'chitose'];
    }
  }

  List<Widget> _buildArrivalRows(BusEntry entry) {
    final order = _getArrivalOrder(entry);
    return order
        .where((key) => entry.arrivals.containsKey(key))
        .map((key) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_stopLabels[key]} 着',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    entry.arrivals[key]!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 18,
                      letterSpacing: 2,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
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
                Text(
                  '→ ',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  switch (entry.direction) {
                    BusDirection.fromChitose => '科技大',
                    BusDirection.fromMinamiChitose => '科技大',
                    BusDirection.fromKenkyutoToHonbuto => '本部棟',
                    BusDirection.fromKenkyutoToStation => '千歳駅',
                    BusDirection.fromHonbuto => '千歳駅',
                  },
                  style: const TextStyle(
                    color: AppColors.textPrimary,
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
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 64,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          if (showPlatform && entry.platformNumber != null) ...[
            const SizedBox(height: 4),
            Text(
              '${entry.platformNumber}番のりば',
              style: const TextStyle(
                color: AppColors.textSecondary,
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
            const Divider(color: AppColors.divider, height: 1),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: const Text(
        '本日の運行は終了しました',
        style: TextStyle(
          color: AppColors.textTertiary,
          fontSize: 16,
          letterSpacing: 2,
        ),
      ),
    );
  }
}
