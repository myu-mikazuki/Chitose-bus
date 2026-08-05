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

const expectedVacation = [
  '07:20', '08:10', '08:40', '09:10', '09:50', '10:30', '11:00',
  '11:29', '12:10', '12:19', '13:20', '14:29', '16:00', '18:00',
];

check('v=1 は当日(学休期)の便のみ',
  times(v1.current.schedules, 'from_chitose'), expectedVacation);
check('v 未指定は v=1 と同じ',
  times(vNone.current.schedules, 'from_chitose'), expectedVacation);
check('v=2 は全便を返す（授業期の便も含む）',
  times(v2.current.schedules, 'from_chitose').length, 33);
check('v=1 は期別フラグを含まない',
  v1.current.schedules.some((e) => 'academicOnly' in e || 'vacationOnly' in e), false);
check('v=2 は期別フラグを含む',
  v2.current.schedules.some((e) => 'vacationOnly' in e), true);

// 授業期の平日
const v1Academic = doGetJson(1, '2026-09-28');
check('v=1 授業期は直通19便を含む',
  v1Academic.current.schedules
    .filter((e) => e.direction === 'from_chitose' && e.routeLabel === '直通').length, 19);

// 年末年始
const v1NewYear = doGetJson(1, '2027-01-01');
check('v=1 年末年始は空', v1NewYear.current.schedules.length, 0);
check('v=2 年末年始も全便返す（アプリ側で判定）',
  doGetJson(2, '2027-01-01').current.schedules.length > 0, true);

console.log('南千歳駅を経由しない便（Issue #159）');

// 復路の毎日運行便は南千歳駅を通過する。PDF「＜復路＞【空17・空18】」より。
const allSchedules = doGetJson(2, '2026-06-17').current.schedules;
function minamiChitoseOf(time) {
  const e = allSchedules.find(
    (x) => x.time === time && x.direction === 'from_honbuto'
  );
  return e ? 'minamiChitose' in e.arrivals : 'ERROR: 便が見つからない';
}
[['17:52'], ['19:02'], ['20:32'], ['22:02']].forEach(([t]) =>
  check(`${t} 本部棟発は南千歳を経由しない`, minamiChitoseOf(t), false)
);
// 経由する便は維持されていること
[['11:36', '11:51'], ['16:47', '17:02'], ['19:42', '19:57']].forEach(([t, m]) => {
  const e = allSchedules.find(
    (x) => x.time === t && x.direction === 'from_honbuto'
  );
  check(`${t} 本部棟発は南千歳 ${m} を経由する`, e && e.arrivals.minamiChitose, m);
});

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

// v=1 の応答: 8/11 は土日祝ダイヤに絞られ、運行日フラグが落ちていること
const v1Holiday = doGetJson(1, '2026-08-11');
check('8/11 の千歳駅発は5便',
  times(v1Holiday.current.schedules, 'from_chitose'),
  ['07:20', '08:18', '09:10', '11:29', '13:20']);
check('8/11 に直通便は無い',
  v1Holiday.current.schedules.filter(
    (e) => e.direction === 'from_chitose' && e.routeLabel === '直通').length, 0);
check('8/11 は運行日フラグが落ちている',
  v1Holiday.current.schedules.every((e) => !e.weekdayOnly && !e.weekendOnly), true);

// 平日は従来どおりフラグを保持する（余計な変更をしていないこと）
const v1Weekday = doGetJson(1, '2026-08-05');
check('平日は weekdayOnly を保持',
  v1Weekday.current.schedules.some((e) => e.weekdayOnly), true);

console.log('');
if (failures > 0) {
  console.log(`❌ ${failures} 件失敗`);
  process.exit(1);
}
console.log('✅ すべてパス');
