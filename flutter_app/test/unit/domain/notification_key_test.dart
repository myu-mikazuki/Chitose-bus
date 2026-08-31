import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';

void main() {
  // 通知キーは SharedPreferences に保存され、OS へ予約した通知の ID の元になる。
  // 変えると既存の予約を引き当てられず、キャンセルできない通知が残る。
  test('通知キーが #177 以前（BusDirection.name）と同じ文字列になる', () {
    // 旧: '${BusDirection.xxx.name}_${time}'
    final cases = {
      ('chitose', '科技大'): 'fromChitose_07:20',
      ('minamiChitose', '科技大'): 'fromMinamiChitose_07:20',
      ('kenkyuto', '科技大'): 'fromKenkyutoToHonbuto_07:20',
      ('kenkyuto', '千歳駅'): 'fromKenkyutoToStation_07:20',
      ('honbuto', '千歳駅'): 'fromHonbuto_07:20',
    };
    for (final e in cases.entries) {
      final entry = BusEntry(
          time: '07:20', boardingStopId: e.key.$1, destination: e.key.$2);
      expect(entry.notificationKey, e.value, reason: '${e.key}');
    }
  });

  test('該当が無い停留所は 乗車地_行き先_時刻 になる', () {
    const entry =
        BusEntry(time: '07:23', boardingStopId: 'morimoto', destination: '科技大');
    expect(entry.notificationKey, 'morimoto_科技大_07:23');
  });
}
