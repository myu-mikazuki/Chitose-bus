import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/entities/bus_schedule.dart';
import '../../viewmodels/schedule_viewmodel.dart';

class ScheduleList extends ConsumerWidget {
  const ScheduleList({
    super.key,
    required this.timetable,
    required this.direction,
  });

  final BusTimetable timetable;
  final BusDirection direction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(countdownProvider);

    final buses = timetable.todayBuses(direction);
    final nextBus = timetable.nextBus(direction, now: now);

    if (buses.isEmpty) {
      return const Center(
        child: Text(
          '時刻表データなし',
          style: TextStyle(color: Color(0xFF666666)),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: buses.length,
      itemBuilder: (context, index) {
        final bus = buses[index];
        final isPast = bus.minutesFromNow(now: now) < 0;
        final isNext = nextBus != null && bus.time == nextBus.time;
        return _ScheduleRow(bus: bus, isPast: isPast, isNext: isNext);
      },
    );
  }
}

class _ScheduleRow extends StatefulWidget {
  const _ScheduleRow({
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
