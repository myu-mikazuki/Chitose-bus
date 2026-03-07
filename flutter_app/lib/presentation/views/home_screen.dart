import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../domain/entities/bus_schedule.dart';
import '../viewmodels/schedule_viewmodel.dart';
import 'widgets/next_bus_display.dart';
import 'widgets/schedule_list.dart';

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
      bottomNavigationBar: const _BannerAdWidget(),
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
        data: (response) => TabBarView(
          controller: _tabController,
          children: [
            _DirectionTab(timetable: response.current, direction: BusDirection.fromChitose, updatedAt: response.updatedAt),
            _DirectionTab(timetable: response.current, direction: BusDirection.fromMinamiChitose, updatedAt: response.updatedAt),
            _KenkyutoTab(timetable: response.current, updatedAt: response.updatedAt),
            _DirectionTab(timetable: response.current, direction: BusDirection.fromHonbuto, updatedAt: response.updatedAt),
          ],
        ),
      ),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const Text('NEXT BUS  → 本部棟', style: TextStyle(color: Color(0xFF666666), fontSize: 12, letterSpacing: 3)),
          const SizedBox(height: 8),
          NextBusDisplay(timetable: timetable, direction: BusDirection.fromKenkyutoToHonbuto),
          const SizedBox(height: 24),
          const Text("TODAY'S SCHEDULE  → 本部棟", style: TextStyle(color: Color(0xFF666666), fontSize: 12, letterSpacing: 3)),
          const SizedBox(height: 8),
          ScheduleList(timetable: timetable, direction: BusDirection.fromKenkyutoToHonbuto),
          const SizedBox(height: 32),
          const Text('NEXT BUS  → 千歳駅', style: TextStyle(color: Color(0xFF666666), fontSize: 12, letterSpacing: 3)),
          const SizedBox(height: 8),
          NextBusDisplay(timetable: timetable, direction: BusDirection.fromKenkyutoToStation),
          const SizedBox(height: 24),
          const Text("TODAY'S SCHEDULE  → 千歳駅", style: TextStyle(color: Color(0xFF666666), fontSize: 12, letterSpacing: 3)),
          const SizedBox(height: 8),
          ScheduleList(timetable: timetable, direction: BusDirection.fromKenkyutoToStation),
          const SizedBox(height: 16),
          Text('更新: $updatedAt  有効期間: ${timetable.validFrom} 〜 ${timetable.validTo}',
              style: const TextStyle(color: Color(0xFF444444), fontSize: 11)),
        ],
      ),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          ScheduleList(timetable: timetable, direction: direction),
          const SizedBox(height: 16),
          Text(
            '更新: $updatedAt  有効期間: ${timetable.validFrom} 〜 ${timetable.validTo}',
            style: const TextStyle(color: Color(0xFF444444), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _BannerAdWidget extends StatefulWidget {
  const _BannerAdWidget();

  @override
  State<_BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<_BannerAdWidget> {
  BannerAd? _bannerAd;

  static String get _adUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/6300978111';
    } else {
      return 'ca-app-pub-3940256099942544/2934735716';
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
    return SizedBox(
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
