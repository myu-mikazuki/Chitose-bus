import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../viewmodels/schedule_viewmodel.dart';

class WeekendWarningBanner extends ConsumerWidget {
  const WeekendWarningBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(countdownProvider);
    final isWeekend = now.weekday == DateTime.saturday ||
        now.weekday == DateTime.sunday;

    if (!isWeekend) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0x26FFB000), // 0xFFFFB000 at ~15% opacity
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              color: Color(0xFFFFB000), size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '土日祝日はバスが運行していない場合があります',
              style: TextStyle(
                color: Color(0xFFFFB000),
                fontSize: 12,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
