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
import 'settings_screen.dart';
import 'widgets/next_bus_display.dart';
import 'widgets/offline_cache_banner.dart';
import 'widgets/schedule_list.dart';
import 'widgets/weekend_warning_banner.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _bannerDismissed = false;
  bool _favoriteApplied = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Tab _buildTab(String label, int index, int? favoriteTabIndex) {
    return Tab(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isFavorite = favoriteTabIndex == index;
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
                    .toggleFavorite(index),
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

          // 縮小表示（横並びでも収まらない場合）
          return Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: const TextStyle(fontSize: 11)),
              const SizedBox(width: 2),
              starIcon(14),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheduleAsync = ref.watch(scheduleViewModelProvider);
    final favoriteAsync = ref.watch(favoriteTabProvider);
    final favoriteTabIndex = favoriteAsync.valueOrNull?.tabIndex;

    // お気に入りタブの初回適用（アプリ起動時のみ）
    // build() 内の副作用は ref.listen に委ねる（Riverpod 推奨パターン）
    ref.listen(favoriteTabProvider, (prev, next) {
      if (_favoriteApplied) return;
      next.whenData((fav) {
        _favoriteApplied = true;
        if (fav.hasFavorite) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _tabController.index = fav.tabIndex!;
          });
        }
      });
    });

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
                    onPressed: () => _showUpcomingSheet(context, r.data.upcoming!),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
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
            _buildTab('千歳駅', 0, favoriteTabIndex),
            _buildTab('南千歳', 1, favoriteTabIndex),
            _buildTab('研究棟', 2, favoriteTabIndex),
            _buildTab('本部棟', 3, favoriteTabIndex),
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
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _DirectionTab(timetable: result.data.current, direction: BusDirection.fromChitose, updatedAt: result.data.updatedAt),
                        _DirectionTab(timetable: result.data.current, direction: BusDirection.fromMinamiChitose, updatedAt: result.data.updatedAt),
                        _KenkyutoTab(timetable: result.data.current, updatedAt: result.data.updatedAt),
                        _DirectionTab(timetable: result.data.current, direction: BusDirection.fromHonbuto, updatedAt: result.data.updatedAt),
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

  void _showUpcomingSheet(BuildContext context, BusTimetable upcoming) {
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
              ScheduleList(timetable: upcoming, direction: BusDirection.fromChitose),
              const SizedBox(height: 16),
              const Text('南千歳発', style: TextStyle(color: AppColors.primary, fontSize: 12, letterSpacing: 3)),
              const SizedBox(height: 8),
              ScheduleList(timetable: upcoming, direction: BusDirection.fromMinamiChitose),
              const SizedBox(height: 16),
              const Text('研究棟発 → 本部棟', style: TextStyle(color: AppColors.primary, fontSize: 12, letterSpacing: 3)),
              const SizedBox(height: 8),
              ScheduleList(timetable: upcoming, direction: BusDirection.fromKenkyutoToHonbuto),
              const SizedBox(height: 16),
              const Text('研究棟発 → 千歳駅', style: TextStyle(color: AppColors.primary, fontSize: 12, letterSpacing: 3)),
              const SizedBox(height: 8),
              ScheduleList(timetable: upcoming, direction: BusDirection.fromKenkyutoToStation),
              const SizedBox(height: 16),
              const Text('本部棟発', style: TextStyle(color: AppColors.primary, fontSize: 12, letterSpacing: 3)),
              const SizedBox(height: 8),
              ScheduleList(timetable: upcoming, direction: BusDirection.fromHonbuto),
            ],
          ),
        ),
      ),
    );
  }
}

class _KenkyutoTab extends StatefulWidget {
  const _KenkyutoTab({required this.timetable, required this.updatedAt});
  final BusTimetable timetable;
  final String updatedAt;

  @override
  State<_KenkyutoTab> createState() => _KenkyutoTabState();
}

class _KenkyutoTabState extends State<_KenkyutoTab> {
  BusDirection _direction = BusDirection.fromKenkyutoToHonbuto;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: WeekendWarningBanner(),
        ),
        // SegmentedButton で本部棟/千歳駅を切り替え
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<BusDirection>(
            segments: const [
              ButtonSegment(
                value: BusDirection.fromKenkyutoToHonbuto,
                label: Text('→ 本部棟'),
              ),
              ButtonSegment(
                value: BusDirection.fromKenkyutoToStation,
                label: Text('→ 千歳駅'),
              ),
            ],
            selected: {_direction},
            onSelectionChanged: (selection) =>
                setState(() => _direction = selection.first),
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
              Text('NEXT BUS', style: TextStyle(color: context.appColors.textTertiary, fontSize: 12, letterSpacing: 3)),
              const SizedBox(height: 8),
              // IndexedStack で両方向の NextBusDisplay を常時保持し、
              // 本部棟↔千歳駅切り替え時のレイアウトガタつきを防ぐ。
              IndexedStack(
                index: _direction == BusDirection.fromKenkyutoToHonbuto ? 0 : 1,
                children: [
                  NextBusDisplay(timetable: widget.timetable, direction: BusDirection.fromKenkyutoToHonbuto),
                  NextBusDisplay(timetable: widget.timetable, direction: BusDirection.fromKenkyutoToStation),
                ],
              ),
              const SizedBox(height: 24),
              Text("TODAY'S SCHEDULE", style: TextStyle(color: context.appColors.textTertiary, fontSize: 12, letterSpacing: 3)),
              const SizedBox(height: 8),
            ],
          ),
        ),
        // IndexedStack で両 ScheduleList の State を常時保持することで
        // 本部棟↔千歳駅切り替え時にスクロール位置が独立して維持される。
        // PageStorageKey でスクロール位置を方向ごとに永続化する。
        Expanded(
          child: IndexedStack(
            index: _direction == BusDirection.fromKenkyutoToHonbuto ? 0 : 1,
            children: [
              ScheduleList(
                key: const PageStorageKey('kenkyuto_honbuto'),
                timetable: widget.timetable,
                direction: BusDirection.fromKenkyutoToHonbuto,
              ),
              ScheduleList(
                key: const PageStorageKey('kenkyuto_chitose'),
                timetable: widget.timetable,
                direction: BusDirection.fromKenkyutoToStation,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Text(
            '更新: ${widget.updatedAt}  有効期間: ${widget.timetable.validFrom} 〜 ${widget.timetable.validTo}',
            style: TextStyle(color: context.appColors.textDisabled, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _DirectionTab extends StatelessWidget {
  const _DirectionTab({
    required this.timetable,
    required this.direction,
    required this.updatedAt,
  });

  final BusTimetable timetable;
  final BusDirection direction;
  final String updatedAt;

  @override
  Widget build(BuildContext context) {
    // Column + Expanded 構成により:
    // - NEXT BUS セクションを固定ヘッダとして常時表示
    // - ScheduleList に有界な高さを与えて独立スクロール可能にする
    // - Scrollable.ensureVisible が ListView 自身をスクロール（親は不変）
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const WeekendWarningBanner(),
              const SizedBox(height: 8),
              Text(
                'NEXT BUS',
                style: TextStyle(
                  color: context.appColors.textTertiary,
                  fontSize: 12,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 8),
              NextBusDisplay(
                timetable: timetable,
                direction: direction,
                showPlatform: direction == BusDirection.fromChitose,
              ),
              const SizedBox(height: 24),
              Text(
                'TODAY\'S SCHEDULE',
                style: TextStyle(
                  color: context.appColors.textTertiary,
                  fontSize: 12,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        Expanded(
          child: ScheduleList(timetable: timetable, direction: direction),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Text(
            '更新: $updatedAt  有効期間: ${timetable.validFrom} 〜 ${timetable.validTo}',
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
