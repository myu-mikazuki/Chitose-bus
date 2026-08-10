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
