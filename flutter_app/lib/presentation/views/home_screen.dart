import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_colors_theme.dart';
import '../../domain/entities/bus_schedule.dart';
import '../viewmodels/favorite_tab_viewmodel.dart';
import '../viewmodels/schedule_viewmodel.dart';
import '../viewmodels/stop_selection_viewmodel.dart';
import '../../domain/entities/stop_selection.dart';
import 'settings_screen.dart';
import 'widgets/next_bus_display.dart';
import 'widgets/offline_cache_banner.dart';
import 'widgets/schedule_list.dart';
import 'widgets/season_notice_banner.dart';
import 'widgets/weekend_warning_banner.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;

  /// [_tabController] を組んだときの停留所。**タブの構成はこれが正**で、
  /// TabBar / TabBarView もこれを見る。選択そのものを直接描画すると、
  /// controller の長さと食い違ったフレームが生まれて落ちる。
  late List<String> _tabStopIds;

  bool _bannerDismissed = false;
  bool _favoriteApplied = false;

  @override
  void initState() {
    super.initState();
    // 選択の読み出しは非同期。解決するまでは既定の4停留所で組んでおく
    _tabStopIds = StopSelection.initial.stopIds;
    _tabController = TabController(length: _tabStopIds.length, vsync: this);
  }

  /// タブを [stopIds] の構成で組み直す。
  ///
  /// [focusStopId] を渡すとその停留所を開く（お気に入りの初回適用）。
  /// 指定が無ければ**いま見ている停留所を追いかける**。タブ番号で覚えると、
  /// 並べ替えや追加のたびに別の停留所へ飛んでしまう。
  ///
  /// 長さを変えるだけ（`_tabController.index = ...`）では足りず作り直す。
  /// TabBarView が未生成のまま index を動かすと、初回生成時に PageView の
  /// initialPage と TabController の内部状態がずれて SegmentedButton の高さが
  /// 0 になる（#126）。initialIndex を持つ controller を作れば起きない。
  ///
  /// **build 中から呼ぶ。** この直後に組む TabBar / TabBarView が同じ build で
  /// 新しい controller と `_tabStopIds` を読むため、setState は要らないし、
  /// 次フレームへ遅らせると1フレームだけ両者が食い違う。
  void _retuneTabs(List<String> stopIds, {String? focusStopId}) {
    final viewing = _tabController.index < _tabStopIds.length
        ? _tabStopIds[_tabController.index]
        : null;
    // 見ていた停留所が外されていれば先頭に戻す
    final index = stopIds.indexOf(focusStopId ?? viewing ?? '');

    final old = _tabController;
    _tabStopIds = stopIds;
    _tabController = TabController(
      length: stopIds.length,
      initialIndex: index < 0 ? 0 : index,
      vsync: this,
    );
    // build 中に捨てると、まだ古い controller を参照している TabBar が落ちる
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Tab _buildTab(String label, String stopId, String? favoriteStopId) {
    return Tab(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isFavorite = favoriteStopId == stopId;
          final tabWidth = constraints.maxWidth;

          // タブ内のラベルスタイルでテキスト幅を計測
          final textStyle = DefaultTextStyle.of(context).style;
          final textPainter = TextPainter(
            text: TextSpan(text: label, style: textStyle),
            textDirection: TextDirection.ltr,
          )..layout();
          final textWidth = textPainter.width;

          const starSize = 20.0;
          const gap = 4.0;

          Widget starIcon(double size) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => ref
                    .read(favoriteTabProvider.notifier)
                    .toggleFavorite(stopId),
                child: Icon(
                  isFavorite ? Icons.star : Icons.star_border,
                  size: size,
                  color: isFavorite ? AppColors.warning : null,
                ),
              );

          // デフォルト: ラベル中央・スター右端（重ならない場合）
          // 中央テキストの右端 = tabWidth/2 + textWidth/2
          // スターの左端 = tabWidth - starSize
          final stackFits =
              tabWidth / 2 + textWidth / 2 + gap <= tabWidth - starSize;
          if (stackFits) {
            return Stack(
              children: [
                Align(alignment: Alignment.center, child: Text(label)),
                Align(
                    alignment: Alignment.centerRight,
                    child: starIcon(starSize)),
              ],
            );
          }

          // 横並び（重なる場合）
          final rowFits = textWidth + gap + starSize <= tabWidth;
          if (rowFits) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label),
                const SizedBox(width: gap),
                starIcon(starSize),
              ],
            );
          }

          // 縮小表示（横並びでも収まらない場合）。
          // ここは「入らないと分かっている」経路なので、Flexible + ellipsis で
          // 必ず幅に収める。短縮名を持たない停留所（古泉循環器内科クリニック前
          // など）を選ぶと、11px でもタブ幅を超える（#177）
          return Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
              const SizedBox(width: 2),
              starIcon(14),
            ],
          );
        },
      ),
    );
  }

  void _toggleDayTypeView() {
    final dayNotifier = ref.read(dayTypeOverrideProvider.notifier);
    final seasonNotifier = ref.read(seasonOverrideProvider.notifier);
    if (dayNotifier.state != null) {
      dayNotifier.state = null;
      seasonNotifier.state = null;
      return;
    }
    // 当日以外モードに入るときは、当日と逆のダイヤを初期表示する
    // （平日に土日祝ダイヤを確認する、が主なユースケースのため）
    final now = DateTime.now();
    final today = DayType.fromDate(now);
    dayNotifier.state = today == DayType.weekday
        ? DayType.weekendHoliday
        : DayType.weekday;
    // 期別は当日のものを初期値とする（主目的は曜日ダイヤの確認のため）
    seasonNotifier.state = SeasonType.fromDate(now);
  }

  @override
  Widget build(BuildContext context) {
    final scheduleAsync = ref.watch(scheduleViewModelProvider);
    final favoriteAsync = ref.watch(favoriteTabProvider);
    final favoriteStopId = favoriteAsync.valueOrNull?.stopId;
    final selectionAsync = ref.watch(stopSelectionProvider);
    final selection = selectionAsync.valueOrNull ?? StopSelection.initial;
    final dayType = ref.watch(dayTypeOverrideProvider);
    final season = ref.watch(seasonOverrideProvider);

    // お気に入りタブの初回適用（アプリ起動時のみ）。
    //
    // 停留所の選択と favorite の両方が揃ってから適用する。ref.listen は変化時に
    // しか発火しないため、片方が先に解決した時点で適用済みにすると、あとから
    // もう片方が届いても再適用されない。build で両方を watch して判定する。
    final applyFavorite =
        !_favoriteApplied && favoriteAsync.hasValue && selectionAsync.hasValue;
    if (applyFavorite) _favoriteApplied = true;

    // 設定でバス停を足す・外す・並べ替えるとここに届く
    if (applyFavorite || !listEquals(_tabStopIds, selection.stopIds)) {
      _retuneTabs(
        selection.stopIds,
        focusStopId: applyFavorite ? favoriteStopId : null,
      );
    }
    final stopIds = _tabStopIds;

    return Scaffold(
      backgroundColor: context.appColors.background,
      appBar: AppBar(
        backgroundColor: context.appColors.background,
        foregroundColor: AppColors.primary,
        title: const Text(
          'Kagi-Bus',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 18,
            letterSpacing: 3,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (kDebugMode) ...[
            Consumer(builder: (context, ref, _) {
              final debugTime = ref.watch(debugTimeProvider);
              return IconButton(
                icon: Icon(
                  Icons.access_time,
                  color: debugTime != null
                      ? AppColors.warning
                      : context.appColors.textDisabled,
                ),
                tooltip: debugTime != null
                    ? '時刻オーバーライド中 (タップでリセット/変更)'
                    : 'デバッグ: 時刻を設定',
                onPressed: () => _onDebugTimeTap(context, ref, debugTime),
              );
            }),
          ],
          scheduleAsync.maybeWhen(
            data: (r) => r.data.current.pdfUrl.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.open_in_browser,
                        color: AppColors.primary),
                    tooltip: '時刻表原文を開く',
                    onPressed: () => launchUrl(
                      Uri.parse(r.data.current.pdfUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
          scheduleAsync.maybeWhen(
            data: (r) => r.data.upcoming != null
                ? IconButton(
                    icon: const Icon(Icons.calendar_month,
                        color: AppColors.warning),
                    tooltip: '来週のダイヤ',
                    onPressed: () => _showUpcomingSheet(
                      context,
                      r.data.upcoming!,
                      r.data.stopMaster,
                    ),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
          IconButton(
            icon: Icon(
              Icons.event_repeat,
              color: dayType != null ? AppColors.warning : AppColors.primary,
            ),
            tooltip: dayType != null ? '当日のダイヤに戻る' : '当日以外のダイヤを表示',
            onPressed: _toggleDayTypeView,
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: AppColors.primary),
            tooltip: '設定',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            onPressed: () =>
                ref.read(scheduleViewModelProvider.notifier).refresh(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: context.appColors.textDisabled,
          tabs: [
            for (final id in stopIds)
              _buildTab(
                // まだ取得できていなければ ID が出る（起動直後の一瞬のみ）
                (scheduleAsync.valueOrNull?.data.stopMaster ?? const [])
                    .labelOf(id),
                id,
                favoriteStopId,
              ),
          ],
        ),
      ),
      body: Stack(
        children: [
          scheduleAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
            error: (e, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('エラー: $e',
                      style: const TextStyle(color: AppColors.error)),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () =>
                        ref.read(scheduleViewModelProvider.notifier).refresh(),
                    child: const Text('再試行',
                        style: TextStyle(color: AppColors.primary)),
                  ),
                ],
              ),
            ),
            data: (result) {
              return Column(
                children: [
                  if (result.isFromCache)
                    OfflineCacheBanner(updatedAt: result.data.updatedAt),
                  if (dayType != null) ...[
                    _DayTypeSelector(dayType: dayType),
                    _SeasonSelector(
                      season: season ?? SeasonType.fromDate(DateTime.now()),
                    ),
                  ],
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        for (final id in stopIds)
                          _StopTab(
                            key: ValueKey(id),
                            timetable: result.data.current,
                            stopId: id,
                            stopMaster: result.data.stopMaster,
                            updatedAt: result.data.updatedAt,
                            dayType: dayType,
                            season: season,
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          if (!kIsWeb && !_bannerDismissed)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _BannerAdWidget(
                onDismissed: () => setState(() => _bannerDismissed = true),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _onDebugTimeTap(
      BuildContext context, WidgetRef ref, DateTime? current) async {
    if (current != null) {
      // オーバーライド中: リセットか変更かを選択
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: ctx.appColors.surface,
          title: const Text('時刻オーバーライド',
              style: TextStyle(color: AppColors.primary)),
          content: Text(
            '現在: ${current.hour.toString().padLeft(2, '0')}:${current.minute.toString().padLeft(2, '0')}',
            style: TextStyle(color: ctx.appColors.textPrimary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'reset'),
              child: const Text('リセット',
                  style: TextStyle(color: AppColors.error)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'change'),
              child: const Text('変更',
                  style: TextStyle(color: AppColors.warning)),
            ),
          ],
        ),
      );
      if (choice == 'reset') {
        ref.read(debugTimeProvider.notifier).state = null;
        return;
      }
      if (choice != 'change') return;
    }

    // 時刻ピッカーを表示
    if (!context.mounted) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: current != null
          ? TimeOfDay(hour: current.hour, minute: current.minute)
          : TimeOfDay.now(),
    );
    if (picked == null) return;

    final now = DateTime.now();
    ref.read(debugTimeProvider.notifier).state = DateTime(
      now.year,
      now.month,
      now.day,
      picked.hour,
      picked.minute,
    );
  }

  void _showUpcomingSheet(
    BuildContext context,
    BusTimetable upcoming,
    List<BusStop> stopMaster,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appColors.bottomSheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: context.appColors.textDisabled,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                '来週のダイヤ  ${upcoming.validFrom} 〜 ${upcoming.validTo}',
                style: const TextStyle(
                  color: AppColors.warning,
                  fontSize: 13,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 16),
              const Text('千歳駅発', style: TextStyle(color: AppColors.primary, fontSize: 12, letterSpacing: 3)),
              const SizedBox(height: 8),
              ScheduleList(
                stopMaster: stopMaster,
                timetable: upcoming,
                stopId: 'chitose',
                destination: BusDestination.campus,
              ),
              const SizedBox(height: 16),
              const Text('南千歳発', style: TextStyle(color: AppColors.primary, fontSize: 12, letterSpacing: 3)),
              const SizedBox(height: 8),
              ScheduleList(
                stopMaster: stopMaster,
                timetable: upcoming,
                stopId: 'minamiChitose',
                destination: BusDestination.campus,
              ),
              const SizedBox(height: 16),
              const Text('研究棟発 → 本部棟', style: TextStyle(color: AppColors.primary, fontSize: 12, letterSpacing: 3)),
              const SizedBox(height: 8),
              ScheduleList(
                stopMaster: stopMaster,
                timetable: upcoming,
                stopId: 'kenkyuto',
                destination: BusDestination.campus,
              ),
              const SizedBox(height: 16),
              const Text('研究棟発 → 千歳駅', style: TextStyle(color: AppColors.primary, fontSize: 12, letterSpacing: 3)),
              const SizedBox(height: 8),
              ScheduleList(
                stopMaster: stopMaster,
                timetable: upcoming,
                stopId: 'kenkyuto',
                destination: BusDestination.station,
              ),
              const SizedBox(height: 16),
              const Text('本部棟発', style: TextStyle(color: AppColors.primary, fontSize: 12, letterSpacing: 3)),
              const SizedBox(height: 8),
              ScheduleList(
                stopMaster: stopMaster,
                timetable: upcoming,
                stopId: 'honbuto',
                destination: BusDestination.station,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 当日以外モードで表示するダイヤ種別（平日 / 土日祝）の切り替えボタン。
/// 全タブ共通の設定のため TabBarView の外（上部）に配置する。
class _DayTypeSelector extends ConsumerWidget {
  const _DayTypeSelector({required this.dayType});

  final DayType dayType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SegmentedButton<DayType>(
        segments: const [
          ButtonSegment(
            value: DayType.weekday,
            label: Text('平日ダイヤ'),
          ),
          ButtonSegment(
            value: DayType.weekendHoliday,
            label: Text('土日祝ダイヤ'),
          ),
        ],
        selected: {dayType},
        onSelectionChanged: (selection) =>
            ref.read(dayTypeOverrideProvider.notifier).state = selection.first,
        style: SegmentedButton.styleFrom(
          backgroundColor: context.appColors.surface,
          foregroundColor: context.appColors.textTertiary,
          selectedBackgroundColor: AppColors.primary,
          selectedForegroundColor: AppColors.onPrimary,
        ),
      ),
    );
  }
}

/// 当日以外モードで表示する期別（授業期 / 学休期）の切り替えボタン。
/// 学休期は美々空港線の直通便が大幅に減便されるため、平日/土日祝とは
/// 独立した軸として選択できるようにしている（Issue #132）。
class _SeasonSelector extends ConsumerWidget {
  const _SeasonSelector({required this.season});

  final SeasonType season;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SegmentedButton<SeasonType>(
        segments: const [
          ButtonSegment(
            value: SeasonType.academic,
            label: Text('授業期'),
          ),
          ButtonSegment(
            value: SeasonType.vacation,
            label: Text('学休期'),
          ),
        ],
        selected: {season},
        onSelectionChanged: (selection) =>
            ref.read(seasonOverrideProvider.notifier).state = selection.first,
        style: SegmentedButton.styleFrom(
          backgroundColor: context.appColors.surface,
          foregroundColor: context.appColors.textTertiary,
          selectedBackgroundColor: AppColors.primary,
          selectedForegroundColor: AppColors.onPrimary,
        ),
      ),
    );
  }
}

class _StopTab extends StatefulWidget {
  const _StopTab({
    super.key,
    required this.stopId,
    required this.stopMaster,
    required this.timetable,
    required this.updatedAt,
    this.dayType,
    this.season,
  });
  final String stopId;
  final List<BusStop> stopMaster;
  final BusTimetable timetable;
  final String updatedAt;
  final DayType? dayType;
  final SeasonType? season;

  /// この停留所から行ける行き先。途中の停留所は上下両方向のバスが通るため、
  /// 複数あるときは利用者に選ばせる。データから導くのでハードコードしない。
  List<String> get destinations {
    final seen = <String>{};
    for (final e in timetable.schedules) {
      if (e.boardingStopId == stopId) seen.add(e.destination);
    }
    // 表示順を安定させる（科技大 → 千歳駅）
    const order = [BusDestination.campus, BusDestination.station];
    final out = order.where(seen.contains).toList();
    for (final d in seen) {
      if (!out.contains(d)) out.add(d);
    }
    return out;
  }

  /// [destination] へ向かうとき、この停留所から見た終点の表示名。
  /// 「→ 本部棟」のように出す。最後の到着地をデータから引く
  String terminusLabel(String destination) {
    for (final e in timetable.schedules) {
      if (e.boardingStopId != stopId || e.destination != destination) continue;
      final last = e.arrivals.keys.lastOrNull;
      if (last == null) continue;
      return stopMaster.labelOf(last);
    }
    return destination;
  }

  @override
  State<_StopTab> createState() => _StopTabState();
}

class _StopTabState extends State<_StopTab> {
  String? _selected;

  /// 時刻表の全便を走査するので、build のたびに数えない
  late List<String> _destinations;

  @override
  void initState() {
    super.initState();
    _destinations = widget.destinations;
  }

  @override
  void didUpdateWidget(_StopTab old) {
    super.didUpdateWidget(old);
    if (!identical(old.timetable, widget.timetable) ||
        old.stopId != widget.stopId) {
      _destinations = widget.destinations;
    }
  }

  String get _destination =>
      _selected ?? _destinations.firstOrNull ?? BusDestination.campus;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 現在は無効化中だが、再有効化したときにここへ出る
              WeekendWarningBanner(),
              SeasonNoticeBanner(),
            ],
          ),
        ),
        // 行き先が複数ある停留所だけ切り替えを出す。
        // 終点や片方向しか通らない停留所では選ぶものが無い
        if (_destinations.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<String>(
              segments: [
                for (final d in _destinations)
                  ButtonSegment(
                    value: d,
                    label: Text('→ ${widget.terminusLabel(d)}'),
                  ),
              ],
              selected: {_destination},
              onSelectionChanged: (selection) =>
                  setState(() => _selected = selection.first),
              style: SegmentedButton.styleFrom(
                backgroundColor: context.appColors.surface,
                foregroundColor: context.appColors.textTertiary,
                selectedBackgroundColor: AppColors.primary,
                selectedForegroundColor: AppColors.onPrimary,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 当日以外のダイヤ表示では NEXT BUS の概念がないため非表示
              if (widget.dayType == null) ...[
                Text('NEXT BUS', style: TextStyle(color: context.appColors.textTertiary, fontSize: 12, letterSpacing: 3)),
                const SizedBox(height: 8),
                // IndexedStack で両方向の NextBusDisplay を常時保持し、
                // 本部棟↔千歳駅切り替え時のレイアウトガタつきを防ぐ。
                // onVerticalDragUpdate を指定することで VerticalDragGestureRecognizer が
                // ジェスチャーアリーナに参加し、縦スワイプをここで消費する。
                // これにより TabBarView（PageView）への伝播を防ぐ。
                GestureDetector(
                  onVerticalDragUpdate: (_) {},
                  child: IndexedStack(
                    index: _destinations.indexOf(_destination).clamp(0, 99),
                    children: [
                      for (final d in _destinations)
                        NextBusDisplay(
                          timetable: widget.timetable,
                          stopId: widget.stopId,
                          stopMaster: widget.stopMaster,
                          destination: d,
                          showPlatform: widget.stopId == 'chitose',
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
              Text(widget.dayType == null ? "TODAY'S SCHEDULE" : 'SCHEDULE', style: TextStyle(color: context.appColors.textTertiary, fontSize: 12, letterSpacing: 3)),
              const SizedBox(height: 8),
            ],
          ),
        ),
        // IndexedStack で両 ScheduleList の State を常時保持することで
        // 本部棟↔千歳駅切り替え時にスクロール位置が独立して維持される。
        // PageStorageKey でスクロール位置を方向ごとに永続化する
        // （当日/ダイヤ種別ごとに独立させるため dayType もキーに含める）。
        // onVerticalDragUpdate を指定することで VerticalDragGestureRecognizer が
        // ジェスチャーアリーナに参加し、スクロール不可時の縦スワイプを消費する。
        // これにより TabBarView（PageView）への伝播を防ぐ。
        Expanded(
          child: GestureDetector(
            onVerticalDragUpdate: (_) {},
            child: IndexedStack(
              index: _destinations.indexOf(_destination).clamp(0, 99),
              children: [
                for (final d in _destinations)
                  ScheduleList(
                    key: ValueKey(
                        '${widget.stopId}_${d}_${widget.dayType?.name ?? 'today'}_${widget.season?.name ?? ''}'),
                    timetable: widget.timetable,
                    stopId: widget.stopId,
                    stopMaster: widget.stopMaster,
                    destination: d,
                    dayType: widget.dayType,
                    season: widget.season,
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Text(
            '更新: ${widget.updatedAt}',
            style: TextStyle(color: context.appColors.textDisabled, fontSize: 11),
          ),
        ),
      ],
    );
  }
}


class _BannerAdWidget extends StatefulWidget {
  const _BannerAdWidget({required this.onDismissed});

  final VoidCallback onDismissed;

  @override
  State<_BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<_BannerAdWidget> {
  BannerAd? _bannerAd;

  static String get _adUnitId {
    if (Platform.isAndroid) {
      return AppConstants.admobAndroidAdUnitId;
    } else {
      return AppConstants.admobIosAdUnitId;
    }
  }

  @override
  void initState() {
    super.initState();
    _bannerAd = BannerAd(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) => setState(() {}),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          setState(() => _bannerAd = null);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_bannerAd == null) return const SizedBox.shrink();
    return Stack(
      alignment: Alignment.topRight,
      children: [
        SizedBox(
          width: double.infinity,
          height: _bannerAd!.size.height.toDouble(),
          child: AdWidget(ad: _bannerAd!),
        ),
        GestureDetector(
          onTap: widget.onDismissed,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
