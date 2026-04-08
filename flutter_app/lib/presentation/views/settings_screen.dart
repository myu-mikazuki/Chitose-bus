import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_colors_theme.dart';
import '../viewmodels/app_info_viewmodel.dart';
import '../viewmodels/display_settings_viewmodel.dart';
import 'contact_screen.dart';
import 'notification_settings_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _launchUrl(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.appColors.background,
      appBar: AppBar(
        backgroundColor: context.appColors.background,
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
              title: Text(
                '通知設定',
                style: TextStyle(color: context.appColors.textPrimary),
              ),
              trailing: Icon(Icons.chevron_right,
                  color: context.appColors.textDisabled),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const NotificationSettingsScreen()),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(label: '表示'),
          _SectionCard(
            child: Consumer(
              builder: (context, ref, _) {
                final settings =
                    ref.watch(displaySettingsProvider).valueOrNull;
                return SwitchListTile(
                  secondary: const Icon(Icons.label_outline,
                      color: AppColors.primary),
                  title: Text(
                    '講時タグを表示',
                    style: TextStyle(color: context.appColors.textPrimary),
                  ),
                  subtitle: Text(
                    'バスが間に合う講時を時刻表に表示します',
                    style: TextStyle(
                        color: context.appColors.textTertiary, fontSize: 12),
                  ),
                  value: settings?.showLectureTags ?? true,
                  activeColor: AppColors.primary,
                  onChanged: settings == null
                      ? null
                      : (v) => ref
                          .read(displaySettingsProvider.notifier)
                          .saveSettings(
                              settings.copyWith(showLectureTags: v)),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(label: 'アプリ情報'),
          _SectionCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.contact_support_outlined,
                      color: AppColors.primary),
                  title: Text(
                    'お問い合わせ',
                    style: TextStyle(color: context.appColors.textPrimary),
                  ),
                  trailing: Icon(Icons.chevron_right,
                      color: context.appColors.textDisabled),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ContactScreen()),
                  ),
                ),
                Divider(height: 1, color: context.appColors.border),
                ListTile(
                  leading: const Icon(Icons.policy_outlined,
                      color: AppColors.primary),
                  title: Text(
                    'プライバシーポリシー',
                    style: TextStyle(color: context.appColors.textPrimary),
                  ),
                  trailing: Icon(Icons.open_in_new,
                      color: context.appColors.textDisabled, size: 18),
                  onTap: () => _launchUrl(AppConstants.privacyPolicyUrl),
                ),
                Divider(height: 1, color: context.appColors.border),
                ListTile(
                  leading: const Icon(Icons.info_outline,
                      color: AppColors.primary),
                  title: Text(
                    'バージョン',
                    style: TextStyle(color: context.appColors.textPrimary),
                  ),
                  trailing: ref.watch(packageInfoProvider).when(
                        data: (info) => Text(
                          '${info.version}+${info.buildNumber}',
                          style: TextStyle(
                              color: context.appColors.textDisabled),
                        ),
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
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
        border: Border.all(color: context.appColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}
