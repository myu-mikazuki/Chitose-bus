import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kagi_bus/data/sources/schedule_local_source.dart';
import 'package:kagi_bus/data/models/bus_schedule_model.dart';

const _defaultStops = 'chitose,minamiChitose,kenkyuto,honbuto';

const _responseModel = ScheduleResponseModel(
  updatedAt: '2024-01-01',
  stopMaster: [StopModel(id: 'chitose', label: '千歳駅前')],
  current: BusTimetableModel(
    validFrom: '2024-01-01',
    validTo: '2024-03-31',
    trips: [
      TripModel(
        destination: '千歳科技大',
        stops: [StopTimeModel(id: 'chitose', time: '09:30')],
      ),
    ],
  ),
  upcoming: null,
);

const _responseModelWithUpcoming = ScheduleResponseModel(
  updatedAt: '2024-04-01',
  stopMaster: [],
  current: BusTimetableModel(
    validFrom: '2024-04-01',
    validTo: '2024-06-30',
    trips: [],
  ),
  upcoming: BusTimetableModel(
    validFrom: '2024-07-01',
    validTo: '2024-09-30',
    trips: [],
  ),
);

void main() {
  late ScheduleLocalSource source;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    source = ScheduleLocalSource();
  });

  group('ScheduleLocalSource.load', () {
    test('returns null when nothing has been saved', () async {
      expect(await source.load(_defaultStops), isNull);
    });

    test('returns saved model after save()', () async {
      await source.save(_responseModel, _defaultStops);

      final loaded = await source.load(_defaultStops);
      expect(loaded, isNotNull);
      expect(loaded!.updatedAt, '2024-01-01');
      expect(loaded.current.trips.length, 1);
      expect(loaded.current.trips.first.stops.first.time, '09:30');
      expect(loaded.upcoming, isNull);
    });

    test('restores model with upcoming non-null', () async {
      await source.save(_responseModelWithUpcoming, _defaultStops);

      final loaded = await source.load(_defaultStops);
      expect(loaded!.upcoming, isNotNull);
      expect(loaded.upcoming!.validFrom, '2024-07-01');
    });

    test('returns latest model when saved twice', () async {
      await source.save(_responseModel, _defaultStops);
      await source.save(_responseModelWithUpcoming, _defaultStops);

      final loaded = await source.load(_defaultStops);
      expect(loaded!.updatedAt, '2024-04-01');
    });

    test('returns null when JSON is corrupted', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('schedule_cache_json', 'not valid json {{{');
      await prefs.setString('schedule_cache_stops', _defaultStops);

      expect(await source.load(_defaultStops), isNull);
    });
  });

  group('停留所の選択とキャッシュ', () {
    test('選択が違うキャッシュはミス扱いになる', () async {
      // 選んだ停留所によって応答が変わるため、別の選択のキャッシュは使えない
      await source.save(_responseModel, _defaultStops);

      expect(await source.load('chitose,morimoto'), isNull);
    });

    test('選択が同じなら当たる', () async {
      await source.save(_responseModel, 'chitose,morimoto');

      expect(await source.load('chitose,morimoto'), isNotNull);
    });

    test('順序が違えばミス扱い（タブの並びが変わるため）', () async {
      await source.save(_responseModel, 'chitose,honbuto');

      expect(await source.load('honbuto,chitose'), isNull);
    });

    test('選択の記録が無い旧バージョンのキャッシュはミス扱い', () async {
      // v=3 時代のキャッシュは形式そのものが違うので読ませない
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('schedule_cache_json', '{"updatedAt":"2024-01-01"}');

      expect(await source.load(_defaultStops), isNull);
    });
  });

  group('#177 以前のキャッシュを読む（移行用）', () {
    // v=3 時代の形式。current.schedules に乗車地ごとの便が並ぶ
    const legacyJson = '''
{"updatedAt":"2026-08-01",
 "current":{"validFrom":"2025-04-01","validTo":"2099-12-31","pdfUrl":"",
   "schedules":[
     {"time":"07:20","direction":"from_chitose","destination":"科技大",
      "routeLabel":"空港経由","platformNumber":"5番",
      "weekdayOnly":false,"weekendOnly":false,
      "academicOnly":false,"vacationOnly":false,
      "arrivals":{"minamiChitose":"07:31","kenkyuto":"07:44","honbuto":"07:45"}},
     {"time":"11:36","direction":"from_honbuto","destination":"千歳駅",
      "routeLabel":"空港経由","platformNumber":null,
      "weekdayOnly":true,"weekendOnly":false,
      "academicOnly":false,"vacationOnly":false,
      "arrivals":{"kenkyuto":"11:39","chitose":"12:02"}}]},
 "upcoming":null}
''';

    Future<void> putLegacyCache() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('schedule_cache_json', legacyJson);
      // 旧バージョンは停留所の選択を記録していない
    }

    test('何も無ければ null', () async {
      expect(await source.loadLegacy(), isNull);
    });

    test('旧形式のキャッシュを読める（更新直後にオフラインでも時刻表を出す）', () async {
      await putLegacyCache();

      final loaded = await source.loadLegacy();
      expect(loaded, isNotNull);
      expect(loaded!.updatedAt, '2026-08-01');
      expect(loaded.current.schedules.length, 2);
    });

    test('便の中身が引き継がれる', () async {
      await putLegacyCache();

      final e = (await source.loadLegacy())!.current.schedules.first;
      expect(e.time, '07:20');
      expect(e.destination, '科技大');
      expect(e.routeLabel, '空港経由');
      expect(e.platformNumber, '5番');
      expect(e.arrivals, {
        'minamiChitose': '07:31',
        'kenkyuto': '07:44',
        'honbuto': '07:45',
      });
    });

    test('運行日フラグが引き継がれる', () async {
      await putLegacyCache();

      final entries = (await source.loadLegacy())!.current.schedules;
      expect(entries[0].weekdayOnly, isFalse);
      expect(entries[1].weekdayOnly, isTrue);
    });

    test('新形式で保存済みなら旧経路は使わない', () async {
      // 一度でも取得に成功していれば移行は済んでいる
      await source.save(_responseModel, _defaultStops);

      expect(await source.loadLegacy(), isNull);
    });

    test('壊れた JSON なら null', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('schedule_cache_json', 'not valid json {{{');

      expect(await source.loadLegacy(), isNull);
    });

    test('新形式の JSON を旧経路で読もうとしても null', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('schedule_cache_json',
          '{"updatedAt":"2026-08-10","current":{"trips":[]}}');

      expect(await source.loadLegacy(), isNull);
    });
  });

  group('ScheduleLocalSource.loadCachedAt', () {
    test('returns null when nothing has been saved', () async {
      expect(await source.loadCachedAt(), isNull);
    });

    test('returns timestamp close to now after save()', () async {
      final before = DateTime.now();
      await source.save(_responseModel, _defaultStops);
      final after = DateTime.now();

      final ts = await source.loadCachedAt();
      expect(ts, isNotNull);
      expect(ts!.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(ts.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });
  });
}
