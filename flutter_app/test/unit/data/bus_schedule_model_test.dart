import 'package:flutter_test/flutter_test.dart';
import 'package:kagi_bus/data/models/bus_schedule_model.dart';
import 'package:kagi_bus/domain/entities/bus_schedule.dart';

/// 系統1 往路（千歳駅 → 空港経由 → 科技大）の 07:20 便。
/// 現行の4停留所に加え、途中の「もりもと本店前」を含む。
const _outbound = TripModel(
  destination: '科技大',
  routeLabel: '空港経由',
  stops: [
    StopTimeModel(id: 'chitose', time: '07:20', platform: '5番'),
    StopTimeModel(id: 'morimoto', time: '07:23'),
    StopTimeModel(id: 'minamiChitose', time: '07:31'),
    StopTimeModel(id: 'kenkyuto', time: '07:44'),
    StopTimeModel(id: 'honbuto', time: '07:45'),
  ],
);

/// 系統1 復路（科技大 → 空港経由 → 千歳駅）の 11:36 便
const _inbound = TripModel(
  destination: '千歳駅',
  routeLabel: '空港経由',
  weekdayOnly: true,
  stops: [
    StopTimeModel(id: 'honbuto', time: '11:36'),
    StopTimeModel(id: 'kenkyuto', time: '11:39'),
    StopTimeModel(id: 'minamiChitose', time: '11:51'),
    StopTimeModel(id: 'chitose', time: '12:02'),
  ],
);

/// 系統2 直通（南千歳を経由しない）
const _direct = TripModel(
  destination: '科技大',
  routeLabel: '直通',
  weekdayOnly: true,
  academicOnly: true,
  stops: [
    StopTimeModel(id: 'chitose', time: '07:14', platform: '3番'),
    StopTimeModel(id: 'kenkyuto', time: '07:32'),
    StopTimeModel(id: 'honbuto', time: '07:35'),
  ],
);

List<BusEntry> entriesOf(List<TripModel> trips) => BusTimetableModel(
      validFrom: '2025-04-01',
      validTo: '2099-12-31',
      trips: trips,
    ).toEntity().schedules;

void main() {
  group('TripModel → BusEntry の展開', () {
    test('終点を除く全ての停留所が乗車地になる', () {
      // 終点は後に停留所が無いので乗車地にならない
      final entries = entriesOf([_outbound]);
      expect(entries.map((e) => e.boardingStopId), [
        'chitose',
        'morimoto',
        'minamiChitose',
        'kenkyuto',
      ]);
      expect(entries.map((e) => e.time), ['07:20', '07:23', '07:31', '07:44']);
    });

    test('復路も同じく終点以外が乗車地になる', () {
      final entries = entriesOf([_inbound]);
      expect(entries.map((e) => e.boardingStopId), [
        'honbuto',
        'kenkyuto',
        'minamiChitose',
      ]);
      expect(entries.map((e) => e.time), ['11:36', '11:39', '11:51']);
    });

    test('arrivals は乗車地より後の停留所を通過順に持つ', () {
      final entries = entriesOf([_outbound]);
      expect(entries[0].arrivals, {
        'morimoto': '07:23',
        'minamiChitose': '07:31',
        'kenkyuto': '07:44',
        'honbuto': '07:45',
      });
      expect(entries.last.arrivals, {'honbuto': '07:45'});
    });

    test('途中の停留所も乗車地・到着地として扱える', () {
      // #177 の目的。もりもと本店前から乗る便が引ける
      final entries = entriesOf([_outbound]);
      final fromMorimoto =
          entries.firstWhere((e) => e.boardingStopId == 'morimoto');
      expect(fromMorimoto.time, '07:23');
      expect(fromMorimoto.arrivals.keys, ['minamiChitose', 'kenkyuto', 'honbuto']);
    });

    test('復路の arrivals も通過順（研究棟 → 南千歳 → 千歳駅）', () {
      final entries = entriesOf([_inbound]);
      expect(entries[0].arrivals.keys.toList(),
          ['kenkyuto', 'minamiChitose', 'chitose']);
      expect(entries[1].arrivals.keys.toList(), ['minamiChitose', 'chitose']);
    });

    test('のりばは乗車地のものだけが付く', () {
      final entries = entriesOf([_outbound]);
      expect(entries.first.platformNumber, '5番');
      expect(entries[1].platformNumber, isNull);
    });

    test('通らない停留所は arrivals に現れない（直通は南千歳を経由しない）', () {
      final entries = entriesOf([_direct]);
      expect(entries.map((e) => e.boardingStopId), [
        'chitose',
        'kenkyuto',
      ]);
      expect(entries[0].arrivals, {'kenkyuto': '07:32', 'honbuto': '07:35'});
    });

    test('のりばは乗車地が持つものだけを引き継ぐ', () {
      final entries = entriesOf([_outbound]);
      expect(entries[0].platformNumber, '5番');
      expect(entries[1].platformNumber, isNull);
      expect(entries[2].platformNumber, isNull);
    });

    test('運行日・期別のフラグが全ての展開先に引き継がれる', () {
      final entries = entriesOf([_direct]);
      for (final e in entries) {
        expect(e.weekdayOnly, isTrue);
        expect(e.academicOnly, isTrue);
        expect(e.weekendOnly, isFalse);
        expect(e.vacationOnly, isFalse);
      }
    });

    test('destination と routeLabel が引き継がれる', () {
      final entries = entriesOf([_outbound]);
      for (final e in entries) {
        expect(e.destination, '科技大');
        expect(e.routeLabel, '空港経由');
      }
    });

    test('停留所が1つだけの便は展開されない', () {
      // 選んだ停留所を1つしか通らない便。乗っても降りる先が無い
      final entries = entriesOf([
        const TripModel(
          destination: '科技大',
          stops: [StopTimeModel(id: 'morimoto', time: '07:23')],
        ),
      ]);
      expect(entries, isEmpty);
    });
  });

  group('ScheduleResponseModel', () {
    test('stopMaster が entity に引き継がれる', () {
      const model = ScheduleResponseModel(
        updatedAt: '2026-08-10',
        stopMaster: [
          StopModel(id: 'chitose', label: '千歳駅前'),
          StopModel(id: 'rapidus', label: 'ラピダス前', boardable: false),
        ],
        current: BusTimetableModel(trips: []),
      );
      final entity = model.toEntity();
      expect(entity.stopMaster.length, 2);
      expect(entity.stopMaster.first.label, '千歳駅前');
    });

    test('boardable は既定 true、false のときだけ落ちる', () {
      const model = ScheduleResponseModel(
        updatedAt: '2026-08-10',
        stopMaster: [
          StopModel(id: 'chitose', label: '千歳駅前'),
          StopModel(id: 'rapidus', label: 'ラピダス前', boardable: false),
        ],
        current: BusTimetableModel(trips: []),
      );
      final stops = model.toEntity().stopMaster;
      expect(stops[0].boardable, isTrue);
      expect(stops[1].boardable, isFalse);
    });

    test('JSON から復元できる（GAS の応答そのままの形）', () {
      final model = ScheduleResponseModel.fromJson(const {
        'updatedAt': '2026-08-10',
        'stopMaster': [
          {'id': 'chitose', 'label': '千歳駅前'},
          {'id': 'rapidus', 'label': 'ラピダス前', 'boardable': false},
        ],
        'current': {
          'validFrom': '2025-04-01',
          'validTo': '2099-12-31',
          'trips': [
            {
              'destination': '科技大',
              'routeLabel': '空港経由',
              'weekdayOnly': false,
              'weekendOnly': false,
              'academicOnly': false,
              'vacationOnly': false,
              'stops': [
                {'id': 'chitose', 'time': '07:20', 'platform': '5番'},
                {'id': 'honbuto', 'time': '07:45'},
              ],
            },
          ],
        },
        'upcoming': null,
      });

      expect(model.stopMaster.length, 2);
      expect(model.stopMaster[1].boardable, isFalse);
      expect(model.current.trips.single.stops.first.platform, '5番');

      final entries = model.toEntity().current.schedules;
      expect(entries.single.boardingStopId, 'chitose');
      expect(entries.single.arrivals, {'honbuto': '07:45'});
    });
  });
}
