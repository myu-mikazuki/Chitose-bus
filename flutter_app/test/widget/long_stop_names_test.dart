import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';
import 'package:kagi_bus/domain/entities/stop_selection.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_result.dart';
import 'package:kagi_bus/presentation/viewmodels/schedule_viewmodel.dart';
import 'package:kagi_bus/presentation/viewmodels/stop_selection_viewmodel.dart';
import 'package:kagi_bus/presentation/views/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_theme.dart';

/// 既定の4停留所の外を選んだときの表示を守る（#177）。
///
/// #177 以前は GAS が4停留所に絞っていたため、長い名前も未知の ID も画面に
/// 出てこなかった。設定でバス停を選べるようになって初めて露出する。
///
/// overflow はテストが自動で失敗として拾うので、「例外なく pump できること」
/// 自体が検査になっている。

class _FakeScheduleViewModel extends ScheduleViewModel {
  _FakeScheduleViewModel(this._result);
  final ScheduleResult _result;

  @override
  Future<ScheduleResult> build() async => _result;

  @override
  Future<void> refresh() async {}
}

class _FakeStopSelectionNotifier extends StopSelectionNotifier {
  _FakeStopSelectionNotifier(this._initial);
  final StopSelection _initial;

  @override
  Future<StopSelection> build() async => _initial;
}

/// 実データで最も長い部類の停留所名。短縮名を持たない
const _master = [
  BusStop(id: 'chitose', label: '千歳駅前', shortLabel: '千歳駅'),
  BusStop(id: 'koizumi', label: '古泉循環器内科クリニック前'),
  BusStop(id: 'arcadia', label: 'オフィス・アルカディア入口'),
  BusStop(id: 'hoyukai', label: '千歳豊友会病院前'),
  BusStop(id: 'osatsu', label: '長都駅東口'),
  BusStop(id: 'honbuto', label: '科技大本部棟', shortLabel: '本部棟'),
];

const _result = ScheduleResult(
  data: ScheduleResponse(
    stopMaster: _master,
    updatedAt: '2024-01-01',
    current: BusTimetable(
      validFrom: '2024-01-01',
      validTo: '2024-12-31',
      schedules: [
        BusEntry(
          time: '09:00',
          boardingStopId: 'koizumi',
          destination: '科技大',
          // 既定の4停留所に無い到着地。対応表を引いていた頃は `null 着` になった
          arrivals: {
            'arcadia': '09:05',
            'hoyukai': '09:12',
            'honbuto': '09:30',
          },
        ),
      ],
    ),
  ),
);

Widget _wrap(List<String> stopIds) => ProviderScope(
      overrides: [
        scheduleViewModelProvider
            .overrideWith(() => _FakeScheduleViewModel(_result)),
        stopSelectionProvider.overrideWith(
          () => _FakeStopSelectionNotifier(StopSelection(stopIds: stopIds)),
        ),
        // 2024-01-01 は年末年始（12/31〜1/3）で全便運休になり、便が1つも出ない
        countdownOverride(now: DateTime(2024, 6, 17, 8, 0)),
      ],
      child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('長い名前・既定外の停留所', () {
    testWidgets('タブが overflow しない（狭い端末）', (tester) async {
      // iPhone SE 相当。タブ1つあたり約94px しかない
      tester.view.physicalSize = const Size(750, 1334);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester
          .pumpWidget(_wrap(['koizumi', 'arcadia', 'hoyukai', 'chitose']));
      await tester.pumpAndSettle();
    });

    // #231。到着行は `spaceBetween` に素の Text を2つ並べるだけなので、
    // 名前が伸びると縮まずに溢れる。**幅の主張はここでしかできない**
    // （既定の4停留所は短縮名が短く、溢れる長さにならない）。
    //
    // 「タブが overflow しない（狭い端末）」では拾えなかった。あちらは
    // 停留所を4つ選ぶため `_retuneTabs` が既定の先頭 `chitose` を追いかけ、
    // その停留所を発つ便が無いので `_StopHasNoBus` が出てカード自体が
    // 描かれない。1停留所だけ選ばせるとカードに辿り着く。
    for (final width in [375.0, 360.0]) {
      testWidgets('NEXT BUS の到着行が overflow しない（幅 $width・#231）', (tester) async {
        tester.view.physicalSize = Size(width * 2, 1334);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_wrap(['koizumi']));
        await tester.pumpAndSettle();

        // 短縮名を持たない到着地。overflow はテストが失敗として拾う
        expect(find.text('オフィス・アルカディア入口 着'), findsOneWidget);
      });
    }

    testWidgets('見出しの停留所名は削らずに正式名を出す', (tester) async {
      await tester.pumpWidget(_wrap(['koizumi']));
      await tester.pumpAndSettle();

      // タブでは1〜2文字しか読めない名前を、ここでは丸ごと出す（#208）。
      // find.text だけでは ellipsis で切れていても通るので、省略の有無まで見る
      expect(find.text('古泉循環器内科クリニック前 発'), findsOneWidget);
      expectNotTruncated(tester, '古泉循環器内科クリニック前 発');
    });

    testWidgets('到着地のラベルが null にならない', (tester) async {
      await tester.pumpWidget(_wrap(['koizumi']));
      await tester.pumpAndSettle();

      // NEXT BUS カード
      expect(find.textContaining('null'), findsNothing);
      expect(find.text('オフィス・アルカディア入口 着'), findsOneWidget);

      // 時刻表の行を開く
      await tester.tap(find.text('09:00').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('null'), findsNothing);
      expect(find.text('千歳豊友会病院前 着'), findsWidgets);
    });

    testWidgets('短縮名があればそちらを出す（既定の4停留所の見え方は不変）', (tester) async {
      await tester.pumpWidget(_wrap(['koizumi']));
      await tester.pumpAndSettle();

      // 科技大本部棟 ではなく 本部棟
      expect(find.text('本部棟 着'), findsOneWidget);
      expect(find.text('科技大本部棟 着'), findsNothing);
    });

    testWidgets('stopMaster に無い ID は ID をそのまま出す', (tester) async {
      // GAS から停留所が消えても null にはしない
      const result = ScheduleResult(
        data: ScheduleResponse(
          stopMaster: _master,
          updatedAt: '2024-01-01',
          current: BusTimetable(
            validFrom: '2024-01-01',
            validTo: '2024-12-31',
            schedules: [
              BusEntry(
                time: '09:00',
                boardingStopId: 'koizumi',
                destination: '科技大',
                arrivals: {'ghost': '09:05'},
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          scheduleViewModelProvider
              .overrideWith(() => _FakeScheduleViewModel(result)),
          stopSelectionProvider.overrideWith(
            () => _FakeStopSelectionNotifier(
                const StopSelection(stopIds: ['koizumi'])),
          ),
          countdownOverride(now: DateTime(2024, 6, 17, 8, 0)),
        ],
        child: MaterialApp(theme: buildTestTheme(), home: const HomeScreen()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('ghost 着'), findsOneWidget);
    });
  });
}
