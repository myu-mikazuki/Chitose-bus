import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/entities/bus_schedule.dart';
import '../../../domain/entities/notification_settings.dart';
import '../../viewmodels/notification_viewmodel.dart';
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
  // LayoutBuilder のコールバックで設定される。
  // true = 有界コンテキスト（_DirectionTab の Expanded 配下）→ 独立スクロール
  // false = 非有界コンテキスト（_KenkyutoTab・来週ダイヤ BottomSheet）→ スクロールなし
  bool _isBounded = false;

  @override
  void initState() {
    super.initState();
    // スクロールは初期表示時のみ実行（didUpdateWidgetは対象外）。
    // - direction は各タブで固定のため変化しない
    // - timetable 更新時の再スクロールは要件外（ユーザー操作の上書きを避けるため）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 非有界コンテキスト（KenkyutoTab・来週ダイヤ等）はスクロールしない。
      // nextBus が null の場合は _nextBusKey が付与されず currentContext が null となり
      // スクロールは発生しない（意図通り）。
      if (!_isBounded) return;
      final ctx = _nextBusKey.currentContext;
      if (ctx != null) {
        // 有界コンテキストでは ListView 自身が独立スクロール可能なため、
        // ensureVisible が ListView をスクロールする（親 SingleChildScrollView は不変）。
        // NEXT BUS セクションは常時表示のまま維持される。
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

    return LayoutBuilder(
      builder: (context, constraints) {
        // maxHeight が有限 = Expanded 等で有界な高さが与えられている（_DirectionTab）。
        // maxHeight が無限大 = SingleChildScrollView 配下（_KenkyutoTab・BottomSheet 等）。
        _isBounded = constraints.maxHeight.isFinite;

        final rows = List.generate(buses.length, (index) {
          final bus = buses[index];
          final isPast = bus.minutesFromNow(now: now) < 0;
          final isNext = index == nextBusIndex;
          return _ScheduleRow(
            key: isNext ? _nextBusKey : null,
            bus: bus,
            isPast: isPast,
            isNext: isNext,
          );
        });

        if (_isBounded) {
          // bounded 時は SingleChildScrollView + Column を使う。
          // ListView（SliverList）はビューポート外のアイテムをエレメントツリーに
          // 追加しないため、NEXT が画面外の場合 _nextBusKey.currentContext が null に
          // なり Scrollable.ensureVisible が機能しない。
          // Column は全アイテムをツリーに保持するためこの問題が発生しない。
          // スケジュール件数は最大でも数十件程度なので性能問題はない。
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          );
        }
        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: rows,
        );
      },
    );
  }
}

class _ScheduleRow extends ConsumerStatefulWidget {
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
  ConsumerState<_ScheduleRow> createState() => _ScheduleRowState();
}

class _ScheduleRowState extends ConsumerState<_ScheduleRow> {
  bool _expanded = false;

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

  Widget _buildBellIcon() {
    if (widget.isPast) return const SizedBox.shrink();
    final settings = ref.watch(notificationSettingsProvider).valueOrNull;
    if (settings == null || !settings.enabled) return const SizedBox.shrink();

    final isScheduled = settings.scheduledBusKeys
        .contains(NotificationSettingsNotifier.busKey(widget.bus));
    return IconButton(
      onPressed: () => ref
          .read(notificationSettingsProvider.notifier)
          .toggleBusNotification(widget.bus),
      icon: Icon(
        isScheduled ? Icons.notifications : Icons.notifications_off_outlined,
        color: const Color(0xFF888888),
        size: 24,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      visualDensity: VisualDensity.compact,
    );
  }

  List<Widget> _buildArrivalRows() {
    final order = _getArrivalOrder(widget.bus);
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
                const SizedBox(width: 8),
                if (widget.bus.routeLabel != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: widget.isNext
                            ? const Color(0xFF0A0A0A)
                            : const Color(0xFF666666),
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      widget.bus.routeLabel!,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 10,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.bus.destination,
                  style:
                      TextStyle(color: textColor, fontSize: 14, letterSpacing: 1),
                ),
                // ベルアイコンを右端に配置するため全行に Spacer を挿入。
                // isPast 行はベルを SizedBox.shrink() で返すため視覚的影響はない。
                const Spacer(),
                if (widget.isNext)
                  const Text(
                    '◀ NEXT',
                    style: TextStyle(
                      color: Color(0xFF0A0A0A),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                _buildBellIcon(),
              ],
            ),
            if (_expanded && hasArrivals) ..._buildArrivalRows(),
          ],
        ),
      ),
    );
  }
}
