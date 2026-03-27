import 'package:flutter/material.dart';

/// アプリ全体で使用するカラー定数
class AppColors {
  AppColors._();

  // ブランドカラー
  static const Color primary = Color(0xFF00FF88);
  static const Color onPrimary = Color(0xFF0A0A0A);

  // 背景・サーフェス
  static const Color background = Color(0xFF0A0A0A);
  static const Color surface = Color(0xFF1A1A1A);
  static const Color bottomSheet = Color(0xFF111111);

  // テキスト（明→暗の順）
  static const Color textPrimary = Color(0xFFCCCCCC);
  static const Color textSecondary = Color(0xFF888888);
  static const Color textTertiary = Color(0xFF666666);
  static const Color textDisabled = Color(0xFF444444);

  // セマンティックカラー
  static const Color error = Color(0xFFFF4444);
  static const Color warning = Color(0xFFFFB000);
  static const Color warningBackground = Color(0x26FFB000);

  // ボーダー・仕切り
  static const Color border = Color(0xFF222222);
  static const Color divider = Color(0xFF333333);
}
