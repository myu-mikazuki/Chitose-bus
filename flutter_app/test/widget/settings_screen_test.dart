import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/domain/entities/display_settings.dart';
import 'package:kagi_bus/domain/entities/notification_settings.dart';
import 'package:kagi_bus/presentation/viewmodels/display_settings_viewmodel.dart';
import 'package:kagi_bus/presentation/viewmodels/notification_viewmodel.dart';
import 'package:kagi_bus/presentation/views/settings_screen.dart';

import '../helpers/test_theme.dart';

class _FakeNotificationSettingsNotifier extends NotificationSettingsNotifier {
  _FakeNotificationSettingsNotifier(this._initial);
  final NotificationSettings _initial;

  @override
  Future<NotificationSettings> build() async => _initial;
}

class _FakeDisplaySettingsNotifier extends DisplaySettingsNotifier {
  _FakeDisplaySettingsNotifier(this._initial);
  final DisplaySettings _initial;
  DisplaySettings? saved;

  @override
  Future<DisplaySettings> build() async => _initial;

  @override
  Future<void> saveSettings(DisplaySettings settings) async {
    saved = settings;
    state = AsyncData(settings);
  }
}

Widget _wrap({
  NotificationSettings? notification,
  DisplaySettings? display,
}) {
  final notifNotifier =
      _FakeNotificationSettingsNotifier(notification ?? NotificationSettings());
  final displayNotifier =
      _FakeDisplaySettingsNotifier(display ?? const DisplaySettings());

  return ProviderScope(
    overrides: [
      notificationSettingsProvider.overrideWith(() => notifNotifier),
      displaySettingsProvider.overrideWith(() => displayNotifier),
    ],
    child: MaterialApp(
      theme: buildTestTheme(),
      home: const SettingsScreen(),
    ),
  );
}

void main() {
  group('SettingsScreen 表示設定', () {
    testWidgets('「講時タグを表示」スイッチが表示される', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(find.text('講時タグを表示'), findsOneWidget);
    });

    testWidgets('showLectureTags=true: スイッチがON状態', (tester) async {
      await tester.pumpWidget(
          _wrap(display: const DisplaySettings(showLectureTags: true)));
      await tester.pump();

      final sw = tester.widget<Switch>(
        find.byWidgetPredicate(
          (w) => w is Switch,
          description: 'Switch for lecture tags',
        ).last,
      );
      expect(sw.value, isTrue);
    });

    testWidgets('showLectureTags=false: スイッチがOFF状態', (tester) async {
      await tester.pumpWidget(
          _wrap(display: const DisplaySettings(showLectureTags: false)));
      await tester.pump();

      final sw = tester.widget<Switch>(
        find.byWidgetPredicate(
          (w) => w is Switch,
          description: 'Switch for lecture tags',
        ).last,
      );
      expect(sw.value, isFalse);
    });

    testWidgets('スイッチをタップ → saveSettings が呼ばれ state が更新される',
        (tester) async {
      final displayNotifier =
          _FakeDisplaySettingsNotifier(const DisplaySettings(showLectureTags: true));

      await tester.pumpWidget(ProviderScope(
        overrides: [
          notificationSettingsProvider.overrideWith(
            () => _FakeNotificationSettingsNotifier(NotificationSettings()),
          ),
          displaySettingsProvider.overrideWith(() => displayNotifier),
        ],
        child: MaterialApp(
          theme: buildTestTheme(),
          home: const SettingsScreen(),
        ),
      ));
      await tester.pump();

      await tester.tap(find.byWidgetPredicate((w) => w is Switch).last);
      await tester.pump();

      expect(displayNotifier.saved?.showLectureTags, isFalse);
    });
  });
}
