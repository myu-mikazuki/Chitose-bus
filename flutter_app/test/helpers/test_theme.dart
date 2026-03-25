import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_viewmodel.dart';

/// テスト用共通テーマ
ThemeData buildTestTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF00FF88),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0A0A0A),
      fontFamily: 'monospace',
    );

/// テスト用固定時刻 (2024-01-01 09:00)
final kTestNow = DateTime(2024, 1, 1, 9, 0);

/// countdownProviderを固定時刻にオーバーライドするOverride
Override countdownOverride({DateTime? now}) => countdownProvider.overrideWith(
      (ref) => CountdownNotifier(ref)..state = now ?? kTestNow,
    );

/// [now] から [minutesAhead] 分後のHH:MM文字列を返す（日付跨ぎを23:58にキャップ）
/// [now] を省略すると kTestNow を使用する（countdownOverride と整合させるため）
String safeFutureHhmm(int minutesAhead, {DateTime? now}) {
  final base = now ?? kTestNow;
  final totalMins = base.hour * 60 + base.minute + minutesAhead;
  final capped = totalMins < 24 * 60 ? totalMins : 23 * 60 + 58;
  return '${(capped ~/ 60).toString().padLeft(2, '0')}:${(capped % 60).toString().padLeft(2, '0')}';
}
