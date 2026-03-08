import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/entities/bus_schedule.dart';
import '../../viewmodels/schedule_viewmodel.dart';

class ScheduleList extends ConsumerStatefulWidget {
  const ScheduleList({
    super.key,
    required this.timetable,
    required this.direction,
  });

  final BusTimetable timetable;
  final BusDirection direction;

  @override
  ConsumerState<ScheduleList> createState() => _ScheduleListState();
}

class _ScheduleListState extends ConsumerState<ScheduleList> {
  final GlobalKey _nextBusKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // スクロールは初期表示時のみ実行（didUpdateWidgetは対象外）。
    // - direction は各タブで固定のため変化しない
    // - timetable 更新時の再スクロールは要件外（ユーザー操作の上書きを避けるため）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // nextBus が null（来週ダイヤの ScheduleList 等）の場合は
      // _nextBusKey がどのウィジェットにも付与されないため
      // currentContext が null となりスクロールは発生しない（意図通り）。
      final ctx = _nextBusKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.0,
          duration: Duration.zero,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(countdownProvider);

    final buses = widget.timetable.todayBuses(widget.direction);
    final nextBus = widget.timetable.nextBus(widget.direction, now: now);

    if (buses.isEmpty) {
      return const Center(
        child: Text(
          '時刻表データなし',
          style: TextStyle(color: Color(0xFF666666)),
        ),
      );
    }

    // BusEntry は == を override しないためオブジェクト同一性で比較される。
    // todayBuses() と nextBus() は同一 schedules リストの要素を返すため
    // indexOf が正確に1件を特定でき、同時刻便が複数あっても GlobalKey の重複付与を防ぐ。
    final nextBusIndex = nextBus != null ? buses.indexOf(nextBus) : -1;

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: buses.length,
      itemBuilder: (context, index) {
        final bus = buses[index];
        final isPast = bus.minutesFromNow(now: now) < 0;
        final isNext = index == nextBusIndex;
        return _ScheduleRow(
          key: isNext ? _nextBusKey : null,
          bus: bus,
          isPast: isPast,
          isNext: isNext,
        );
      },
    );
  }
}

class _ScheduleRow extends StatefulWidget {
  const _ScheduleRow({
    super.key,
    required this.bus,
    required this.isPast,
    required this.isNext,
  });

  final BusEntry bus;
  final bool isPast;
  final bool isNext;

  @override
  State<_ScheduleRow> createState() => _ScheduleRowState();
}

class _ScheduleRowState extends State<_ScheduleRow> {
  bool _expanded = false;

  static const _stopLabels = {
    'kenkyuto': '研究棟',
    'honbuto': '本部棟',
    'minamiChitose': '南千歳',
    'chitose': '千歳駅',
  };

  static const _arrivalOrder = {
    BusDirection.fromChitose:           ['kenkyuto', 'honbuto'],
    BusDirection.fromMinamiChitose:     ['kenkyuto', 'honbuto'],
    BusDirection.fromKenkyutoToHonbuto: ['honbuto'],
    BusDirection.fromKenkyutoToStation: ['minamiChitose', 'chitose'],
    BusDirection.fromHonbuto:           ['kenkyuto', 'minamiChitose', 'chitose'],
  };

  List<Widget> _buildArrivalRows() {
    final order = _arrivalOrder[widget.bus.direction] ?? [];
    return order
        .where((key) => widget.bus.arrivals.containsKey(key))
        .map((key) => Padding(
              padding: const EdgeInsets.only(top: 4, left: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_stopLabels[key]} 着',
                    style: const TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    widget.bus.arrivals[key]!,
                    style: const TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 14,
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
    final Color textColor;
    final Color bgColor;

    if (widget.isNext) {
      textColor = const Color(0xFF0A0A0A);
      bgColor = const Color(0xFF00FF88);
    } else if (widget.isPast) {
      textColor = const Color(0xFF444444);
      bgColor = Colors.transparent;
    } else {
      textColor = const Color(0xFFCCCCCC);
      bgColor = Colors.transparent;
    }

    final hasArrivals = widget.bus.arrivals.isNotEmpty;

    return GestureDetector(
      onTap: hasArrivals ? () => setState(() => _expanded = !_expanded) : null,
      child: Container(
        color: bgColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  widget.bus.time,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight:
                        widget.isNext ? FontWeight.bold : FontWeight.normal,
                    letterSpacing: 2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  widget.bus.destination,
                  style:
                      TextStyle(color: textColor, fontSize: 14, letterSpacing: 1),
                ),
                if (widget.isNext) ...[
                  const Spacer(),
                  const Text(
                    '◀ NEXT',
                    style: TextStyle(
                      color: Color(0xFF0A0A0A),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ],
            ),
            if (_expanded && hasArrivals) ..._buildArrivalRows(),
          ],
        ),
      ),
    );
  }
}
