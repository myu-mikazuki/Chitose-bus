import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../viewmodels/schedule_viewmodel.dart';

class WeekendWarningBanner extends ConsumerWidget {
  const WeekendWarningBanner({super.key});

  // 表示を一時無効化（将来の再有効化に備えてコードを保持）
  static const bool _enabled = false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_enabled) return const SizedBox.shrink();

    final now = ref.watch(countdownProvider);
    final isWeekend = now.weekday == DateTime.saturday ||
        now.weekday == DateTime.sunday;

    if (!isWeekend) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.warningBackground,
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              color: AppColors.warning, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '土日祝日はバスが運行していない場合があります',
              style: TextStyle(
                color: AppColors.warning,
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
