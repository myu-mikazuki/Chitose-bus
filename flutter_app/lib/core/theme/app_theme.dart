import 'package:flutter/material.dart';
import 'app_colors.dart';

/// アプリのテーマ定義
class AppTheme {
  AppTheme._();

  static ThemeData light() => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
        ),
        fontFamily: 'monospace',
        fontFamilyFallback: const ['NotoSansJP'],
      );

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
