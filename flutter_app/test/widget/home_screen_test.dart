import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';
import 'package:kagi_bus/domain/entities/favorite_tab.dart';
import 'package:kagi_bus/presentation/viewmodels/favorite_tab_viewmodel.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_viewmodel.dart';
import 'package:kagi_bus/presentation/views/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_theme.dart';

// ---------------------------------------------------------------------------
// Fake ViewModels
// ---------------------------------------------------------------------------

class _FakeScheduleViewModel extends ScheduleViewModel {
  _FakeScheduleViewModel(this._response);

  final ScheduleResponse _response;
  bool refreshCalled = false;

  @override
  Future<ScheduleResponse> build() async => _response;

  @override
  Future<void> refresh() async {
    refreshCalled = true;
  }
}

class _LoadingViewModel extends ScheduleViewModel {
  @override
  Future<ScheduleResponse> build() async {
    // Never completes → keeps state as AsyncLoading
    await Completer<void>().future;
    throw Exception('unreachable');
  }
}

class _ErrorViewModel extends ScheduleViewModel {
  _ErrorViewModel(this._error);
  final Object _error;

  @override
  Future<ScheduleResponse> build() async => throw _error;
}

class _FakeFavoriteTabNotifier extends FavoriteTabNotifier {
  final FavoriteTab _initial;
  int? lastToggleIndex;

  _FakeFavoriteTabNotifier(this._initial);

  @override
  Future<FavoriteTab> build() async => _initial;

  @override
  Future<void> toggleFavorite(int tabIndex) async {
    lastToggleIndex = tabIndex;
    final current = state.value!;
    state = AsyncData(
      current.tabIndex == tabIndex
          ? const FavoriteTab()
          : FavoriteTab(tabIndex: tabIndex),
    );
  }
}

/// Error VM that also tracks refresh() calls.
class _TrackingErrorViewModel extends ScheduleViewModel {
  bool refreshCalled = false;

  @override
  Future<ScheduleResponse> build() async => throw Exception('test error');

  @override
  Future<void> refresh() async {
    refreshCalled = true;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _emptyTimetable = BusTimetable(
  validFrom: '2024-01-01',
  validTo: '2024-03-31',
  schedules: const [],
);

final _mockResponse = ScheduleResponse(
  updatedAt: '2024-01-01',
  current: _emptyTimetable,
);

final _mockResponseWithUpcoming = ScheduleResponse(
  updatedAt: '2024-01-01',
  current: _emptyTimetable,
  upcoming: BusTimetable(
    validFrom: '2024-04-01',
    validTo: '2024-06-30',
    schedules: const [],
  ),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('HomeScreen', () {
    testWidgets('loading状態: CircularProgressIndicatorが表示される', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scheduleViewModelProvider.overrideWith(() => _LoadingViewModel()),
            countdownOverride(),
          ],
          child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
        ),
      );

      // Don't pump further — the loading future never completes
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('error状態: 「エラー:」テキストと「再試行」ボタンが表示される', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scheduleViewModelProvider.overrideWith(
                () => _ErrorViewModel(Exception('test error'))),
            countdownOverride(),
          ],
          child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
        ),
      );
      await tester.pump(); // let the failed future resolve

      expect(find.textContaining('エラー:'), findsOneWidget);
      expect(find.text('再試行'), findsOneWidget);
    });

    testWidgets('error状態で「再試行」タップ: refreshが呼ばれる', (tester) async {
      final vm = _TrackingErrorViewModel();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scheduleViewModelProvider.overrideWith(() => vm),
            countdownOverride(),
          ],
          child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
        ),
      );
      await tester.pump(); // let the failed future resolve

      await tester.tap(find.text('再試行'));
      await tester.pump();

      expect(vm.refreshCalled, isTrue);
    });

    testWidgets('data状態: 4つのタブ（千歳駅・南千歳・研究棟・本部棟）が表示される', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scheduleViewModelProvider
                .overrideWith(() => _FakeScheduleViewModel(_mockResponse)),
            countdownOverride(),
          ],
          child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('千歳駅'), findsOneWidget);
      expect(find.text('南千歳'), findsOneWidget);
      expect(find.text('研究棟'), findsOneWidget);
      expect(find.text('本部棟'), findsOneWidget);
    });

    testWidgets('data状態でupcoming非null: カレンダーアイコンが表示される', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scheduleViewModelProvider.overrideWith(
                () => _FakeScheduleViewModel(_mockResponseWithUpcoming)),
            countdownOverride(),
          ],
          child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.calendar_month), findsOneWidget);
    });

    testWidgets('カレンダーアイコンタップ: ModalBottomSheetが表示され「来週のダイヤ」が含まれる',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scheduleViewModelProvider.overrideWith(
                () => _FakeScheduleViewModel(_mockResponseWithUpcoming)),
            countdownOverride(),
          ],
          child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.calendar_month));
      await tester.pumpAndSettle();

      expect(find.textContaining('来週のダイヤ'), findsOneWidget);
    });

    testWidgets('リフレッシュボタンタップ: refreshが呼ばれる', (tester) async {
      final vm = _FakeScheduleViewModel(_mockResponse);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scheduleViewModelProvider.overrideWith(() => vm),
            countdownOverride(),
          ],
          child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();

      expect(vm.refreshCalled, isTrue);
    });

    // 市路線バスは土日も一部運行するためバナーは現在非表示（WeekendWarningBanner._enabled = false）
    testWidgets('土曜日のdata状態: 土日バナーが表示されない（現在無効化中）', (tester) async {
      // 2024-01-06 = Saturday
      final saturday = DateTime(2024, 1, 6, 9, 0);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scheduleViewModelProvider
                .overrideWith(() => _FakeScheduleViewModel(_mockResponse)),
            countdownOverride(now: saturday),
          ],
          child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
        ),
      );
      await tester.pump();

      expect(
        find.text('土日祝日はバスが運行していない場合があります'),
        findsNothing,
      );
    });

    testWidgets('平日のdata状態: 土日バナーが表示されない', (tester) async {
      // 2024-01-01 = Monday (kTestNow)
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scheduleViewModelProvider
                .overrideWith(() => _FakeScheduleViewModel(_mockResponse)),
            countdownOverride(),
          ],
          child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
        ),
      );
      await tester.pump();

      expect(
        find.text('土日祝日はバスが運行していない場合があります'),
        findsNothing,
      );
    });

    group('お気に入りタブ', () {
      testWidgets('お気に入り未設定: star_border アイコンが表示される', (tester) async {
        final favNotifier = _FakeFavoriteTabNotifier(const FavoriteTab());
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => _FakeScheduleViewModel(_mockResponse)),
              favoriteTabProvider.overrideWith(() => favNotifier),
              countdownOverride(),
            ],
            child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pump();

        expect(find.byIcon(Icons.star_border), findsOneWidget);
        expect(find.byIcon(Icons.star), findsNothing);
      });

      testWidgets('タブ0がお気に入り: star アイコンが表示される', (tester) async {
        final favNotifier =
            _FakeFavoriteTabNotifier(const FavoriteTab(tabIndex: 0));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => _FakeScheduleViewModel(_mockResponse)),
              favoriteTabProvider.overrideWith(() => favNotifier),
              countdownOverride(),
            ],
            child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pump();

        expect(find.byIcon(Icons.star), findsOneWidget);
        expect(find.byIcon(Icons.star_border), findsNothing);
      });

      testWidgets('タブ1がお気に入り: 別タブ表示中は star_border が表示される', (tester) async {
        // タブ0を表示している状態で、タブ1がお気に入り → star_border
        final favNotifier =
            _FakeFavoriteTabNotifier(const FavoriteTab(tabIndex: 1));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => _FakeScheduleViewModel(_mockResponse)),
              favoriteTabProvider.overrideWith(() => favNotifier),
              countdownOverride(),
            ],
            child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pump();

        // 初期表示はタブ0（千歳駅）
        expect(find.byIcon(Icons.star_border), findsOneWidget);
      });

      testWidgets('スタータップ: toggleFavorite が現在タブのインデックスで呼ばれる',
          (tester) async {
        final favNotifier = _FakeFavoriteTabNotifier(const FavoriteTab());
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              scheduleViewModelProvider
                  .overrideWith(() => _FakeScheduleViewModel(_mockResponse)),
              favoriteTabProvider.overrideWith(() => favNotifier),
              countdownOverride(),
            ],
            child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
          ),
        );
        await tester.pump();

        await tester.tap(find.byIcon(Icons.star_border));
        await tester.pump();

        expect(favNotifier.lastToggleIndex, equals(0)); // タブ0が現在表示中
      });
    });
  });
}
