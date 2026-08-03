import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/bus_schedule.dart';
import '../../viewmodels/schedule_viewmodel.dart';

/// 当日が学休期ダイヤ、または年末年始の全便運休であることを知らせるバナー。
///
/// 学休期は美々空港線（特に直通便）の本数が授業期の半分以下に減るため、
/// 通常ダイヤとの取り違えを防ぐ目的で常時表示する。
class SeasonNoticeBanner extends ConsumerWidget {
  const SeasonNoticeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 当日以外のダイヤ表示中は、選択中の期別が別途表示されるため出さない
    if (ref.watch(dayTypeOverrideProvider) != null) {
      return const SizedBox.shrink();
    }

    final now = ref.watch(countdownProvider);

    if (ServiceCalendar.isSuspended(now)) {
      return const _Banner(
        icon: Icons.do_not_disturb_on_outlined,
        text: '年末年始（12/31〜1/3）は全便運休です',
        color: AppColors.error,
      );
    }

    if (SeasonType.fromDate(now) == SeasonType.vacation) {
      return const _Banner(
        icon: Icons.school_outlined,
        text: '学休期ダイヤで運行中です（直通便が減便されます）',
        color: AppColors.warning,
      );
    }

    return const SizedBox.shrink();
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.warningBackground,
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
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
