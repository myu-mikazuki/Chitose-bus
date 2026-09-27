import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/presentation/views/widgets/arrival_row.dart';

import '../helpers/test_theme.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: buildTestTheme(), home: Scaffold(body: child));

void main() {
  group('ArrivalRow', () {
    testWidgets('タップすると正式名の行が展開される', (tester) async {
      await tester.pumpWidget(_wrap(const ArrivalRow(
        stopId: 'kenkyuto',
        time: '10:20',
        stopMaster: kTestStopMaster,
      )));

      expect(find.text('科技大研究棟'), findsNothing);

      await tester.tap(find.text('研究棟 着'));
      await tester.pump();

      expect(find.text('科技大研究棟'), findsOneWidget);
    });

    // `didUpdateWidget` の「同じ位置の行が別の到着地・時刻に変わったら展開を
    // 閉じる」分岐（`arrival_row.dart:88-103`）のテスト。この分岐が無いと、
    // 同じ位置に別の便・別の到着地が来たときに前の便の正式名が誤って
    // 展開されたままになる（例: NEXT の便が繰り上がったとき）。
    testWidgets('展開後に stopId が変わると展開状態が閉じる', (tester) async {
      await tester.pumpWidget(_wrap(const ArrivalRow(
        stopId: 'kenkyuto',
        time: '10:20',
        stopMaster: kTestStopMaster,
      )));

      await tester.tap(find.text('研究棟 着'));
      await tester.pump();
      expect(find.text('科技大研究棟'), findsOneWidget);

      // 同じ位置（Widget を差し替えるだけで、ArrivalRow 自体は再利用される）
      // に別の到着地を渡す
      await tester.pumpWidget(_wrap(const ArrivalRow(
        stopId: 'honbuto',
        time: '10:25',
        stopMaster: kTestStopMaster,
      )));
      await tester.pump();

      // 展開が閉じ、前の便の正式名は出ていない。新しい行も展開されていない
      // （既定の短縮名のみ）
      expect(find.text('科技大研究棟'), findsNothing);
      expect(find.text('科技大本部棟'), findsNothing);
      expect(find.text('本部棟 着'), findsOneWidget);
    });

    // 対照として、stopId / time が変わらなければ展開状態は保たれることも
    // 確かめる（`didUpdateWidget` の条件が広すぎて毎回閉じてしまう、という
    // 逆方向の壊れ方を拾う）
    testWidgets('展開後に stopId・time が変わらなければ展開状態を保つ', (tester) async {
      await tester.pumpWidget(_wrap(const ArrivalRow(
        stopId: 'kenkyuto',
        time: '10:20',
        stopMaster: kTestStopMaster,
      )));

      await tester.tap(find.text('研究棟 着'));
      await tester.pump();
      expect(find.text('科技大研究棟'), findsOneWidget);

      // 同じ stopId / time で pump し直す（親の再ビルドを模す）
      await tester.pumpWidget(_wrap(const ArrivalRow(
        stopId: 'kenkyuto',
        time: '10:20',
        stopMaster: kTestStopMaster,
      )));
      await tester.pump();

      expect(find.text('科技大研究棟'), findsOneWidget);
    });
  });
}
