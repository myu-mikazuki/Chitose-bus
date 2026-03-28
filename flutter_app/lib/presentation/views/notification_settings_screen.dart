import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_colors_theme.dart';
import '../../domain/entities/notification_settings.dart';
import '../viewmodels/notification_viewmodel.dart';

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(notificationSettingsProvider);

    return Scaffold(
      backgroundColor: context.appColors.background,
      appBar: AppBar(
        backgroundColor: context.appColors.background,
        foregroundColor: AppColors.primary,
        title: const Text(
          '通知設定',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 16,
            letterSpacing: 2,
          ),
        ),
      ),
      body: settingsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => Center(
          child: Text('エラー: $e',
              style: const TextStyle(color: AppColors.error)),
        ),
        data: (settings) => _SettingsBody(settings: settings),
      ),
    );
  }
}

class _SettingsBody extends ConsumerWidget {
  const _SettingsBody({required this.settings});

  final NotificationSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(notificationSettingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Enable toggle
        _SectionCard(
          child: SwitchListTile(
            title: Text(
              '出発通知を有効にする',
              style: TextStyle(color: context.appColors.textPrimary, letterSpacing: 1),
            ),
            subtitle: Text(
              '次のバスが出発する前に通知を受け取ります',
              style: TextStyle(color: context.appColors.textTertiary, fontSize: 12),
            ),
            value: settings.enabled,
            activeThumbColor: AppColors.primary,
            onChanged: (v) => v
                ? notifier.enableNotifications(settings)
                : notifier.saveSettings(settings.copyWith(enabled: false)),
          ),
        ),
        const SizedBox(height: 16),

        // Minutes before
        _SectionCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '通知タイミング',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      letterSpacing: 2),
                ),
                const SizedBox(height: 12),
                DropdownButton<int>(
                  value: settings.minutesBefore,
                  dropdownColor: context.appColors.surface,
                  style: TextStyle(
                      color: context.appColors.textPrimary, fontSize: 16),
                  isExpanded: true,
                  underline: Divider(color: context.appColors.divider),
                  items: NotificationSettings.minutesOptions
                      .map((m) => DropdownMenuItem(
                            value: m,
                            child: Text('$m 分前'),
                          ))
                      .toList(),
                  onChanged: settings.enabled
                      ? (v) => notifier.saveSettings(
                          settings.copyWith(minutesBefore: v ?? 10))
                      : null,
                ),
              ],
            ),
          ),
        ),
      ],
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
