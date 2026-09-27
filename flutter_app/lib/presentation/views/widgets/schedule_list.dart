import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_colors_theme.dart';
import '../../../domain/entities/bus_schedule.dart';
import '../../../domain/entities/lecture_period.dart';
import '../../viewmodels/display_settings_viewmodel.dart';
import '../../viewmodels/notification_viewmodel.dart';
import '../../viewmodels/schedule_viewmodel.dart';
import 'arrival_row.dart';

class ScheduleList extends ConsumerStatefulWidget {
  const ScheduleList({
    super.key,
    required this.timetable,
    required this.stopId,
    required this.stopMaster,
    this.destination,
    this.dayType,
    this.season,
  });

  final BusTimetable timetable;

  /// 停留所の表示名の供給元（GAS の stopMaster）。
  /// アプリ側に対応表を持つと、停留所が増えるたびにリリースが要る（#177）
  final List<BusStop> stopMaster;

  /// 乗車地
  final String stopId;

  /// 行き先（科技大 / 千歳駅）。指定しなければ絞らない
  final String? destination;

  /// 非 null の場合、当日ではなく指定ダイヤ種別（平日 / 土日祝）の全便を表示する。
  /// このとき現在時刻に依存する表示（NEXT ハイライト・過去便のグレーアウト・
  /// 通知ベル・NEXT への自動スクロール）は行わない。
  final DayType? dayType;

  /// 当日以外モードで表示する期別（授業期 / 学休期）。
  /// null の場合は当日の期別を用いる。[dayType] が null のときは参照されない。
  final SeasonType? season;

  @override
  ConsumerState<ScheduleList> createState() => _ScheduleListState();
}

class _ScheduleListState extends ConsumerState<ScheduleList> {
  final GlobalKey _nextBusKey = GlobalKey();
  // LayoutBuilder のコールバックで設定される。
  // true = 有界コンテキスト（_StopTab の Expanded 配下）→ 独立スクロール
  // false = 非有界コンテキスト（来週ダイヤ BottomSheet）→ スクロールなし
  bool _isBounded = false;

  @override
  void initState() {
    super.initState();
    // スクロールは初期表示時のみ実行（didUpdateWidgetは対象外）。
    // - stopId / destination は各タブで固定のため変化しない
    // - timetable 更新時の再スクロールは要件外（ユーザー操作の上書きを避けるため）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 非有界コンテキスト（来週ダイヤ BottomSheet 等）はスクロールしない。
      // nextBus が null の場合は _nextBusKey が付与されず currentContext が null となり
      // スクロールは発生しない（意図通り）。
      //
      // **非有界になる経路がもう1つ増えた**（#240 / #266）。文字拡大が
      // `kVerticalScrollThreshold` を超えると `_StopTab` が画面ごとスクロールに
      // 切り替わり、`Expanded` が外れてここも非有界になる。そちらでも
      // 自動スクロールは走らないが、外側のスクロールが NEXT BUS カードから
      // 始まるので意図した挙動として受け入れている
      // （`home_screen.dart` の `_buildScheduleSection` 参照）。
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

    final dayType = widget.dayType;
    final buses = dayType == null
        ? widget.timetable.todayBuses(widget.stopId,
            destination: widget.destination, now: now)
        : widget.timetable.busesFor(
            widget.stopId,
            dayType,
            widget.season ?? SeasonType.fromDate(now),
            destination: widget.destination,
          );
    // 当日以外の表示では NEXT の概念がないため null とする
    final nextBus = dayType == null
        ? widget.timetable
            .nextBus(widget.stopId, destination: widget.destination, now: now)
        : null;

    if (buses.isEmpty) {
      final isSuspended = dayType == null && ServiceCalendar.isSuspended(now);
      return Center(
        child: Text(
          isSuspended ? '年末年始のため全便運休です' : '時刻表データなし',
          style: TextStyle(color: context.appColors.textTertiary),
        ),
      );
    }

    // BusEntry は == を override しないためオブジェクト同一性で比較される。
    // todayBuses() と nextBus() は同一 schedules リストの要素を返すため
    // indexOf が正確に1件を特定でき、同時刻便が複数あっても GlobalKey の重複付与を防ぐ。
    final nextBusIndex = nextBus != null ? buses.indexOf(nextBus) : -1;

    return LayoutBuilder(
      builder: (context, constraints) {
        // maxHeight が有限 = Expanded 等で有界な高さが与えられている（_StopTab）。
        // maxHeight が無限大 = SingleChildScrollView 配下（来週ダイヤ BottomSheet 等）。
        _isBounded = constraints.maxHeight.isFinite;

        final rows = List.generate(buses.length, (index) {
          final bus = buses[index];
          final isPast = dayType == null && bus.minutesFromNow(now: now) < 0;
          final isNext = index == nextBusIndex;
          return _ScheduleRow(
            key: isNext ? _nextBusKey : null,
            bus: bus,
            stopMaster: widget.stopMaster,
            isPast: isPast,
            isNext: isNext,
            showBell: dayType == null,
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
    required this.stopMaster,
    required this.isPast,
    required this.isNext,
    this.showBell = true,
  });

  final BusEntry bus;
  final List<BusStop> stopMaster;
  final bool isPast;
  final bool isNext;

  /// 通知ベルは当日の便に対してのみ意味を持つため、
  /// 当日以外のダイヤ表示では false を渡して非表示にする。
  final bool showBell;

  @override
  ConsumerState<_ScheduleRow> createState() => _ScheduleRowState();
}

class _ScheduleRowState extends ConsumerState<_ScheduleRow> {
  bool _expanded = false;

  List<Widget> _buildLectureTagWidgets() {
    final showTags =
        ref.watch(displaySettingsProvider).valueOrNull?.showLectureTags ?? true;
    if (!showTags) return const [];
    final period = LecturePeriodCalculator.forBus(widget.bus);
    if (period == null) return const [];
    final color = _lectureTagColor(period);
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          period.label,
          // 下の系統タグと同じ理由（#242 / PR #254 の指摘）
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 10,
            letterSpacing: 0.5,
          ),
        ),
      ),
      // **末尾に `SizedBox(width: 8)` を付けないこと**（#242）。返り値は
      // `Wrap` の子として並べるので、区切りは `Wrap` の `spacing` が持つ。
      // 付けると二重に空いて等倍の見た目が変わる
    ];
  }

  static Color _lectureTagColor(LecturePeriod period) => switch (period) {
        LecturePeriod.period1 => const Color(0xFF64B5F6), // 青（朝）
        LecturePeriod.period2 => const Color(0xFF4DD0E1), // シアン
        LecturePeriod.lunchBreak => const Color(0xFFF2CB4B), // 黄（昼）
        LecturePeriod.period3 => const Color(0xFF81C784), // 緑
        LecturePeriod.period4 => const Color(0xFFFFB74D), // オレンジ
        LecturePeriod.period5 => const Color(0xFFFF8A65), // 深オレンジ
        LecturePeriod.afterSchool => const Color(0xFFCE93D8), // 紫
      };

  Widget _buildBellIcon() {
    if (!widget.showBell) return const SizedBox.shrink();
    if (widget.isPast) return const SizedBox.shrink();
    final settings = ref.watch(notificationSettingsProvider).valueOrNull;
    if (settings == null || !settings.enabled) return const SizedBox.shrink();

    final now = ref.watch(countdownProvider);
    if (widget.bus.minutesFromNow(now: now) <= settings.minutesBefore) {
      return const SizedBox.shrink();
    }

    final isScheduled = settings.scheduledBusKeys
        .contains(NotificationSettingsNotifier.busKey(widget.bus));
    return IconButton(
      onPressed: () => ref
          .read(notificationSettingsProvider.notifier)
          .toggleBusNotification(widget.bus),
      icon: Icon(
        isScheduled ? Icons.notifications : Icons.notifications_off_outlined,
        color: context.appColors.textSecondary,
        size: 24,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      visualDensity: VisualDensity.compact,
    );
  }

  /// 到着行。**中身は `ArrivalRow`（`arrival_row.dart`）に切り出した。**
  ///
  /// NEXT BUS カード（`next_bus_display.dart`）と同じ Row が複製されていて、
  /// #231 → #234 → #241 と3回続けて両方を直す羽目になったため、1箇所に
  /// まとめた（#241）。既定表示・タップで正式名を出す判断の経緯・
  /// 3経路の幅の実測（300 / 303 / 335px）は `ArrivalRow` のドキュメント
  /// コメントを見ること。
  ///
  /// **この行の展開・折りたたみは2段になっている。** 親の `_ScheduleRow`
  /// （このファイル）はタップで到着行そのものを出し入れする（`_expanded`）。
  /// 到着行が出たあと、行ごとにさらにタップすると `ArrivalRow` 自身の
  /// `_expanded` が正式名を出し入れする。**内側のタップは外側まで貫通しない**
  /// （Flutter のジェスチャーアリーナで内側の `GestureDetector` が勝つ）ので、
  /// 到着行をタップしても親の行が閉じることはない。
  List<Widget> _buildArrivalRows() {
    final order = widget.bus.arrivals.keys.toList();
    return order
        .map((key) => Padding(
              padding: const EdgeInsets.only(top: 4, left: 8),
              child: ArrivalRow(
                stopId: key,
                time: widget.bus.arrivals[key]!,
                stopMaster: widget.stopMaster,
              ),
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final Color textColor;
    final Color bgColor;

    if (widget.isNext) {
      textColor = AppColors.onPrimary;
      bgColor = AppColors.secondary;
    } else if (widget.isPast) {
      textColor = colors.textDisabled;
      bgColor = Colors.transparent;
    } else {
      textColor = colors.textPrimary;
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
                // **中間の3つ（系統タグ・講義タグ・行き先）を `Wrap` に入れる**（#242）。
                //
                // 元は素の `Row` に固定幅で並べ、`Spacer` を挟むだけだったので
                // **縮む余地が無く、停留所名と無関係に横へ溢れていた**
                // （代替フォントの実測で 1.35、実フォントで 2.0）。既定の
                // 4停留所でも同じ倍率で溢れる。
                //
                // **`Spacer` を `Expanded` に置き換えて中に `Wrap` を入れる**のが肝。
                // `Wrap` には `Spacer` が無いので、素直に `Wrap` へ移すと
                // `◀ NEXT` とベルが右端から離れてしまう。`Expanded` は
                // `Spacer` と同じく残り幅を全部取るので、**等倍の見え方は
                // 変わらないまま**、入らなくなった分だけ2段目へ流れる。
                //
                // **時刻とベルは `Wrap` に入れない。** 時刻は行の主役、ベルは
                // タップ対象なので、位置が動くと押しにくい。
                //
                // `crossAxisAlignment` は `Row` の既定（center）のまま。
                // 等倍では1段なので差が出ない
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (widget.bus.routeLabel != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: widget.isNext
                                  ? AppColors.onPrimary
                                  : colors.textTertiary,
                            ),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            widget.bus.routeLabel!,
                            // **枠の中で文字単位に割れるのを防ぐ**（#242 /
                            // PR #254 の指摘）。`Wrap` の子は「その行に入る
                            // ところまで」の幅しか貰えないので、拡大時に
                            // `空港経由` が `空港経` / `由` の2行になって
                            // タグの枠が崩れていた。**`Wrap` は折り返せてしまう
                            // ぶん overflow 例外を出さないので、テストは緑の
                            // まま見た目だけ壊れる。** 等倍では収まるので
                            // ellipsis は働かない
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 10,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ..._buildLectureTagWidgets(),
                      Text(
                        widget.bus.destination,
                        // 系統タグと同じ理由。1.7 で `科技大` が
                        // `科技` / `大` に割れていた（#242 / PR #254 の指摘）
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: textColor, fontSize: 14, letterSpacing: 1),
                      ),
                    ],
                  ),
                ),
                if (widget.isNext)
                  const Text(
                    '◀ NEXT',
                    style: TextStyle(
                      color: AppColors.onPrimary,
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
