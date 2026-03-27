import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import 'bug_report_screen.dart';
import 'notification_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _launchUrl(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.primary,
        title: const Text(
          '設定',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 16,
            letterSpacing: 2,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(label: '通知'),
          _SectionCard(
            child: ListTile(
              leading: const Icon(Icons.notifications_outlined,
                  color: AppColors.primary),
              title: const Text(
                '通知設定',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              trailing: const Icon(Icons.chevron_right,
                  color: AppColors.textDisabled),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const NotificationSettingsScreen()),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(label: 'アプリ情報'),
          _SectionCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined,
                      color: AppColors.primary),
                  title: const Text(
                    'バグを報告',
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                  trailing: const Icon(Icons.chevron_right,
                      color: AppColors.textDisabled),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const BugReportScreen()),
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                ListTile(
                  leading: const Icon(Icons.policy_outlined,
                      color: AppColors.primary),
                  title: const Text(
                    'プライバシーポリシー',
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                  trailing: const Icon(Icons.open_in_new,
                      color: AppColors.textDisabled, size: 18),
                  onTap: () => _launchUrl(AppConstants.privacyPolicyUrl),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 12,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}
