import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/core/theme/app_colors_theme.dart';
import 'package:kagi_bus/core/theme/app_theme.dart';

void main() {
  group('AppColorsTheme.dark', () {
    test('background は 0xFF1F1F1F', () {
      expect(AppColorsTheme.dark.background, const Color(0xFF1F1F1F));
    });
    test('surface は 0xFF2A2A2A', () {
      expect(AppColorsTheme.dark.surface, const Color(0xFF2A2A2A));
    });
    test('bottomSheet は 0xFF111111', () {
      expect(AppColorsTheme.dark.bottomSheet, const Color(0xFF111111));
    });
    test('textPrimary は 0xFFCCCCCC', () {
      expect(AppColorsTheme.dark.textPrimary, const Color(0xFFCCCCCC));
    });
    test('textSecondary は 0xFF888888', () {
      expect(AppColorsTheme.dark.textSecondary, const Color(0xFF888888));
    });
    test('textTertiary は 0xFF666666', () {
      expect(AppColorsTheme.dark.textTertiary, const Color(0xFF666666));
    });
    test('textDisabled は 0xFF444444', () {
      expect(AppColorsTheme.dark.textDisabled, const Color(0xFF444444));
    });
    test('border は 0xFF222222', () {
      expect(AppColorsTheme.dark.border, const Color(0xFF222222));
    });
    test('divider は 0xFF333333', () {
      expect(AppColorsTheme.dark.divider, const Color(0xFF333333));
    });
  });

  group('AppColorsTheme.light', () {
    test('background は 0xFFF5F5F5', () {
      expect(AppColorsTheme.light.background, const Color(0xFFF5F5F5));
    });
    test('surface は 0xFFFFFFFF', () {
      expect(AppColorsTheme.light.surface, const Color(0xFFFFFFFF));
    });
    test('bottomSheet は 0xFFEEEEEE', () {
      expect(AppColorsTheme.light.bottomSheet, const Color(0xFFEEEEEE));
    });
    test('textPrimary は 0xFF1A1A1A', () {
      expect(AppColorsTheme.light.textPrimary, const Color(0xFF1A1A1A));
    });
    test('textSecondary は 0xFF555555', () {
      expect(AppColorsTheme.light.textSecondary, const Color(0xFF555555));
    });
    test('textTertiary は 0xFF777777', () {
      expect(AppColorsTheme.light.textTertiary, const Color(0xFF777777));
    });
    test('textDisabled は 0xFFAAAAAA', () {
      expect(AppColorsTheme.light.textDisabled, const Color(0xFFAAAAAA));
    });
    test('border は 0xFFDDDDDD', () {
      expect(AppColorsTheme.light.border, const Color(0xFFDDDDDD));
    });
    test('divider は 0xFFE0E0E0', () {
      expect(AppColorsTheme.light.divider, const Color(0xFFE0E0E0));
    });
  });

  group('AppColorsTheme.copyWith', () {
    test('指定フィールドだけ変わり他は元の値を保つ', () {
      final modified = AppColorsTheme.dark.copyWith(
        background: const Color(0xFFABCDEF),
      );
      expect(modified.background, const Color(0xFFABCDEF));
      expect(modified.surface, AppColorsTheme.dark.surface);
    });
  });

  group('AppColorsTheme.lerp', () {
    test('t=0 で dark の値を返す', () {
      final result = AppColorsTheme.dark.lerp(AppColorsTheme.light, 0);
      expect(result.background, AppColorsTheme.dark.background);
    });
    test('t=1 で light の値を返す', () {
      final result = AppColorsTheme.dark.lerp(AppColorsTheme.light, 1);
      expect(result.background, AppColorsTheme.light.background);
    });
  });

  group('AppTheme', () {
    test('light() の brightness は Brightness.light', () {
      expect(AppTheme.light().brightness, Brightness.light);
    });

    test('light() に AppColorsTheme extension が含まれる', () {
      expect(AppTheme.light().extension<AppColorsTheme>(), isNotNull);
    });

    test('dark() に AppColorsTheme extension が含まれる', () {
      expect(AppTheme.dark().extension<AppColorsTheme>(), isNotNull);
    });

    test('light() の scaffoldBackgroundColor は AppColorsTheme.light.background', () {
      expect(
        AppTheme.light().scaffoldBackgroundColor,
        AppColorsTheme.light.background,
      );
    });

    test('dark() の scaffoldBackgroundColor は AppColorsTheme.dark.background', () {
      expect(
        AppTheme.dark().scaffoldBackgroundColor,
        AppColorsTheme.dark.background,
      );
    });
  });

  group('BuildContext.appColors', () {
    testWidgets('light テーマの context.appColors は light の background を返す',
        (tester) async {
      late AppColorsTheme captured;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.light,
        home: Builder(builder: (ctx) {
          captured = ctx.appColors;
          return const SizedBox();
        }),
      ));
      expect(captured.background, AppColorsTheme.light.background);
    });

    testWidgets('dark テーマの context.appColors は dark の background を返す',
        (tester) async {
      late AppColorsTheme captured;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: Builder(builder: (ctx) {
          captured = ctx.appColors;
          return const SizedBox();
        }),
      ));
      expect(captured.background, AppColorsTheme.dark.background);
    });
  });
}
