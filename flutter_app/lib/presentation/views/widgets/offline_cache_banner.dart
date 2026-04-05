import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class OfflineCacheBanner extends StatelessWidget {
  const OfflineCacheBanner({super.key, required this.updatedAt});

  final String updatedAt;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.warningBackground,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: AppColors.warning, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'キャッシュデータを表示中（データ更新: $updatedAt）',
              style: const TextStyle(
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
