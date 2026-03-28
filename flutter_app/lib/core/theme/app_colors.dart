import 'package:flutter/material.dart';

/// アプリ全体で使用するカラー定数（テーマ非依存のブランド・セマンティックカラーのみ）。
/// テーマで変わる色は [AppColorsTheme] を参照。
class AppColors {
  AppColors._();

  // ブランドカラー
  static const Color primary = Color(0xFFFE9616);
  static const Color secondary = Color(0xFFFDA02E);
  static const Color onPrimary = Color(0xFF0A0A0A);

  // セマンティックカラー
  static const Color error = Color(0xFFFF4444);
  static const Color warning = Color(0xFFFFB000);
  static const Color warningBackground = Color(0x26FFB000);
}
