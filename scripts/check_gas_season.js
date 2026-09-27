#!/usr/bin/env node
/**
 * gas/Code.gs の期別判定とスキーマバージョン出し分けを検証する。
 *
 * GAS 側の seasonForYmd / isSuspendedYmd / dayTypeForYmd はアプリ側の
 * SeasonType.fromDate / ServiceCalendar.isSuspended / DayType.fromDate と
 * 同一でなければならない（v=1 と v=2 で結果が食い違うため）。
 * 境界値はアプリ側の season_type_test.dart / japanese_holiday_test.dart と
 * 揃えてある。
 *
 * 使い方: node scripts/check_gas_season.js
 */

const fs = require('fs');
const path = require('path');

const CODE_GS = path.join(__dirname, '..', 'gas', 'Code.gs');

// GAS のグローバル API を最小限スタブする
const FIXED_TODAY = { value: '2026-08-04' };
global.Utilities = { formatDate: () => FIXED_TODAY.value };
global.ContentService = {
  MimeType: { JSON: 'application/json' },
  createTextOutput(s) {
    return { _body: s, setMimeType() { return this; }, getContent() { return this._body; } };
  },
};

eval(fs.readFileSync(CODE_GS, 'utf8'));

let failures = 0;
function check(label, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) {
    console.log(`  ok   ${label}`);
  } else {
    console.log(`  FAIL ${label}\n         期待: ${e}\n         実際: ${a}`);
    failures++;
  }
}

function season(dateString) {
  return seasonForYmd(parseYmd(dateString));
}
function suspended(dateString) {
  return isSuspendedYmd(parseYmd(dateString));
}

console.log('期別判定（夏季: 8月第1月曜日 〜 9月第4金曜日）');
check('2026-08-02 (日) 開始前日', season('2026-08-02'), 'academic');
check('2026-08-03 (月) 開始日', season('2026-08-03'), 'vacation');
check('2026-09-25 (金) 終了日', season('2026-09-25'), 'vacation');
check('2026-09-26 (土) 終了翌日', season('2026-09-26'), 'academic');
check('2027-08-01 (日)', season('2027-08-01'), 'academic');
check('2027-08-02 (月) 第1月曜日', season('2027-08-02'), 'vacation');

console.log('期別判定（冬季: 2月第1月曜日 〜 3月31日）');
check('2026-02-01 (日) 開始前日', season('2026-02-01'), 'academic');
check('2026-02-02 (月) 開始日', season('2026-02-02'), 'vacation');
check('2026-03-31 終了日', season('2026-03-31'), 'vacation');
check('2026-04-01 終了翌日', season('2026-04-01'), 'academic');

console.log('期別判定（お盆・授業期）');
['13', '14', '15', '16'].forEach((d) =>
  check(`2026-08-${d} お盆`, season(`2026-08-${d}`), 'vacation')
);
check('2026-06-17 授業期', season('2026-06-17'), 'academic');
check('2026-11-04 授業期', season('2026-11-04'), 'academic');

console.log('年末年始（12/31 〜 1/3）');
check('2025-12-30', suspended('2025-12-30'), false);
check('2025-12-31', suspended('2025-12-31'), true);
check('2026-01-01', suspended('2026-01-01'), true);
check('2026-01-03', suspended('2026-01-03'), true);
check('2026-01-04', suspended('2026-01-04'), false);

console.log('スキーマバージョンによる出し分け');

function times(schedules, direction) {
  return schedules
    .filter((e) => e.direction === direction && !e.weekendOnly)
    .map((e) => e.time)
    .sort();
}
function doGetJson(v, today) {
  FIXED_TODAY.value = today;
  const e = v === null ? {} : { parameter: { v: String(v) } };
  return JSON.parse(doGet(e).getContent());
}

// 学休期の平日に、v=1 は絞り込み済み・v=2 は全便を返す
const v2 = doGetJson(2, '2026-08-04');
const v1 = doGetJson(1, '2026-08-04');
const vNone = doGetJson(null, '2026-08-04');

// 8/4 は学休期の平日。**令和8年10月1日改正のダイヤには学休期が無い**ため、
// 期別で減る便は1本も無く、平日ダイヤがそのまま出る（#253）。
// 改正前はここが14便（学休期のみ）で、v=2 の33便と差が出ていた。
// 学休期が復活したらこの期待値も戻すこと。
const expectedVacation = [
  '06:29', '06:45', '06:59', '07:00', '07:15', '07:29', '07:34', '07:50',
  '08:00', '08:10', '08:16', '08:19', '08:24', '08:29', '08:50', '09:04',
  '09:19', '09:34', '09:50', '09:54', '10:04', '10:14', '10:45', '11:00',
  '11:29', '11:50', '12:10', '12:19', '12:40', '13:20', '14:24', '14:50',
  '15:18', '16:00', '18:29', '19:29',
];

check('v=1 は当日(学休期)の便のみ',
  times(v1.current.schedules, 'from_chitose'), expectedVacation);
check('v 未指定は v=1 と同じ',
  times(vNone.current.schedules, 'from_chitose'), expectedVacation);
// 期別が無いので v=2 の全便と一致する。**一致しなくなったら期別が復活した合図**
check('v=2 は全便を返す（学休期が無いので v=1 と同数）',
  times(v2.current.schedules, 'from_chitose').length, expectedVacation.length);
check('v=1 は期別フラグを含まない',
  v1.current.schedules.some((e) => 'academicOnly' in e || 'vacationOnly' in e), false);
check('v=2 は期別フラグを含む',
  v2.current.schedules.some((e) => 'vacationOnly' in e), true);

// 授業期の平日
const v1Academic = doGetJson(1, '2026-09-28');
check('v=1 授業期は直通17便を含む',
  v1Academic.current.schedules
    .filter((e) => e.direction === 'from_chitose' && e.routeLabel === '直通').length, 17);

// 年末年始
const v1NewYear = doGetJson(1, '2027-01-01');
check('v=1 年末年始は空', v1NewYear.current.schedules.length, 0);
check('v=2 年末年始も全便返す（アプリ側で判定）',
  doGetJson(2, '2027-01-01').current.schedules.length > 0, true);

console.log('復路の南千歳着（Issue #159 の回帰ガード）')

// 空港経由・長都行きの復路は**全便が南千歳駅を経由する**。
// 千歳市の旧 PDF（bibikuuko.pdf）は該当セルが黒塗りに見えるが、これは通過を
// 意味しない。実際に通過と誤読して到着時刻を削除し本番に出した（#159／PR #176）。
//
// **令和8年10月1日改正版でこの食い違いは解消した。** 新 PDF
// （bibi_jikoku.pdf）はテキストレイヤーを持ち、復路の空17・空18 全25便に
// 南千歳駅の時刻が並んでいることを機械的に確認できる。
//
// 時刻を直接並べると改正のたびに全滅するので、**「空港を通る復路便は必ず
// 南千歳の到着を持つ」という不変条件**で見る。削除されたら 0 件ではなく
// 「欠けている便」として出る。
const allSchedules = doGetJson(2, '2026-06-17').current.schedules;
const viaAirport = allSchedules.filter(
  (e) => e.direction === 'from_honbuto' &&
    (e.routeLabel === '空港経由' || e.routeLabel === '長都行き')
);
check('空港を通る復路便が1件以上ある', viaAirport.length > 0, true);
check('そのすべてが南千歳の到着を持つ',
  viaAirport.filter((e) => !e.arrivals.minamiChitose).map((e) => e.time), []);

// 直通・南千歳行きは南千歳駅を通らない（通ることにしてはいけない）
check('直通の復路は南千歳を持たない',
  allSchedules.filter(
    (e) => e.direction === 'from_honbuto' && e.routeLabel === '直通' &&
      e.arrivals.minamiChitose).length, 0);

console.log('祝日判定（Issue #158）');

// 祝日は土日祝ダイヤ。ただし PDF が「平日ダイヤ」と明記する5日は平日扱い。
const holidayCases = [
  ['2026-08-11', '山の日', 'weekendHoliday'],
  ['2026-01-01', '元日', 'weekendHoliday'],
  ['2026-02-11', '建国記念の日', 'weekendHoliday'],
  ['2026-05-04', 'みどりの日', 'weekendHoliday'],
  ['2026-09-21', '敬老の日', 'weekendHoliday'],
  ['2026-09-22', '国民の休日', 'weekendHoliday'],
  ['2026-09-23', '秋分の日', 'weekendHoliday'],
  ['2026-03-20', '春分の日', 'weekendHoliday'],
];
holidayCases.forEach(([d, name, dt]) => {
  const ymd = parseYmd(d);
  check(`${d} は ${name}`, holidayNameOf(ymd.y, ymd.m, ymd.d), name);
  check(`${d} は ${dt}`, dayTypeForYmd(ymd), dt);
});

// 「祝日だが平日ダイヤ」の5日
[['2026-04-29', '昭和の日'], ['2026-11-03', '文化の日'], ['2026-11-23', '勤労感謝の日']]
  .forEach(([d, name]) => {
    const ymd = parseYmd(d);
    check(`${d}(${name}) は祝日だが平日ダイヤ`, dayTypeForYmd(ymd), 'weekday');
  });

// 平日・土日
check('2026-08-05 (水) は平日', dayTypeForYmd(parseYmd('2026-08-05')), 'weekday');
check('2026-08-08 (土) は土日祝', dayTypeForYmd(parseYmd('2026-08-08')), 'weekendHoliday');

// 8/11（山の日）に出るはずの千歳駅発。v=1 と v=2 で同じ並びになることも見る
const holidayExpected = [
  '06:29', '07:15', '07:34', '07:50', '08:24', '09:50', '10:45',
  '11:29', '12:40', '13:40', '16:00', '17:30', '18:29', '19:29',
];

// v=1 の応答: 8/11 は土日祝ダイヤに絞られ、運行日フラグが落ちていること
//
// ★ 期待値は令和8年10月1日改正のデータ（#253）。改正前は「学休期 × 土日祝」の
//   交わりで5便だったが、**新ダイヤには学休期が無い**ため土日祝ダイヤそのものが
//   出る。学休期の扱いは大学に確認中で、復活させるならここも戻すこと。
const v1Holiday = doGetJson(1, '2026-08-11');
check('8/11 の千歳駅発は14便',
  times(v1Holiday.current.schedules, 'from_chitose'),
  holidayExpected);
// 平日限定の直通便が土日祝に漏れないこと。新ダイヤの直通は毎日運行が2便ある
check('8/11 に出る直通便は毎日運行の2便だけ',
  v1Holiday.current.schedules.filter(
    (e) => e.direction === 'from_chitose' && e.routeLabel === '直通')
    .map((e) => e.time).sort(),
  ['07:50', '08:24']);
check('8/11 は運行日フラグが落ちている',
  v1Holiday.current.schedules.every((e) => !e.weekdayOnly && !e.weekendOnly), true);

// 平日は従来どおりフラグを保持する（余計な変更をしていないこと）
const v1Weekday = doGetJson(1, '2026-08-05');
check('平日は weekdayOnly を保持',
  v1Weekday.current.schedules.some((e) => e.weekdayOnly), true);

console.log('祝日 × スキーマバージョン（v1.2.0 のすり抜け防止）');

// v1.2.0 は v=2 を送るが DayType.fromDate が土日しか見ない。
// そのアプリの絞り込みを再現し、祝日でも正しい便数になることを確認する。
function asV120(json, today) {
  // v1.2.0 相当: 曜日は土日のみ判定（祝日を知らない）、期別は判定できる
  const d = new Date(`${today}T00:00:00Z`);
  const isWeekend = d.getUTCDay() === 0 || d.getUTCDay() === 6;
  const season = seasonForYmd(parseYmd(today));
  return json.current.schedules.filter(
    (e) =>
      e.direction === 'from_chitose' &&
      !(isWeekend && e.weekdayOnly) &&
      !(!isWeekend && e.weekendOnly) &&
      !(season === 'vacation' && e.academicOnly) &&
      !(season === 'academic' && e.vacationOnly)
  );
}

const v2Holiday = doGetJson(2, '2026-08-11');
check('v=2 で v1.2.0 が 8/11 に表示するのは14便',
  asV120(v2Holiday, '2026-08-11').map((e) => e.time).sort(), holidayExpected);
check('v=2 で v1.2.0 に出る直通便は毎日運行の2便だけ',
  asV120(v2Holiday, '2026-08-11')
    .filter((e) => e.routeLabel === '直通').map((e) => e.time).sort(),
  ['07:50', '08:24']);

// v=3 は全便を返し、アプリ側（祝日判定あり）が絞る
const v3Holiday = doGetJson(3, '2026-08-11');
check('v=3 は祝日でも全便を返す',
  v3Holiday.current.schedules.length > v2Holiday.current.schedules.length, true);
check('v=3 は運行日フラグを保持',
  v3Holiday.current.schedules.some((e) => e.weekdayOnly), true);

// 平日は v=2 も v=3 も全便のまま（当日以外のダイヤ表示のため）
const v2Weekday = doGetJson(2, '2026-08-05');
const v3Weekday = doGetJson(3, '2026-08-05');
check('平日は v=2 と v=3 が同一',
  v2Weekday.current.schedules.length, v3Weekday.current.schedules.length);

console.log('');
if (failures > 0) {
  console.log(`❌ ${failures} 件失敗`);
  process.exit(1);
}
console.log('✅ すべてパス');
