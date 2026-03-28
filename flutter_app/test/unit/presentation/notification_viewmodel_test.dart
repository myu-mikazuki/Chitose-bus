import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';
import 'package:kagi_bus/domain/entities/notification_settings.dart';
import 'package:kagi_bus/domain/services/notification_service.dart';
import 'package:kagi_bus/data/repositories/notification_settings_repository.dart';
import 'package:kagi_bus/presentation/viewmodels/notification_viewmodel.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---- Fakes ----

class FakeNotificationService implements NotificationService {
  int cancelAllCount = 0;
  final List<int> canceledIds = [];
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
  Future<void> cancel(int id) async {
    canceledIds.add(id);
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

// ---- テスト用の固定時刻 ----

/// テスト全体で使う固定基準時刻（正午を使うことで前後数時間の未来・過去が当日内に収まる）
final _fixedNow = DateTime(2026, 1, 15, 12, 0, 0);

// ---- テスト用の BusTimetable ヘルパー ----

/// 指定した direction で未来時刻のバスを含む BusTimetable を生成する
BusTimetable futureTimetable(BusDirection direction) {
  final future1 = _fixedNow.add(const Duration(hours: 1));
  final future2 = _fixedNow.add(const Duration(hours: 2));
  final future3 = _fixedNow.add(const Duration(hours: 3));
  final future4 = _fixedNow.add(const Duration(hours: 4));
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
  final past1 = _fixedNow.subtract(const Duration(hours: 2));
  final past2 = _fixedNow.subtract(const Duration(hours: 1));
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
      clockProvider.overrideWithValue(() => _fixedNow),
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
  final future1 = _fixedNow.add(const Duration(hours: 1));
  final future2 = _fixedNow.add(const Duration(hours: 2));
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
      test('enabled=false: cancelAll・scheduleNotification は呼ばれない', () async {
        final service = FakeNotificationService();
        final container = makeContainer(service: service);
        addTearDown(container.dispose);
        await awaitProviders(container);

        await container
            .read(notificationSettingsProvider.notifier)
            .saveSettings(NotificationSettings(enabled: false));

        expect(service.cancelAllCount, 0,
            reason: 'direction ベース削除後は cancelAll を呼ばない');
        expect(service.scheduledCalls, isEmpty);
      });

      test('enabled=true, scheduledBusKeys 空: cancelAll・scheduleNotification は呼ばれない',
          () async {
        final service = FakeNotificationService();
        final container = makeContainer(service: service);
        addTearDown(container.dispose);
        await awaitProviders(container);

        await container
            .read(notificationSettingsProvider.notifier)
            .saveSettings(NotificationSettings(enabled: true));

        expect(service.cancelAllCount, 0,
            reason: 'direction ベース削除後は cancelAll を呼ばない');
        expect(service.scheduledCalls, isEmpty,
            reason: 'tracked 便がなければスケジュールしない');
      });

      test('enabled=true, scheduledBusKeys={key}: tracked な未来便のみスケジュールされる',
          () async {
        final service = FakeNotificationService();
        final futureTime = _fixedNow.add(const Duration(hours: 2));
        String fmt(DateTime dt) =>
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        final futureBus = BusEntry(
          time: fmt(futureTime),
          direction: BusDirection.fromChitose,
          destination: '千歳駅',
        );
        final key = NotificationSettingsNotifier.busKey(futureBus);
        final timetable = BusTimetable(
          validFrom: '2026-01-01',
          validTo: '2026-12-31',
          schedules: [futureBus],
        );
        final container = makeContainer(
          service: service,
          timetable: timetable,
          initialSettings: NotificationSettings(
            enabled: true,
            minutesBefore: 10,
            scheduledBusKeys: {key},
          ),
        );
        addTearDown(container.dispose);
        await awaitProviders(container);

        final current = container.read(notificationSettingsProvider).value!;
        await container
            .read(notificationSettingsProvider.notifier)
            .saveSettings(current.copyWith(minutesBefore: 5));

        // direction ベース削除後は tracked 便のみ → 1件
        expect(service.scheduledCalls.length, equals(1),
            reason: 'tracked 便のみスケジュールされるべき（direction ベースの重複なし）');
        expect(service.scheduledCalls.first.bus, equals(futureBus));
        expect(service.scheduledCalls.first.settings.minutesBefore, equals(5));
      });

      test('timetable 未ロード: scheduledBusKeys があっても scheduleNotification は呼ばれない',
          () async {
        final service = FakeNotificationService();
        final repo = FakeNotificationSettingsRepository(
          NotificationSettings(
            enabled: true,
            scheduledBusKeys: {'fromChitose_12:00'},
          ),
        );
        final container = ProviderContainer(
          overrides: [
            notificationServiceProvider.overrideWithValue(service),
            notificationSettingsRepositoryProvider.overrideWithValue(repo),
            clockProvider.overrideWithValue(() => _fixedNow),
            scheduleViewModelProvider
                .overrideWith(() => _FakeLoadingScheduleViewModel()),
          ],
        );
        addTearDown(container.dispose);
        await container.read(notificationSettingsProvider.future);

        final current = container.read(notificationSettingsProvider).value!;
        await container
            .read(notificationSettingsProvider.notifier)
            .saveSettings(current);

        expect(service.scheduledCalls, isEmpty,
            reason: 'timetable 未ロードのとき _rescheduleTrackedBuses は何もしない');
      });
    });

    group('enableNotifications()', () {
      test('権限が許可されたとき tracked 便が再スケジュールされる', () async {
        final service = FakeNotificationService(permissionGranted: true);
        final futureTime = _fixedNow.add(const Duration(hours: 2));
        String fmt(DateTime dt) =>
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        final futureBus = BusEntry(
          time: fmt(futureTime),
          direction: BusDirection.fromChitose,
          destination: '千歳駅',
        );
        final key = NotificationSettingsNotifier.busKey(futureBus);
        final timetable = BusTimetable(
          validFrom: '2026-01-01',
          validTo: '2026-12-31',
          schedules: [futureBus],
        );
        final container = makeContainer(
          service: service,
          timetable: timetable,
          initialSettings: NotificationSettings(
            enabled: false,
            minutesBefore: 10,
            scheduledBusKeys: {key},
          ),
        );
        addTearDown(container.dispose);
        await awaitProviders(container);

        final current = container.read(notificationSettingsProvider).value!;
        await container
            .read(notificationSettingsProvider.notifier)
            .enableNotifications(current);

        expect(service.scheduledCalls, isNotEmpty,
            reason: '権限許可後に tracked 便がスケジュールされるべき');
      });

      test('権限が拒否されたとき scheduleNotification は呼ばれない', () async {
        final service = FakeNotificationService(permissionGranted: false);
        final container = makeContainer(
          service: service,
          initialSettings: NotificationSettings(enabled: false),
        );
        addTearDown(container.dispose);
        await awaitProviders(container);

        final current = container.read(notificationSettingsProvider).value!;
        await container
            .read(notificationSettingsProvider.notifier)
            .enableNotifications(current);

        expect(service.scheduledCalls, isEmpty,
            reason: '権限拒否後は scheduleNotification が呼ばれるべきでない');
      });

      test('権限許可後に enabled=true で設定が保存される', () async {
        final service = FakeNotificationService(permissionGranted: true);
        final container = makeContainer(
          service: service,
          initialSettings: NotificationSettings(enabled: false),
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
          initialSettings: NotificationSettings(enabled: false),
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

    group('toggleBusNotification()', () {
      // 固定時刻から未来のバスを生成するヘルパー
      BusEntry futureBusEntry() {
        final future = _fixedNow.add(const Duration(hours: 2));
        String fmt(DateTime dt) =>
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        return BusEntry(
          time: fmt(future),
          direction: BusDirection.fromChitose,
          destination: '千歳駅',
        );
      }

      test('OFF→ON: scheduleNotification が呼ばれ scheduledBusKeys にキーが追加される', () async {
        final service = FakeNotificationService();
        final bus = futureBusEntry();
        final container = makeContainer(
          service: service,
          initialSettings: NotificationSettings(enabled: true, minutesBefore: 10),
        );
        addTearDown(container.dispose);
        await awaitProviders(container);

        await container
            .read(notificationSettingsProvider.notifier)
            .toggleBusNotification(bus);

        expect(service.scheduledCalls.length, equals(1),
            reason: 'scheduleNotification が1回呼ばれるべき');
        expect(service.scheduledCalls.first.bus, equals(bus));
        final saved = container.read(notificationSettingsProvider).value!;
        expect(saved.scheduledBusKeys, contains(NotificationSettingsNotifier.busKey(bus)));
      });

      test('ON→OFF: cancel(id) が呼ばれ scheduledBusKeys からキーが削除される', () async {
        final service = FakeNotificationService();
        final bus = futureBusEntry();
        final key = NotificationSettingsNotifier.busKey(bus);
        final container = makeContainer(
          service: service,
          initialSettings: NotificationSettings(
            enabled: true,
            minutesBefore: 10,
            scheduledBusKeys: {key},
          ),
        );
        addTearDown(container.dispose);
        await awaitProviders(container);

        await container
            .read(notificationSettingsProvider.notifier)
            .toggleBusNotification(bus);

        final expectedId = NotificationService.busNotificationId(bus);
        expect(service.canceledIds, contains(expectedId),
            reason: 'cancel(id) が呼ばれるべき');
        expect(service.scheduledCalls, isEmpty,
            reason: 'scheduleNotification は呼ばれるべきでない');
        final saved = container.read(notificationSettingsProvider).value!;
        expect(saved.scheduledBusKeys, isNot(contains(key)));
      });

      test('OFF→ON: 過去の便は scheduleNotification が呼ばれない', () async {
        final service = FakeNotificationService();
        // 固定時刻より過去のバス
        final past = _fixedNow.subtract(const Duration(hours: 1));
        String fmt(DateTime dt) =>
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        final pastBus = BusEntry(
          time: fmt(past),
          direction: BusDirection.fromChitose,
          destination: '千歳駅',
        );
        final container = makeContainer(
          service: service,
          initialSettings: NotificationSettings(enabled: true, minutesBefore: 10),
        );
        addTearDown(container.dispose);
        await awaitProviders(container);

        await container
            .read(notificationSettingsProvider.notifier)
            .toggleBusNotification(pastBus);

        expect(service.scheduledCalls, isEmpty,
            reason: '過去の便は scheduleNotification が呼ばれるべきでない');
        final saved = container.read(notificationSettingsProvider).value!;
        expect(saved.scheduledBusKeys, contains(NotificationSettingsNotifier.busKey(pastBus)),
            reason: 'キーは追加されるべき');
      });

      test('enabled=false のとき ON にしても scheduleNotification は呼ばれない', () async {
        final service = FakeNotificationService();
        final bus = futureBusEntry();
        final container = makeContainer(
          service: service,
          initialSettings: NotificationSettings(enabled: false),
        );
        addTearDown(container.dispose);
        await awaitProviders(container);

        await container
            .read(notificationSettingsProvider.notifier)
            .toggleBusNotification(bus);

        expect(service.scheduledCalls, isEmpty,
            reason: 'enabled=false では scheduleNotification は呼ばれるべきでない');
        final saved = container.read(notificationSettingsProvider).value!;
        expect(saved.scheduledBusKeys, contains(NotificationSettingsNotifier.busKey(bus)),
            reason: 'キーは追加されるべき');
      });

      test('minutesBefore 変更後の saveSettings: 選択済み便が再スケジュールされる', () async {
        final service = FakeNotificationService();
        // timetable に含まれる未来バスを使ってキーを作る
        final futureTime = _fixedNow.add(const Duration(hours: 2));
        String fmt(DateTime dt) =>
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        final futureBus = BusEntry(
          time: fmt(futureTime),
          direction: BusDirection.fromChitose,
          destination: '千歳駅',
        );
        final key = NotificationSettingsNotifier.busKey(futureBus);
        final timetable = BusTimetable(
          validFrom: '2026-01-01',
          validTo: '2026-12-31',
          schedules: [futureBus],
        );
        final container = makeContainer(
          service: service,
          timetable: timetable,
          initialSettings: NotificationSettings(
            enabled: true,
            minutesBefore: 10,
            scheduledBusKeys: {key},
          ),
        );
        addTearDown(container.dispose);
        await awaitProviders(container);

        final current = container.read(notificationSettingsProvider).value!;
        await container
            .read(notificationSettingsProvider.notifier)
            .saveSettings(current.copyWith(minutesBefore: 5));

        final trackedCalls = service.scheduledCalls
            .where((c) => c.bus.time == futureBus.time &&
                          c.bus.direction == futureBus.direction)
            .toList();
        expect(trackedCalls, isNotEmpty,
            reason: '選択済み便が再スケジュールされるべき');
        expect(trackedCalls.first.settings.minutesBefore, equals(5));
      });
    });
  });
}
