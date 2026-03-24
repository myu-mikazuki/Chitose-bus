import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chitose_bus/domain/entities/bus_schedule.dart';
import 'package:chitose_bus/presentation/viewmodels/schedule_viewmodel.dart';
import 'package:chitose_bus/presentation/views/home_screen.dart';

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
  group('HomeScreen', () {
    testWidgets('loading状態: CircularProgressIndicatorが表示される', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scheduleViewModelProvider.overrideWith(() => _LoadingViewModel()),
            countdownOverride(),
          ],
          child: const MaterialApp(home: HomeScreen()),
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
          child: const MaterialApp(home: HomeScreen()),
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
          child: const MaterialApp(home: HomeScreen()),
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
          child: const MaterialApp(home: HomeScreen()),
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
          child: const MaterialApp(home: HomeScreen()),
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
          child: const MaterialApp(home: HomeScreen()),
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
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();

      expect(vm.refreshCalled, isTrue);
    });

    testWidgets('土曜日のdata状態: 土日バナーが表示される', (tester) async {
      // 2024-01-06 = Saturday
      final saturday = DateTime(2024, 1, 6, 9, 0);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scheduleViewModelProvider
                .overrideWith(() => _FakeScheduleViewModel(_mockResponse)),
            countdownOverride(now: saturday),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();

      expect(
        find.text('土日祝日は一部の便のみ運行します（系統2は運休）'),
        findsWidgets,
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
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pump();

      expect(
        find.text('土日祝日は一部の便のみ運行します（系統2は運休）'),
        findsNothing,
      );
    });
  });
}
