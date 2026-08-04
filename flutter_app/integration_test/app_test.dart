import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kagi_bus/domain/entities/bus_schedule.dart';
import 'package:kagi_bus/domain/repositories/schedule_repository.dart';
import 'package:kagi_bus/main.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_viewmodel.dart';

class MockScheduleRepository extends Mock implements ScheduleRepository {}

final _mockResponse = ScheduleResponse(
  updatedAt: '2024-01-01 09:00',
  current: BusTimetable(
    validFrom: '2024-01-01',
    validTo: '2024-03-31',
    schedules: [
      BusEntry(
        time: '09:00',
        direction: BusDirection.fromChitose,
        destination: '千歳科技大',
        arrivals: {'kenkyuto': '09:20', 'honbuto': '09:25'},
      ),
      BusEntry(
        time: '23:59',
        direction: BusDirection.fromChitose,
        destination: '千歳科技大',
      ),
      BusEntry(
        time: '09:30',
        direction: BusDirection.fromMinamiChitose,
        destination: '千歳科技大',
      ),
      BusEntry(
        time: '23:59',
        direction: BusDirection.fromMinamiChitose,
        destination: '千歳科技大',
      ),
      BusEntry(
        time: '10:00',
        direction: BusDirection.fromKenkyutoToHonbuto,
        destination: '本部棟',
      ),
      BusEntry(
        time: '23:59',
        direction: BusDirection.fromKenkyutoToHonbuto,
        destination: '本部棟',
      ),
      BusEntry(
        time: '10:30',
        direction: BusDirection.fromKenkyutoToStation,
        destination: '千歳駅',
      ),
      BusEntry(
        time: '23:59',
        direction: BusDirection.fromKenkyutoToStation,
        destination: '千歳駅',
      ),
      BusEntry(
        time: '11:00',
        direction: BusDirection.fromHonbuto,
        destination: '千歳駅',
      ),
      BusEntry(
        time: '23:59',
        direction: BusDirection.fromHonbuto,
        destination: '千歳駅',
      ),
    ],
  ),
  upcoming: BusTimetable(
    validFrom: '2024-04-01',
    validTo: '2024-06-30',
    schedules: [
      BusEntry(
        time: '09:00',
        direction: BusDirection.fromChitose,
        destination: '千歳科技大',
      ),
    ],
  ),
);

final _mockResponseNoUpcoming = ScheduleResponse(
  updatedAt: '2024-01-01 09:00',
  current: _mockResponse.current,
);

Widget _buildApp(MockScheduleRepository repo) {
  return ProviderScope(
    overrides: [
      scheduleRepositoryProvider.overrideWithValue(repo),
    ],
    child: const KagiBusApp(),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late MockScheduleRepository mockRepo;

  setUp(() {
    mockRepo = MockScheduleRepository();
    when(() => mockRepo.fetchSchedule()).thenAnswer((_) async => _mockResponse);
  });

  testWidgets('アプリ起動→ローディング表示→データ取得→タブ画面表示', (tester) async {
    await tester.pumpWidget(_buildApp(mockRepo));

    // ローディング表示確認
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // データ取得後タブ表示確認
    await tester.pumpAndSettle();
    expect(find.text('千歳駅'), findsOneWidget);
    expect(find.text('南千歳'), findsOneWidget);
    expect(find.text('研究棟'), findsOneWidget);
    expect(find.text('本部棟'), findsOneWidget);

    verify(() => mockRepo.fetchSchedule()).called(1);
  });

  testWidgets('千歳駅タブを選択→千歳駅方面のバス時刻が表示される', (tester) async {
    await tester.pumpWidget(_buildApp(mockRepo));
    await tester.pumpAndSettle();

    // 千歳駅タブをタップ（デフォルトで選択済みだが明示的にタップ）
    await tester.tap(find.text('千歳駅'));
    await tester.pumpAndSettle();

    // 千歳科技大の行き先が表示されること
    expect(find.text('千歳科技大'), findsWidgets);
    // NEXT BUS セクションラベルが表示されること
    expect(find.text('NEXT BUS'), findsOneWidget);
  });

  testWidgets('研究棟タブを選択→本部棟方面と千歳駅方面の両方が表示される', (tester) async {
    await tester.pumpWidget(_buildApp(mockRepo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('研究棟'));
    await tester.pumpAndSettle();

    expect(find.textContaining('→ 本部棟'), findsWidgets);
    expect(find.textContaining('→ 千歳駅'), findsWidgets);
  });

  testWidgets('リフレッシュボタンタップ→再ロード', (tester) async {
    await tester.pumpWidget(_buildApp(mockRepo));
    await tester.pumpAndSettle();

    // リフレッシュボタンタップ
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();

    // 再ローディング表示確認
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // 完了後タブ表示確認
    await tester.pumpAndSettle();
    expect(find.text('千歳駅'), findsOneWidget);

    // fetchSchedule が複数回呼ばれたことを確認
    verify(() => mockRepo.fetchSchedule()).called(greaterThan(1));
  });

  testWidgets('APIエラー時→エラーテキストと再試行ボタンが表示される', (tester) async {
    when(() => mockRepo.fetchSchedule())
        .thenThrow(Exception('Network error'));

    await tester.pumpWidget(_buildApp(mockRepo));
    await tester.pumpAndSettle();

    expect(find.textContaining('エラー'), findsOneWidget);
    expect(find.text('再試行'), findsOneWidget);
  });

  testWidgets('upcoming非nullのとき→カレンダーアイコンが表示される', (tester) async {
    await tester.pumpWidget(_buildApp(mockRepo));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.calendar_month), findsOneWidget);
  });

  testWidgets('upcoming nullのとき→カレンダーアイコンが表示されない', (tester) async {
    when(() => mockRepo.fetchSchedule())
        .thenAnswer((_) async => _mockResponseNoUpcoming);

    await tester.pumpWidget(_buildApp(mockRepo));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.calendar_month), findsNothing);
  });
}
