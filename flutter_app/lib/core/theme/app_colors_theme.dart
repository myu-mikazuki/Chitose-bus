import 'package:flutter/material.dart';

/// テーマに応じて切り替わるカラートークン。
/// [dark] / [light] の静的定数を ThemeData.extensions に注入し、
/// BuildContext 拡張 [AppColorsThemeX.appColors] で参照する。
class AppColorsTheme extends ThemeExtension<AppColorsTheme> {
  const AppColorsTheme({
    required this.background,
    required this.surface,
    required this.bottomSheet,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.border,
    required this.divider,
  });

  final Color background;
  final Color surface;
  final Color bottomSheet;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;
  final Color border;
  final Color divider;

  static const dark = AppColorsTheme(
    background: Color(0xFF1F1F1F),
    surface: Color(0xFF2A2A2A),
    bottomSheet: Color(0xFF111111),
    textPrimary: Color(0xFFCCCCCC),
    textSecondary: Color(0xFF888888),
    textTertiary: Color(0xFF666666),
    textDisabled: Color(0xFF444444),
    border: Color(0xFF222222),
    divider: Color(0xFF333333),
  );

  static const light = AppColorsTheme(
    background: Color(0xFFF5F5F5),
    surface: Color(0xFFFFFFFF),
    bottomSheet: Color(0xFFEEEEEE),
    textPrimary: Color(0xFF1A1A1A),
    textSecondary: Color(0xFF555555),
    textTertiary: Color(0xFF777777),
    textDisabled: Color(0xFFAAAAAA),
    border: Color(0xFFDDDDDD),
    divider: Color(0xFFE0E0E0),
  );

  @override
  AppColorsTheme copyWith({
    Color? background,
    Color? surface,
    Color? bottomSheet,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textDisabled,
    Color? border,
    Color? divider,
  }) {
    return AppColorsTheme(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      bottomSheet: bottomSheet ?? this.bottomSheet,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textDisabled: textDisabled ?? this.textDisabled,
      border: border ?? this.border,
      divider: divider ?? this.divider,
    );
  }

  @override
  AppColorsTheme lerp(ThemeExtension<AppColorsTheme>? other, double t) {
    if (other is! AppColorsTheme) return this;
    return AppColorsTheme(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      bottomSheet: Color.lerp(bottomSheet, other.bottomSheet, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
    );
  }
}

extension AppColorsThemeX on BuildContext {
  AppColorsTheme get appColors =>
      Theme.of(this).extension<AppColorsTheme>() ?? AppColorsTheme.dark;
}
