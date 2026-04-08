import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/core/theme/app_colors.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';
import 'package:kagi_bus/domain/entities/notification_settings.dart';
import 'package:kagi_bus/presentation/viewmodels/notification_viewmodel.dart';
import 'package:kagi_bus/presentation/views/widgets/schedule_list.dart';

import 'package:kagi_bus/domain/entities/display_settings.dart';
import 'package:kagi_bus/presentation/viewmodels/display_settings_viewmodel.dart';

import '../helpers/test_theme.dart';

// 未来の出発時刻を返す（kTestNow=09:00 の 5分後 = 09:05）
String get _futureDeparture => safeFutureHhmm(5);

class _FakeDisplaySettingsNotifier extends DisplaySettingsNotifier {
  _FakeDisplaySettingsNotifier(this._settings);
  final DisplaySettings _settings;

  @override
  Future<DisplaySettings> build() async => _settings;
}

Widget _wrapWithDisplay(Widget child, DisplaySettings settings) => ProviderScope(
      overrides: [
        countdownOverride(),
        displaySettingsProvider.overrideWith(
          () => _FakeDisplaySettingsNotifier(settings),
        ),
      ],
      child: MaterialApp(theme: buildTestTheme(), home: Scaffold(body: child)),
    );

Widget _wrap(Widget child) => ProviderScope(
      overrides: [countdownOverride()],
      child: MaterialApp(theme: buildTestTheme(), home: Scaffold(body: child)),
    );

Widget _wrapWithNotification(Widget child, NotificationSettings settings) =>
    ProviderScope(
      overrides: [
        countdownOverride(),
        notificationSettingsProvider.overrideWith(
          () => _FakeNotificationSettingsNotifier(settings),
        ),
      ],
      child: MaterialApp(theme: buildTestTheme(), home: Scaffold(body: child)),
    );

class _FakeNotificationSettingsNotifier extends NotificationSettingsNotifier {
  _FakeNotificationSettingsNotifier(this._settings);
  final NotificationSettings _settings;

  @override
  Future<NotificationSettings> build() async => _settings;
}

class _TrackingNotificationSettingsNotifier
    extends NotificationSettingsNotifier {
  _TrackingNotificationSettingsNotifier(this._settings, {required this.onSave});
  final NotificationSettings _settings;
  final void Function(NotificationSettings) onSave;

  @override
  Future<NotificationSettings> build() async => _settings;

  @override
  Future<void> toggleBusNotification(bus) async {
    final current = state.value!;
    final key = NotificationSettingsNotifier.busKey(bus);
    final newKeys = {...current.scheduledBusKeys, key};
    final updated = current.copyWith(scheduledBusKeys: newKeys);
    state = AsyncData(updated);
    onSave(updated);
  }
}

void main() {
  group('ScheduleList', () {
    testWidgets('バスリストが空の場合: 「時刻表データなし」が表示される', (tester) async {
      final timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        schedules: const [],
      );

      await tester.pumpWidget(
        _wrap(ScheduleList(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      expect(find.text('時刻表データなし'), findsOneWidget);
    });

    testWidgets('バスリストに複数エントリ: 時刻・行き先が表示される', (tester) async {
      final t1 = safeFutureHhmm(60);
      final t2 = safeFutureHhmm(120);
      final timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        schedules: [
          BusEntry(
              time: t1,
              direction: BusDirection.fromChitose,
              destination: '千歳科技大'),
          BusEntry(
              time: t2,
              direction: BusDirection.fromChitose,
              destination: '千歳科技大'),
        ],
      );

      await tester.pumpWidget(
        _wrap(ScheduleList(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      // When t1 == t2 (both capped at 23:58 near midnight), two widgets share
      // the same text, so use findsNWidgets(2). Otherwise each appears once.
      if (t1 == t2) {
        expect(find.text(t1), findsNWidgets(2));
      } else {
        expect(find.text(t1), findsOneWidget);
        expect(find.text(t2), findsOneWidget);
      }
      expect(find.text('千歳科技大'), findsNWidgets(2));
    });

    testWidgets('isNext=trueのバス: 背景色がAppColors.secondary・「◀ NEXT」が表示される',
        (tester) async {
      final nextTime = safeFutureHhmm(60);
      final timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        schedules: [
          BusEntry(
              time: nextTime,
              direction: BusDirection.fromChitose,
              destination: '千歳科技大'),
        ],
      );

      await tester.pumpWidget(
        _wrap(ScheduleList(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      expect(find.text('◀ NEXT'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Container && w.color == AppColors.secondary,
        ),
        findsWidgets,
      );
    });

    testWidgets('isPast=trueのバス: テキスト色がColor(0xFF444444)', (tester) async {
      // '00:01' is in the past for nearly the entire day (except the first minute).
      const pastTime = '00:01';
      final timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        schedules: [
          BusEntry(
              time: pastTime,
              direction: BusDirection.fromChitose,
              destination: '千歳科技大'),
        ],
      );

      await tester.pumpWidget(
        _wrap(ScheduleList(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      final timeText = tester.widget<Text>(find.text(pastTime));
      expect(timeText.style?.color, const Color(0xFF444444));
    });

    testWidgets('通常未来バス（isPast=false, isNext=false）: テキスト色がColor(0xFFCCCCCC)',
        (tester) async {
      // Two future buses: t1 is the "next" bus, t2 is a normal future bus.
      // nextBus() returns the first future entry, so t1 is NEXT and t2 is normal future.
      final t1 = safeFutureHhmm(60);
      final t2 = safeFutureHhmm(120);
      final timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        schedules: [
          BusEntry(
              time: t1,
              direction: BusDirection.fromChitose,
              destination: '千歳科技大'),
          BusEntry(
              time: t2,
              direction: BusDirection.fromChitose,
              destination: '千歳科技大'),
        ],
      );

      await tester.pumpWidget(
        _wrap(ScheduleList(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      // t2 is neither next nor past → textColor should be 0xFFCCCCCC.
      // Find the Text widget showing t2; there may be two Text widgets with the
      // same time string if t1 == t2 (capped at 23:58), so guard with findsWidgets.
      if (t1 != t2) {
        final timeText = tester.widget<Text>(find.text(t2));
        expect(timeText.style?.color, const Color(0xFFCCCCCC));
      }
      // If t1 == t2 (midnight cap), both are treated as the same entry; skip color check.
    });

    testWidgets('arrivalsがある行をタップ: 到着停留所・時刻が展開表示される', (tester) async {
      final busTime = safeFutureHhmm(60);
      final arrivalTime = safeFutureHhmm(80);
      final timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        schedules: [
          BusEntry(
            time: busTime,
            direction: BusDirection.fromChitose,
            destination: '千歳科技大',
            arrivals: {'kenkyuto': arrivalTime},
          ),
        ],
      );

      await tester.pumpWidget(
        _wrap(ScheduleList(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      // タップ前は到着情報が非表示
      expect(find.text('研究棟 着'), findsNothing);

      await tester.tap(find.text(busTime));
      await tester.pump();

      // タップ後は到着情報が表示
      expect(find.text('研究棟 着'), findsOneWidget);
      expect(find.text(arrivalTime), findsAtLeastNWidgets(1));
    });

    testWidgets('arrivalsがある行を2回タップ: 到着情報がトグル非表示になる', (tester) async {
      final busTime = safeFutureHhmm(60);
      final arrivalTime = safeFutureHhmm(80);
      final timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        schedules: [
          BusEntry(
            time: busTime,
            direction: BusDirection.fromChitose,
            destination: '千歳科技大',
            arrivals: {'kenkyuto': arrivalTime},
          ),
        ],
      );

      await tester.pumpWidget(
        _wrap(ScheduleList(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      // 1回目タップ → 展開
      await tester.tap(find.text(busTime));
      await tester.pump();
      expect(find.text('研究棟 着'), findsOneWidget);

      // 2回目タップ → 折りたたみ
      await tester.tap(find.text(busTime));
      await tester.pump();
      expect(find.text('研究棟 着'), findsNothing);
    });

    group('ベルアイコン', () {
      testWidgets('enabled=true かつ未来便・未選択: 斜線ありベルが表示される', (tester) async {
        final busTime = safeFutureHhmm(60);
        final timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-12-31',
          schedules: [
            BusEntry(
                time: busTime,
                direction: BusDirection.fromChitose,
                destination: '千歳科技大'),
          ],
        );
        await tester.pumpWidget(_wrapWithNotification(
          ScheduleList(timetable: timetable, direction: BusDirection.fromChitose),
          NotificationSettings(enabled: true),
        ));
        await tester.pump();

        expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
      });

      testWidgets('enabled=false: ベルアイコンが非表示', (tester) async {
        final busTime = safeFutureHhmm(60);
        final timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-12-31',
          schedules: [
            BusEntry(
                time: busTime,
                direction: BusDirection.fromChitose,
                destination: '千歳科技大'),
          ],
        );
        await tester.pumpWidget(_wrapWithNotification(
          ScheduleList(timetable: timetable, direction: BusDirection.fromChitose),
          NotificationSettings(enabled: false),
        ));
        await tester.pump();

        expect(find.byIcon(Icons.notifications_off_outlined), findsNothing);
        expect(find.byIcon(Icons.notifications), findsNothing);
      });

      testWidgets('過去便: ベルアイコンが非表示', (tester) async {
        const pastTime = '00:01';
        final timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-12-31',
          schedules: [
            BusEntry(
                time: pastTime,
                direction: BusDirection.fromChitose,
                destination: '千歳科技大'),
          ],
        );
        await tester.pumpWidget(_wrapWithNotification(
          ScheduleList(timetable: timetable, direction: BusDirection.fromChitose),
          NotificationSettings(enabled: true),
        ));
        await tester.pump();

        expect(find.byIcon(Icons.notifications_off_outlined), findsNothing);
        expect(find.byIcon(Icons.notifications), findsNothing);
      });

      testWidgets('選択済み便: 斜線なしベル(0xFF888888)が表示される', (tester) async {
        final busTime = safeFutureHhmm(60);
        final bus = BusEntry(
            time: busTime,
            direction: BusDirection.fromChitose,
            destination: '千歳科技大');
        final key = NotificationSettingsNotifier.busKey(bus);
        final timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-12-31',
          schedules: [bus],
        );
        await tester.pumpWidget(_wrapWithNotification(
          ScheduleList(timetable: timetable, direction: BusDirection.fromChitose),
          NotificationSettings(enabled: true, scheduledBusKeys: {key}),
        ));
        await tester.pump();

        final icon = tester.widget<Icon>(find.byIcon(Icons.notifications));
        expect(icon.color, const Color(0xFF888888));
      });

      testWidgets('未選択便: 斜線ありベル(0xFF888888)が表示される', (tester) async {
        final busTime = safeFutureHhmm(60);
        final timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-12-31',
          schedules: [
            BusEntry(
                time: busTime,
                direction: BusDirection.fromChitose,
                destination: '千歳科技大'),
          ],
        );
        await tester.pumpWidget(_wrapWithNotification(
          ScheduleList(timetable: timetable, direction: BusDirection.fromChitose),
          NotificationSettings(enabled: true),
        ));
        await tester.pump();

        final icon = tester.widget<Icon>(find.byIcon(Icons.notifications_off_outlined));
        expect(icon.color, const Color(0xFF888888));
      });

      testWidgets('ベルアイコンをタップ: scheduledBusKeys にキーが追加される', (tester) async {
        final busTime = safeFutureHhmm(60);
        final bus = BusEntry(
            time: busTime,
            direction: BusDirection.fromChitose,
            destination: '千歳科技大');
        final timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-12-31',
          schedules: [bus],
        );
        late NotificationSettings capturedSettings;
        final notifier = _TrackingNotificationSettingsNotifier(
          NotificationSettings(enabled: true),
          onSave: (s) => capturedSettings = s,
        );
        await tester.pumpWidget(ProviderScope(
          overrides: [
            countdownOverride(),
            notificationSettingsProvider.overrideWith(() => notifier),
          ],
          child: MaterialApp(
            theme: buildTestTheme(),
            home: Scaffold(
              body: ScheduleList(
                  timetable: timetable, direction: BusDirection.fromChitose),
            ),
          ),
        ));
        await tester.pump();

        await tester.tap(find.byIcon(Icons.notifications_off_outlined));
        await tester.pump();

        expect(
          capturedSettings.scheduledBusKeys,
          contains(NotificationSettingsNotifier.busKey(bus)),
        );
      });
    });

    testWidgets('arrivalsが空の行をタップ: 何も表示されない', (tester) async {
      final busTime = safeFutureHhmm(60);
      final timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        schedules: [
          BusEntry(
            time: busTime,
            direction: BusDirection.fromChitose,
            destination: '千歳科技大',
          ),
        ],
      );

      await tester.pumpWidget(
        _wrap(ScheduleList(
            timetable: timetable, direction: BusDirection.fromChitose)),
      );

      await tester.tap(find.text(busTime));
      await tester.pump();

      expect(find.text('研究棟 着'), findsNothing);
    });

    group('講時タグ', () {
      testWidgets('arrivals[honbuto]=08:59 → "1講" タグが表示される', (tester) async {
        final timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-03-31',
          schedules: [
            BusEntry(
              time: _futureDeparture,
              direction: BusDirection.fromChitose,
              destination: '千歳科技大',
              arrivals: const {'honbuto': '08:59'},
            ),
          ],
        );
        await tester.pumpWidget(
          _wrap(ScheduleList(
              timetable: timetable, direction: BusDirection.fromChitose)),
        );
        expect(find.text('1講'), findsOneWidget);
      });

      testWidgets('arrivals[honbuto]=09:00 → "2講" タグが表示される（境界値）', (tester) async {
        final timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-03-31',
          schedules: [
            BusEntry(
              time: _futureDeparture,
              direction: BusDirection.fromChitose,
              destination: '千歳科技大',
              arrivals: const {'honbuto': '09:00'},
            ),
          ],
        );
        await tester.pumpWidget(
          _wrap(ScheduleList(
              timetable: timetable, direction: BusDirection.fromChitose)),
        );
        expect(find.text('2講'), findsOneWidget);
      });

      testWidgets('arrivals[honbuto]=16:45 → "放課後" タグが表示される', (tester) async {
        final timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-03-31',
          schedules: [
            BusEntry(
              time: _futureDeparture,
              direction: BusDirection.fromChitose,
              destination: '千歳科技大',
              arrivals: const {'honbuto': '16:45'},
            ),
          ],
        );
        await tester.pumpWidget(
          _wrap(ScheduleList(
              timetable: timetable, direction: BusDirection.fromChitose)),
        );
        expect(find.text('放課後'), findsOneWidget);
      });

      testWidgets('arrivals に honbuto がない方向 → タグが表示されない', (tester) async {
        final timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-03-31',
          schedules: [
            BusEntry(
              time: _futureDeparture,
              direction: BusDirection.fromKenkyutoToStation,
              destination: '千歳駅',
              arrivals: const {'chitose': '09:30'},
            ),
          ],
        );
        await tester.pumpWidget(
          _wrap(ScheduleList(
              timetable: timetable,
              direction: BusDirection.fromKenkyutoToStation)),
        );
        for (final label in ['1講', '2講', '昼休み', '3講', '4講', '5講', '放課後']) {
          expect(find.text(label), findsNothing);
        }
      });

      testWidgets('arrivals が空 → タグが表示されない', (tester) async {
        final timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-03-31',
          schedules: [
            BusEntry(
              time: _futureDeparture,
              direction: BusDirection.fromChitose,
              destination: '千歳科技大',
            ),
          ],
        );
        await tester.pumpWidget(
          _wrap(ScheduleList(
              timetable: timetable, direction: BusDirection.fromChitose)),
        );
        for (final label in ['1講', '2講', '昼休み', '3講', '4講', '5講', '放課後']) {
          expect(find.text(label), findsNothing);
        }
      });

      testWidgets('showLectureTags=false → タグが表示されない', (tester) async {
        final timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-03-31',
          schedules: [
            BusEntry(
              time: _futureDeparture,
              direction: BusDirection.fromChitose,
              destination: '千歳科技大',
              arrivals: const {'honbuto': '10:00'},
            ),
          ],
        );
        await tester.pumpWidget(
          _wrapWithDisplay(
            ScheduleList(
                timetable: timetable, direction: BusDirection.fromChitose),
            const DisplaySettings(showLectureTags: false),
          ),
        );
        await tester.pump();
        for (final label in ['1講', '2講', '昼休み', '3講', '4講', '5講', '放課後']) {
          expect(find.text(label), findsNothing);
        }
      });

      testWidgets('isNext=true の行でも講時タグが表示される', (tester) async {
        final timetable = BusTimetable(
          validFrom: '2024-01-01',
          validTo: '2024-03-31',
          schedules: [
            BusEntry(
              time: _futureDeparture,
              direction: BusDirection.fromChitose,
              destination: '千歳科技大',
              arrivals: const {'honbuto': '10:00'},
            ),
          ],
        );
        await tester.pumpWidget(
          _wrap(ScheduleList(
              timetable: timetable, direction: BusDirection.fromChitose)),
        );
        // NEXT行であることを確認
        expect(find.text('◀ NEXT'), findsOneWidget);
        // 講時タグも表示されている
        expect(find.text('2講'), findsOneWidget);
      });
    });

    testWidgets('NEXTバスが画面外にあっても初期表示でスクロールされて見える', (tester) async {
      // kTestNow = 09:00。過去便を18件並べてNEXTを画面外に追いやる
      final pastTimes = List.generate(
        18,
        (i) => '0${i ~/ 6 + 1}:${(i % 6 * 10).toString().padLeft(2, '0')}',
      );
      final nextTime = safeFutureHhmm(60); // 10:00

      final timetable = BusTimetable(
        validFrom: '2024-01-01',
        validTo: '2024-03-31',
        schedules: [
          ...pastTimes.map((t) => BusEntry(
                time: t,
                direction: BusDirection.fromChitose,
                destination: '科技大',
              )),
          BusEntry(
            time: nextTime,
            direction: BusDirection.fromChitose,
            destination: '科技大',
          ),
        ],
      );

      // 高さ制限を設けて NEXT を画面外にする（ListView.builder では描画されない高さ）
      await tester.pumpWidget(
        ProviderScope(
          overrides: [countdownOverride()],
          child: MaterialApp(
            theme: buildTestTheme(),
            home: Scaffold(
              body: SizedBox(
                height: 200,
                child: ScheduleList(
                    timetable: timetable,
                    direction: BusDirection.fromChitose),
              ),
            ),
          ),
        ),
      );
      await tester.pump(); // postFrameCallback を発火させる

      // NEXT バスが画面内に表示されている（スクロールされた）
      expect(find.text(nextTime), findsOneWidget);
      expect(find.text('◀ NEXT'), findsOneWidget);
    });
  });
}
