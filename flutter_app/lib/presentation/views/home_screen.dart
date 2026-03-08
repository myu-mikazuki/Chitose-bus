import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/entities/bus_schedule.dart';
import '../viewmodels/notification_viewmodel.dart';
import '../viewmodels/schedule_viewmodel.dart';
import 'notification_settings_screen.dart';
import 'widgets/next_bus_display.dart';
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

  @override
  Widget build(BuildContext context) {
    final scheduleAsync = ref.watch(scheduleViewModelProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        foregroundColor: const Color(0xFF00FF88),
        title: const Text(
          'CIST シャトルバス',
          style: TextStyle(
            color: Color(0xFF00FF88),
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
                      ? const Color(0xFFFFB000)
                      : const Color(0xFF444444),
                ),
                tooltip: debugTime != null
                    ? '時刻オーバーライド中 (タップでリセット/変更)'
                    : 'デバッグ: 時刻を設定',
                onPressed: () => _onDebugTimeTap(context, ref, debugTime),
              );
            }),
          ],
          scheduleAsync.maybeWhen(
            data: (r) => r.current.pdfUrl.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.open_in_browser,
                        color: Color(0xFF00FF88)),
                    tooltip: '時刻表原文を開く',
                    onPressed: () => launchUrl(
                      Uri.parse(r.current.pdfUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
          scheduleAsync.maybeWhen(
            data: (r) => r.upcoming != null
                ? IconButton(
                    icon: const Icon(Icons.calendar_month,
                        color: Color(0xFFFFB000)),
                    tooltip: '来週のダイヤ',
                    onPressed: () => _showUpcomingSheet(context, r.upcoming!),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined,
                color: Color(0xFF00FF88)),
            tooltip: '通知設定',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const NotificationSettingsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF00FF88)),
            onPressed: () =>
                ref.read(scheduleViewModelProvider.notifier).refresh(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00FF88),
          labelColor: const Color(0xFF00FF88),
          unselectedLabelColor: const Color(0xFF444444),
          tabs: const [
            Tab(text: '千歳駅'),
            Tab(text: '南千歳'),
            Tab(text: '研究棟'),
            Tab(text: '本部棟'),
          ],
        ),
      ),
      body: scheduleAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF00FF88)),
        ),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('エラー: $e',
                  style: const TextStyle(color: Color(0xFFFF4444))),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () =>
                    ref.read(scheduleViewModelProvider.notifier).refresh(),
                child: const Text('再試行',
                    style: TextStyle(color: Color(0xFF00FF88))),
              ),
            ],
          ),
        ),
        data: (response) {
          // Schedule notifications when timetable data is available
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref
                .read(notificationSettingsProvider.notifier)
                .scheduleForTimetable(response.current);
          });
          return TabBarView(
            controller: _tabController,
            children: [
              _DirectionTab(timetable: response.current, direction: BusDirection.fromChitose, updatedAt: response.updatedAt),
              _DirectionTab(timetable: response.current, direction: BusDirection.fromMinamiChitose, updatedAt: response.updatedAt),
              _KenkyutoTab(timetable: response.current, updatedAt: response.updatedAt),
              _DirectionTab(timetable: response.current, direction: BusDirection.fromHonbuto, updatedAt: response.updatedAt),
            ],
          );
        },
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
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text('時刻オーバーライド',
              style: TextStyle(color: Color(0xFF00FF88))),
          content: Text(
            '現在: ${current.hour.toString().padLeft(2, '0')}:${current.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(color: Color(0xFFCCCCCC)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'reset'),
              child: const Text('リセット',
                  style: TextStyle(color: Color(0xFFFF4444))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'change'),
              child: const Text('変更',
                  style: TextStyle(color: Color(0xFFFFB000))),
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
      backgroundColor: const Color(0xFF111111),
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
                    color: const Color(0xFF444444),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                '来週のダイヤ  ${upcoming.validFrom} 〜 ${upcoming.validTo}',
                style: const TextStyle(
                  color: Color(0xFFFFB000),
                  fontSize: 13,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 16),
              const Text('千歳駅発', style: TextStyle(color: Color(0xFF00FF88), fontSize: 12, letterSpacing: 3)),
              const SizedBox(height: 8),
              ScheduleList(timetable: upcoming, direction: BusDirection.fromChitose),
              const SizedBox(height: 16),
              const Text('南千歳発', style: TextStyle(color: Color(0xFF00FF88), fontSize: 12, letterSpacing: 3)),
              const SizedBox(height: 8),
              ScheduleList(timetable: upcoming, direction: BusDirection.fromMinamiChitose),
              const SizedBox(height: 16),
              const Text('研究棟発 → 本部棟', style: TextStyle(color: Color(0xFF00FF88), fontSize: 12, letterSpacing: 3)),
              const SizedBox(height: 8),
              ScheduleList(timetable: upcoming, direction: BusDirection.fromKenkyutoToHonbuto),
              const SizedBox(height: 16),
              const Text('研究棟発 → 千歳駅', style: TextStyle(color: Color(0xFF00FF88), fontSize: 12, letterSpacing: 3)),
              const SizedBox(height: 8),
              ScheduleList(timetable: upcoming, direction: BusDirection.fromKenkyutoToStation),
              const SizedBox(height: 16),
              const Text('本部棟発', style: TextStyle(color: Color(0xFF00FF88), fontSize: 12, letterSpacing: 3)),
              const SizedBox(height: 8),
              ScheduleList(timetable: upcoming, direction: BusDirection.fromHonbuto),
            ],
          ),
        ),
      ),
    );
  }
}

class _KenkyutoTab extends StatelessWidget {
  const _KenkyutoTab({required this.timetable, required this.updatedAt});
  final BusTimetable timetable;
  final String updatedAt;

  @override
  Widget build(BuildContext context) {
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
              const Text('NEXT BUS  → 本部棟', style: TextStyle(color: Color(0xFF666666), fontSize: 12, letterSpacing: 3)),
              const SizedBox(height: 8),
              NextBusDisplay(timetable: timetable, direction: BusDirection.fromKenkyutoToHonbuto),
              const SizedBox(height: 24),
              const Text("TODAY'S SCHEDULE  → 本部棟", style: TextStyle(color: Color(0xFF666666), fontSize: 12, letterSpacing: 3)),
              const SizedBox(height: 8),
            ],
          ),
        ),
        Expanded(
          child: ScheduleList(timetable: timetable, direction: BusDirection.fromKenkyutoToHonbuto),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('NEXT BUS  → 千歳駅', style: TextStyle(color: Color(0xFF666666), fontSize: 12, letterSpacing: 3)),
              const SizedBox(height: 8),
              NextBusDisplay(timetable: timetable, direction: BusDirection.fromKenkyutoToStation),
              const SizedBox(height: 24),
              const Text("TODAY'S SCHEDULE  → 千歳駅", style: TextStyle(color: Color(0xFF666666), fontSize: 12, letterSpacing: 3)),
              const SizedBox(height: 8),
            ],
          ),
        ),
        Expanded(
          child: ScheduleList(timetable: timetable, direction: BusDirection.fromKenkyutoToStation),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Text('更新: $updatedAt  有効期間: ${timetable.validFrom} 〜 ${timetable.validTo}',
              style: const TextStyle(color: Color(0xFF444444), fontSize: 11)),
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
              const Text(
                'NEXT BUS',
                style: TextStyle(
                  color: Color(0xFF666666),
                  fontSize: 12,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 8),
              NextBusDisplay(timetable: timetable, direction: direction),
              const SizedBox(height: 24),
              const Text(
                'TODAY\'S SCHEDULE',
                style: TextStyle(
                  color: Color(0xFF666666),
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
            style: const TextStyle(color: Color(0xFF444444), fontSize: 11),
          ),
        ),
      ],
    );
  }
}
