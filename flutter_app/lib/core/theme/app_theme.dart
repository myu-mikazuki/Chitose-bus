import 'package:flutter/material.dart';
import 'app_colors.dart';

/// アプリのテーマ定義
class AppTheme {
  AppTheme._();

  static ThemeData dark() => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: AppColors.background,
        fontFamily: 'monospace',
        fontFamilyFallback: const ['NotoSansJP'],
      );
}
