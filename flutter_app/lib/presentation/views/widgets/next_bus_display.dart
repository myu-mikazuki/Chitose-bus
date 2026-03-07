import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/entities/bus_schedule.dart';
import '../../viewmodels/schedule_viewmodel.dart';

class NextBusDisplay extends ConsumerWidget {
  const NextBusDisplay({
    super.key,
    required this.timetable,
    required this.direction,
  });

  final BusTimetable timetable;
  final BusDirection direction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(countdownProvider);

    final next = timetable.nextBus(direction, now: now);
    if (next == null) {
      return const _NoMoreBusCard();
    }
    return _NextBusCard(entry: next, now: now);
  }
}

class _NextBusCard extends StatelessWidget {
  const _NextBusCard({required this.entry, required this.now});
  final BusEntry entry;
  final DateTime now;

  static const _stopLabels = {
    'kenkyuto':      '研究棟',
    'honbuto':       '本部棟',
    'minamiChitose': '南千歳',
    'chitose':       '千歳駅',
  };

  static const _arrivalOrder = {
    BusDirection.fromChitose:           ['kenkyuto', 'honbuto'],
    BusDirection.fromMinamiChitose:     ['kenkyuto', 'honbuto'],
    BusDirection.fromKenkyutoToHonbuto: ['honbuto'],
    BusDirection.fromKenkyutoToStation: ['minamiChitose', 'chitose'],
    BusDirection.fromHonbuto:           ['kenkyuto', 'minamiChitose', 'chitose'],
  };

  List<Widget> _buildArrivalRows(BusEntry entry) {
    final order = _arrivalOrder[entry.direction] ?? [];
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
                      color: Color(0xFF888888),
                      fontSize: 13,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    entry.arrivals[key]!,
                    style: const TextStyle(
                      color: Color(0xFF888888),
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
        border: Border.all(color: const Color(0xFF00FF88), width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            switch (entry.direction) {
              BusDirection.fromChitose => '→ 千歳科技大',
              BusDirection.fromMinamiChitose => '→ 千歳科技大',
              BusDirection.fromKenkyutoToHonbuto => '→ 本部棟',
              BusDirection.fromKenkyutoToStation => '→ 千歳駅',
              BusDirection.fromHonbuto => '→ 千歳駅',
            },
            style: const TextStyle(
              color: Color(0xFF00FF88),
              fontSize: 14,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            entry.time,
            style: const TextStyle(
              color: Color(0xFF00FF88),
              fontSize: 64,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            minLabel,
            style: TextStyle(
              color: minutes <= 5
                  ? const Color(0xFFFF4444)
                  : const Color(0xFFFFB000),
              fontSize: 20,
              letterSpacing: 2,
            ),
          ),
          // 到着時刻（arrivalsが空でない場合のみ表示）
          if (entry.arrivals.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: Color(0xFF333333), height: 1),
            const SizedBox(height: 10),
            ..._buildArrivalRows(entry),
          ],
        ],
      ),
    );
  }
}

/// カウントダウン分数を h:mm 形式の文字列に変換する
/// 0分以下の場合は '発車中' を返す
String _formatCountdown(int minutes) {
  if (minutes <= 0) return '発車中';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return '$h:${m.toString().padLeft(2, '0')}';
}

class _NoMoreBusCard extends StatelessWidget {
  const _NoMoreBusCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: const Text(
        '本日の運行は終了しました',
        style: TextStyle(
          color: Color(0xFF666666),
          fontSize: 16,
          letterSpacing: 2,
        ),
      ),
    );
  }
}
