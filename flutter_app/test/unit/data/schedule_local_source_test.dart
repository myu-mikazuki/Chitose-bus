import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kagi_bus/data/sources/schedule_local_source.dart';
import 'package:kagi_bus/data/models/bus_schedule_model.dart';

const _responseModel = ScheduleResponseModel(
  updatedAt: '2024-01-01',
  current: BusTimetableModel(
    validFrom: '2024-01-01',
    validTo: '2024-03-31',
    pdfUrl: 'https://example.com/pdf',
    schedules: [
      BusEntryModel(
        time: '09:30',
        direction: 'from_chitose',
        destination: '千歳科技大',
      ),
    ],
  ),
  upcoming: null,
);

const _responseModelWithUpcoming = ScheduleResponseModel(
  updatedAt: '2024-04-01',
  current: BusTimetableModel(
    validFrom: '2024-04-01',
    validTo: '2024-06-30',
    pdfUrl: '',
    schedules: [],
  ),
  upcoming: BusTimetableModel(
    validFrom: '2024-07-01',
    validTo: '2024-09-30',
    pdfUrl: '',
    schedules: [],
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
      expect(await source.load(), isNull);
    });

    test('returns saved model after save()', () async {
      await source.save(_responseModel);

      final loaded = await source.load();
      expect(loaded, isNotNull);
      expect(loaded!.updatedAt, '2024-01-01');
      expect(loaded.current.schedules.length, 1);
      expect(loaded.current.schedules.first.time, '09:30');
      expect(loaded.upcoming, isNull);
    });

    test('restores model with upcoming non-null', () async {
      await source.save(_responseModelWithUpcoming);

      final loaded = await source.load();
      expect(loaded!.upcoming, isNotNull);
      expect(loaded.upcoming!.validFrom, '2024-07-01');
    });

    test('returns latest model when saved twice', () async {
      await source.save(_responseModel);
      await source.save(_responseModelWithUpcoming);

      final loaded = await source.load();
      expect(loaded!.updatedAt, '2024-04-01');
    });

    test('returns null when JSON is corrupted', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('schedule_cache_json', 'not valid json {{{');

      expect(await source.load(), isNull);
    });
  });

  group('ScheduleLocalSource.loadCachedAt', () {
    test('returns null when nothing has been saved', () async {
      expect(await source.loadCachedAt(), isNull);
    });

    test('returns timestamp close to now after save()', () async {
      final before = DateTime.now();
      await source.save(_responseModel);
      final after = DateTime.now();

      final ts = await source.loadCachedAt();
      expect(ts, isNotNull);
      expect(ts!.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(ts.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });
  });
}
