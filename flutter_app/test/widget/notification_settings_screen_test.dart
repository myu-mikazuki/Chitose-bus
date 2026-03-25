import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/domain/entities/notification_settings.dart';
import 'package:kagi_bus/presentation/viewmodels/notification_viewmodel.dart';
import 'package:kagi_bus/presentation/views/notification_settings_screen.dart';

// 固定値を返す Fake (NotificationSettingsNotifier を継承して型を合わせる)
class _FakeNotificationSettingsNotifier extends NotificationSettingsNotifier {
  _FakeNotificationSettingsNotifier(this._initial);
  final NotificationSettings _initial;

  @override
  Future<NotificationSettings> build() async => _initial;

  @override
  Future<void> saveSettings(NotificationSettings settings) async {
    state = AsyncData(settings);
  }
}

Widget _wrap(NotificationSettings settings) => ProviderScope(
      overrides: [
        notificationSettingsProvider.overrideWith(
          () => _FakeNotificationSettingsNotifier(settings),
        ),
      ],
      child: const MaterialApp(home: NotificationSettingsScreen()),
    );

void main() {
  group('NotificationSettingsScreen', () {
    testWidgets('初期表示: スイッチ・通知タイミングが表示される', (tester) async {
      await tester.pumpWidget(_wrap(NotificationSettings()));
      await tester.pump();

      expect(find.text('出発通知を有効にする'), findsOneWidget);
      expect(find.text('通知タイミング'), findsOneWidget);
    });

    testWidgets('路線選択UIが非表示', (tester) async {
      await tester.pumpWidget(_wrap(NotificationSettings()));
      await tester.pump();

      expect(find.text('通知する路線'), findsNothing);
      expect(find.text('選択してください'), findsNothing);
      expect(find.text('通知を受け取るには路線を選択してください'), findsNothing);
    });

    testWidgets('enabled=false: minutesBefore ドロップダウンが無効状態', (tester) async {
      await tester.pumpWidget(_wrap(NotificationSettings(enabled: false)));
      await tester.pump();

      // enabled=false のとき minutesBefore DropdownButton は disabled
      final dropdown = tester.widget<DropdownButton<int>>(
        find.byType(DropdownButton<int>),
      );
      expect(dropdown.onChanged, isNull);
    });
  });
}
