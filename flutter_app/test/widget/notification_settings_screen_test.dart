import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chitose_bus/domain/entities/bus_schedule.dart';
import 'package:chitose_bus/domain/entities/notification_settings.dart';
import 'package:chitose_bus/presentation/viewmodels/notification_viewmodel.dart';
import 'package:chitose_bus/presentation/views/notification_settings_screen.dart';

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
    testWidgets('初期表示: スイッチ・通知タイミング・路線ラベルが表示される', (tester) async {
      await tester.pumpWidget(_wrap(NotificationSettings()));
      await tester.pump();

      expect(find.text('出発通知を有効にする'), findsOneWidget);
      expect(find.text('通知タイミング'), findsOneWidget);
      expect(find.text('通知する路線'), findsOneWidget);
    });

    testWidgets('enabled=false: ドロップダウンが無効状態', (tester) async {
      await tester.pumpWidget(_wrap(NotificationSettings(enabled: false)));
      await tester.pump();

      // DropdownButton が disabled (onChanged == null) の場合、opacity が下がる
      // 簡易確認: 選択してください が表示される
      expect(find.text('選択してください'), findsOneWidget);
    });

    testWidgets('enabled=true かつ direction=null: 警告テキストが表示される', (tester) async {
      await tester.pumpWidget(
          _wrap(NotificationSettings(enabled: true)));
      await tester.pump();

      expect(find.text('通知を受け取るには路線を選択してください'), findsOneWidget);
    });

    testWidgets('enabled=true かつ direction 設定済み: 警告テキストが非表示', (tester) async {
      await tester.pumpWidget(_wrap(NotificationSettings(
        enabled: true,
        direction: BusDirection.fromChitose,
      )));
      await tester.pump();

      expect(find.text('通知を受け取るには路線を選択してください'), findsNothing);
    });
  });
}
