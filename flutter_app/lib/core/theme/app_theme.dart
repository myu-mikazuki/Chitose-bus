import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_colors_theme.dart';

/// アプリのテーマ定義
class AppTheme {
  AppTheme._();

  static ThemeData dark() => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: AppColorsTheme.dark.background,
        fontFamily: 'monospace',
        fontFamilyFallback: const ['NotoSansJP'],
        extensions: const [AppColorsTheme.dark],
      );

  static ThemeData light() => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: AppColorsTheme.light.background,
        fontFamily: 'monospace',
        fontFamilyFallback: const ['NotoSansJP'],
        extensions: const [AppColorsTheme.light],
      );
}
