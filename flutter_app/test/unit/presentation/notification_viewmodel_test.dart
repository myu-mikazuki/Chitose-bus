import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chitose_bus/domain/entities/bus_schedule.dart';
import 'package:chitose_bus/domain/entities/notification_settings.dart';
import 'package:chitose_bus/domain/services/notification_service.dart';
import 'package:chitose_bus/data/repositories/notification_settings_repository.dart';
import 'package:chitose_bus/presentation/viewmodels/notification_viewmodel.dart';
import 'package:chitose_bus/presentation/viewmodels/schedule_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---- Fakes ----

class FakeNotificationService implements NotificationService {
  int cancelAllCount = 0;
  final List<({BusEntry bus, NotificationSettings settings})> scheduledCalls =
      [];
  bool permissionGranted;

  FakeNotificationService({this.permissionGranted = true});

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<void> scheduleNotification(
      BusEntry bus, NotificationSettings settings) async {
    scheduledCalls.add((bus: bus, settings: settings));
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
  }
}

class FakeNotificationSettingsRepository
    implements NotificationSettingsRepository {
  NotificationSettings _stored;

  FakeNotificationSettingsRepository([NotificationSettings? initial])
      : _stored = initial ?? NotificationSettings();

  @override
  Future<NotificationSettings> load() async => _stored;

  @override
  Future<void> save(NotificationSettings settings) async {
    _stored = settings;
  }
}

// ---- テスト用の BusTimetable ヘルパー ----

/// 指定した direction で未来時刻のバスを含む BusTimetable を生成する
BusTimetable futureTimetable(BusDirection direction) {
  final now = DateTime.now();
  final future1 = now.add(const Duration(hours: 1));
  final future2 = now.add(const Duration(hours: 2));
  final future3 = now.add(const Duration(hours: 3));
  final future4 = now.add(const Duration(hours: 4));
  String fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  return BusTimetable(
    validFrom: '2026-01-01',
    validTo: '2026-12-31',
    schedules: [
      BusEntry(time: fmt(future1), direction: direction, destination: '千歳科技大'),
      BusEntry(time: fmt(future2), direction: direction, destination: '千歳科技大'),
      BusEntry(time: fmt(future3), direction: direction, destination: '千歳科技大'),
      BusEntry(time: fmt(future4), direction: direction, destination: '千歳科技大'),
    ],
  );
}

/// 過去時刻のみのバスを含む BusTimetable を生成する
BusTimetable pastTimetable(BusDirection direction) {
  final now = DateTime.now();
  final past1 = now.subtract(const Duration(hours: 2));
  final past2 = now.subtract(const Duration(hours: 1));
  String fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  return BusTimetable(
    validFrom: '2026-01-01',
    validTo: '2026-12-31',
    schedules: [
      BusEntry(time: fmt(past1), direction: direction, destination: '千歳科技大'),
      BusEntry(time: fmt(past2), direction: direction, destination: '千歳科技大'),
    ],
  );
}

/// ProviderContainer に必要なオーバーライドを設定して返す
ProviderContainer makeContainer({
  required FakeNotificationService service,
  NotificationSettings? initialSettings,
  BusTimetable? timetable,
  BusDirection direction = BusDirection.fromChitose,
}) {
  final repo = FakeNotificationSettingsRepository(initialSettings);

  final scheduleOverride = timetable != null
      ? scheduleViewModelProvider.overrideWith(() => _FakeScheduleViewModel(
            ScheduleResponse(
              updatedAt: '2026-01-01',
              current: timetable,
            ),
          ))
      : scheduleViewModelProvider.overrideWith(
          () => _FakeScheduleViewModel(
            ScheduleResponse(
              updatedAt: '2026-01-01',
              current: futureTimetable(direction),
            ),
          ),
        );

  return ProviderContainer(
    overrides: [
      notificationServiceProvider.overrideWithValue(service),
      notificationSettingsRepositoryProvider.overrideWithValue(repo),
      scheduleOverride,
    ],
  );
}

/// テスト用のスタブ ScheduleViewModel
class _FakeScheduleViewModel extends ScheduleViewModel {
  _FakeScheduleViewModel(this._response);
  final ScheduleResponse _response;

  @override
  Future<ScheduleResponse> build() async => _response;
}

/// scheduleViewModelProvider が永遠にロード中のままのスタブ
class _FakeLoadingScheduleViewModel extends ScheduleViewModel {
  @override
  Future<ScheduleResponse> build() => Completer<ScheduleResponse>().future;
}

/// fromChitose と fromHonbuto が混在する BusTimetable
BusTimetable mixedDirectionTimetable() {
  final now = DateTime.now();
  final future1 = now.add(const Duration(hours: 1));
  final future2 = now.add(const Duration(hours: 2));
  String fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  return BusTimetable(
    validFrom: '2026-01-01',
    validTo: '2026-12-31',
    schedules: [
      BusEntry(
          time: fmt(future1),
          direction: BusDirection.fromChitose,
          destination: '千歳科技大'),
      BusEntry(
          time: fmt(future2),
          direction: BusDirection.fromHonbuto,
          destination: '千歳駅'),
    ],
  );
}

// ---- テスト ----

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('NotificationSettingsNotifier', () {
    /// 両プロバイダの初期化を待つヘルパー
    Future<void> awaitProviders(ProviderContainer container) async {
      await container.read(scheduleViewModelProvider.future);
      await container.read(notificationSettingsProvider.future);
    }

    group('saveSettings()', () {
      test('enabled=true かつ direction 設定済みのとき通知が再スケジュールされる', () async {
        final service = FakeNotificationService();
        final container = makeContainer(service: service);
        addTearDown(container.dispose);
        await awaitProviders(container);

        final settings = NotificationSettings(
          enabled: true,
          minutesBefore: 10,
          direction: BusDirection.fromChitose,
        );
        await container
            .read(notificationSettingsProvider.notifier)
            .saveSettings(settings);

        expect(service.cancelAllCount, greaterThanOrEqualTo(1),
            reason: 'cancelAll が呼ばれるべき');
        expect(service.scheduledCalls, isNotEmpty,
            reason: 'scheduleNotification が呼ばれるべき');
      });

      test('enabled=false のとき cancelAll のみ呼ばれ再スケジュールされない', () async {
        final service = FakeNotificationService();
        final container = makeContainer(service: service);
        addTearDown(container.dispose);
        await awaitProviders(container);

        final settings = NotificationSettings(enabled: false);
        await container
            .read(notificationSettingsProvider.notifier)
            .saveSettings(settings);

        expect(service.cancelAllCount, greaterThanOrEqualTo(1),
            reason: 'cancelAll が呼ばれるべき');
        expect(service.scheduledCalls, isEmpty,
            reason: 'scheduleNotification は呼ばれるべきでない');
      });

      test('enabled=true かつ direction=null のとき cancelAll のみ呼ばれる', () async {
        final service = FakeNotificationService();
        final container = makeContainer(service: service);
        addTearDown(container.dispose);
        await awaitProviders(container);

        final settings = NotificationSettings(
          enabled: true,
          minutesBefore: 10,
          // direction: null
        );
        await container
            .read(notificationSettingsProvider.notifier)
            .saveSettings(settings);

        expect(service.cancelAllCount, greaterThanOrEqualTo(1));
        expect(service.scheduledCalls, isEmpty,
            reason: '方面未設定では通知スケジュール不可');
      });

      test('minutesBefore を変更したとき新しい値で再スケジュールされる', () async {
        final service = FakeNotificationService();
        final container = makeContainer(service: service);
        addTearDown(container.dispose);
        await awaitProviders(container);

        final settings = NotificationSettings(
          enabled: true,
          minutesBefore: 5,
          direction: BusDirection.fromChitose,
        );
        await container
            .read(notificationSettingsProvider.notifier)
            .saveSettings(settings);

        expect(service.scheduledCalls, isNotEmpty);
        for (final call in service.scheduledCalls) {
          expect(call.settings.minutesBefore, equals(5));
        }
      });

      test('最大3便まで通知がスケジュールされる', () async {
        final service = FakeNotificationService();
        // 未来4便あるが最大3便のみスケジュールされるべき
        final container = makeContainer(
          service: service,
          timetable: futureTimetable(BusDirection.fromChitose),
        );
        addTearDown(container.dispose);
        await awaitProviders(container);

        final settings = NotificationSettings(
          enabled: true,
          minutesBefore: 10,
          direction: BusDirection.fromChitose,
        );
        await container
            .read(notificationSettingsProvider.notifier)
            .saveSettings(settings);

        expect(service.scheduledCalls.length, greaterThan(0));
        expect(service.scheduledCalls.length, lessThanOrEqualTo(3));
      });

      test('過去のバスしかないとき scheduleNotification は呼ばれない', () async {
        final service = FakeNotificationService();
        final container = makeContainer(
          service: service,
          timetable: pastTimetable(BusDirection.fromChitose),
        );
        addTearDown(container.dispose);
        await awaitProviders(container);

        final settings = NotificationSettings(
          enabled: true,
          minutesBefore: 10,
          direction: BusDirection.fromChitose,
        );
        await container
            .read(notificationSettingsProvider.notifier)
            .saveSettings(settings);

        expect(service.cancelAllCount, greaterThanOrEqualTo(1));
        expect(service.scheduledCalls, isEmpty);
      });

      test('timetable が未ロードのとき cancelAll が呼ばれ古い通知が残らない', () async {
        final service = FakeNotificationService();
        final repo = FakeNotificationSettingsRepository();
        final container = ProviderContainer(
          overrides: [
            notificationServiceProvider.overrideWithValue(service),
            notificationSettingsRepositoryProvider.overrideWithValue(repo),
            // scheduleViewModel は永遠にロード中
            scheduleViewModelProvider
                .overrideWith(() => _FakeLoadingScheduleViewModel()),
          ],
        );
        addTearDown(container.dispose);
        // notificationSettingsProvider だけ初期化を待つ
        await container.read(notificationSettingsProvider.future);

        final settings = NotificationSettings(
          enabled: true,
          minutesBefore: 10,
          direction: BusDirection.fromChitose,
        );
        await container
            .read(notificationSettingsProvider.notifier)
            .saveSettings(settings);

        expect(service.cancelAllCount, greaterThanOrEqualTo(1),
            reason: 'timetable 未ロードでも古い通知はキャンセルされるべき');
        expect(service.scheduledCalls, isEmpty);
      });

      test('方面違いのバスが混在するとき指定方面のみ通知される', () async {
        final service = FakeNotificationService();
        final container = makeContainer(
          service: service,
          timetable: mixedDirectionTimetable(),
        );
        addTearDown(container.dispose);
        await awaitProviders(container);

        final settings = NotificationSettings(
          enabled: true,
          minutesBefore: 10,
          direction: BusDirection.fromChitose,
        );
        await container
            .read(notificationSettingsProvider.notifier)
            .saveSettings(settings);

        expect(service.scheduledCalls, isNotEmpty);
        for (final call in service.scheduledCalls) {
          expect(call.bus.direction, equals(BusDirection.fromChitose),
              reason: '指定方面以外のバスが通知されてはいけない');
        }
      });
    });

    group('enableNotifications()', () {
      test('権限が許可されたとき通知が再スケジュールされる', () async {
        final service = FakeNotificationService(permissionGranted: true);
        final container = makeContainer(
          service: service,
          initialSettings: NotificationSettings(
            enabled: false,
            minutesBefore: 10,
            direction: BusDirection.fromChitose,
          ),
        );
        addTearDown(container.dispose);
        await awaitProviders(container);

        final current =
            container.read(notificationSettingsProvider).value!;
        await container
            .read(notificationSettingsProvider.notifier)
            .enableNotifications(current);

        expect(service.scheduledCalls, isNotEmpty,
            reason: '権限許可後に通知がスケジュールされるべき');
      });

      test('権限が拒否されたとき cancelAll のみ呼ばれる', () async {
        final service = FakeNotificationService(permissionGranted: false);
        final container = makeContainer(
          service: service,
          initialSettings: NotificationSettings(
            enabled: false,
            minutesBefore: 10,
            direction: BusDirection.fromChitose,
          ),
        );
        addTearDown(container.dispose);
        await awaitProviders(container);

        final current =
            container.read(notificationSettingsProvider).value!;
        await container
            .read(notificationSettingsProvider.notifier)
            .enableNotifications(current);

        expect(service.cancelAllCount, greaterThanOrEqualTo(1));
        expect(service.scheduledCalls, isEmpty,
            reason: '権限拒否後は scheduleNotification が呼ばれるべきでない');
      });

      test('権限許可後に enabled=true で設定が保存される', () async {
        final service = FakeNotificationService(permissionGranted: true);
        final container = makeContainer(
          service: service,
          initialSettings: NotificationSettings(
            enabled: false,
            direction: BusDirection.fromChitose,
          ),
        );
        addTearDown(container.dispose);
        await awaitProviders(container);

        final current =
            container.read(notificationSettingsProvider).value!;
        await container
            .read(notificationSettingsProvider.notifier)
            .enableNotifications(current);

        final saved = container.read(notificationSettingsProvider).value!;
        expect(saved.enabled, isTrue);
      });

      test('権限拒否後に enabled=false で設定が保存される', () async {
        final service = FakeNotificationService(permissionGranted: false);
        final container = makeContainer(
          service: service,
          initialSettings: NotificationSettings(
            enabled: false,
            direction: BusDirection.fromChitose,
          ),
        );
        addTearDown(container.dispose);
        await awaitProviders(container);

        final current =
            container.read(notificationSettingsProvider).value!;
        await container
            .read(notificationSettingsProvider.notifier)
            .enableNotifications(current);

        final saved = container.read(notificationSettingsProvider).value!;
        expect(saved.enabled, isFalse);
      });
    });
  });
}
