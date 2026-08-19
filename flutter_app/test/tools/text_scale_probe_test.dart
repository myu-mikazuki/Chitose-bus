@Tags(['probe'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';
import 'package:kagi_bus/domain/entities/stop_selection.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_result.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_viewmodel.dart';
import 'package:kagi_bus/presentation/viewmodels/stop_selection_viewmodel.dart';
import 'package:kagi_bus/presentation/views/home_screen.dart';
import 'package:kagi_bus/presentation/views/widgets/schedule_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_view_models.dart';
import '../helpers/test_theme.dart';

/// `text_scaler_test.dart` の表を測り直すための道具（#237 / #246）。
///
/// **主張を持たない。**どの倍率で何が溢れるかを標準出力に並べるだけで、
/// 何も assert しない。表の値は人が読み取って書き写す。
///
/// ## 走らせ方
///
/// ```
/// flutter test test/tools/text_scale_probe_test.dart \
///   --dart-define=JP_FONT=/path/to/font.ttf
/// ```
///
/// **`JP_FONT` を渡さないと丸ごと skip する。**CI では走らない
/// （代替フォントの列だけなら `text_scaler_test.dart` で足りる）。
///
/// TTF の作り方と、なぜ実フォントで測り直す必要があるかは
/// `doc/text-scale-measurement.md`。**TTC は `FontLoader` が受け付けない**ので
/// 単体 TTF に切り出すこと。
const _fontPath = String.fromEnvironment('JP_FONT');

/// 測る倍率。Android は「大」= 1.15 /「最大」= 1.3
const _scales = [1.0, 1.15, 1.3, 1.4, 1.5, 2.0];

/// 実機並びの高さ。縦の溢れ（#240）はこの高さでしか出ない
const _deviceHeight = 667.0;

/// 縦を外して横だけ見たいときの高さ
const _tallHeight = 2400.0;

BusTimetable _timetable(String validFrom, String validTo) => BusTimetable(
      validFrom: validFrom,
      validTo: validTo,
      schedules: const [
        BusEntry(
          time: '09:00',
          boardingStopId: 'koizumi',
          destination: '科技大',
          arrivals: {
            'arcadia': '09:05',
            'hoyukai': '09:12',
            'honbuto': '09:30'
          },
        ),
        BusEntry(
          time: '09:40',
          boardingStopId: 'chitose',
          destination: '科技大',
          arrivals: {
            'arcadia': '09:45',
            'hoyukai': '09:52',
            'honbuto': '09:58'
          },
        ),
      ],
    );

final _result = ScheduleResult(
  data: ScheduleResponse(
    stopMaster: kLongStopMaster,
    updatedAt: '2024-01-01',
    current: _timetable('2024-01-01', '2024-12-31'),
    upcoming: _timetable('2025-01-01', '2025-12-31'),
  ),
);

/// `fontFamily` は **theme と `DefaultTextStyle` の両方**に指定する。
/// 片方だけだと素の `TextStyle` を持つ `Text` に効かない
Widget _wrap(List<String> stopIds, double scale) {
  final base = buildTestTheme();
  return ProviderScope(
    overrides: [
      scheduleViewModelProvider
          .overrideWith(() => FakeScheduleViewModel(_result)),
      stopSelectionProvider.overrideWith(
        () => FakeStopSelectionNotifier(StopSelection(stopIds: stopIds)),
      ),
      countdownOverride(now: DateTime(2024, 6, 17, 8, 0)),
    ],
    child: MaterialApp(
      theme: base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'JP')),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: DefaultTextStyle(
          style: const TextStyle(fontFamily: 'JP'),
          child: child!,
        ),
      ),
      home: const HomeScreen(),
    ),
  );
}

/// 溢れた `RenderFlex` を creator 付きで1行にまとめる
String _describe(FlutterErrorDetails details) {
  final head = details.exceptionAsString().split('\n').first;
  final info = details.informationCollector?.call().toList() ?? const [];
  for (final node in info) {
    final dump = node.toStringDeep();
    if (!dump.contains('The specific RenderFlex')) continue;
    for (final line in dump.split('\n')) {
      if (line.contains('creator:')) {
        final who = line.trim();
        return '$head\n      ${who.length > 120 ? who.substring(0, 120) : who}';
      }
    }
  }
  return head;
}

Future<void> _probe(
  WidgetTester tester,
  double scale, {
  required List<String> stopIds,
  required double height,
  required String label,
}) async {
  tester.view.physicalSize = Size(375 * 2, height * 2);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final found = <String>{};
  final previous = FlutterError.onError;
  FlutterError.onError = (details) => found.add(_describe(details));

  var header = '(見出しが見つからない)';
  try {
    await tester.pumpWidget(_wrap(stopIds, scale));
    await tester.pumpAndSettle();

    // 節見出しは `Expanded` + ellipsis で**溢れずに切れる**ので、
    // overflow ではなく didExceedMaxLines で見る（#245）
    final headerFinder = find.text('古泉循環器内科クリニック前 発');
    if (headerFinder.evaluate().isNotEmpty) {
      final paragraph = tester.renderObject<RenderParagraph>(headerFinder);
      header = paragraph.didExceedMaxLines ? '切れている' : '収まっている';
    }

    // 到着行は行を開かないと出ない
    final row = find.descendant(
      of: find.byType(ScheduleList),
      matching: find.text('09:00'),
    );
    if (row.evaluate().isNotEmpty) {
      await tester.ensureVisible(row.first);
      await tester.pumpAndSettle();
      await tester.tap(row.first, warnIfMissed: false);
      await tester.pumpAndSettle();
    }
  } catch (error) {
    found.add('throw: $error');
  } finally {
    FlutterError.onError = previous;
  }

  // ignore: avoid_print
  print('==== $label / 倍率 $scale ── 節見出し: $header');
  if (found.isEmpty) {
    // ignore: avoid_print
    print('     overflow なし');
  }
  for (final line in found) {
    // ignore: avoid_print
    print('     $line');
  }
}

void main() {
  if (_fontPath.isEmpty) {
    test('JP_FONT が無いので skip', () {}, skip: '''
実フォントでの計測用。--dart-define=JP_FONT=/path/to/font.ttf を渡すと走る。
手順は doc/text-scale-measurement.md''');
    return;
  }

  setUpAll(() async {
    final bytes = File(_fontPath).readAsBytesSync();
    await (FontLoader('JP')..addFont(Future.value(ByteData.sublistView(bytes))))
        .load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final scale in _scales) {
    testWidgets('375×$_deviceHeight・1停留所（縦も見る）', (tester) async {
      await _probe(tester, scale,
          stopIds: ['koizumi'], height: _deviceHeight, label: '実機並び');
    });

    testWidgets('375×$_tallHeight・4停留所（タブを見る）', (tester) async {
      await _probe(tester, scale,
          stopIds: ['koizumi', 'arcadia', 'hoyukai', 'osatsu'],
          height: _tallHeight,
          label: '縦に余裕・4タブ');
    });
  }
}
