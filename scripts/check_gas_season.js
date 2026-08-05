#!/usr/bin/env node
/**
 * gas/Code.gs の期別判定とスキーマバージョン出し分けを検証する。
 *
 * GAS 側の seasonForYmd / isSuspendedYmd はアプリ側の SeasonType.fromDate /
 * ServiceCalendar.isSuspended と同一でなければならない（v=1 と v=2 で結果が
 * 食い違うため）。境界値はアプリ側の season_type_test.dart と揃えてある。
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

console.log('復路の南千歳着（大学配付物「学休期ダイヤ（修正版）」より）');

// 復路は全便が南千歳駅を経由する。市の PDF は該当セルが黒塗りに見えるが
// 通過を意味しない（Issue #159 の差し戻し）。大学版を正とする。
const allSchedules = doGetJson(2, '2026-06-17').current.schedules;
function minamiChitoseOf(time) {
  const e = allSchedules.find(
    (x) => x.time === time && x.direction === 'from_honbuto'
  );
  return e ? e.arrivals.minamiChitose : 'ERROR: 便が見つからない';
}
// 02 科技大 ▶ 空港経由 ▶ 千歳駅行き の全10便
[
  ['11:36', '11:51'], ['12:42', '12:57'], ['13:35', '13:50'], ['14:32', '14:47'],
  ['15:24', '15:39'], ['16:47', '17:02'], ['17:52', '18:07'], ['19:02', '19:17'],
  ['19:42', '19:57'], ['21:22', '21:37'],
].forEach(([t, m]) => check(`${t} 本部棟発 → 南千歳 ${m}`, minamiChitoseOf(t), m));

// 03 科技大 ▶ 空港・千歳駅経由 ▶ 長都駅行き
[['20:32', '20:47'], ['22:02', '22:17']].forEach(([t, m]) =>
  check(`${t} 本部棟発（長都行き）→ 南千歳 ${m}`, minamiChitoseOf(t), m)
);

// 15:24 は期別で分岐しない（両期とも南千歳を経由する）
check('15:24 は期別に分かれていない',
  allSchedules.filter((e) => e.time === '15:24' && e.direction === 'from_honbuto').length, 1);

console.log('');
if (failures > 0) {
  console.log(`❌ ${failures} 件失敗`);
  process.exit(1);
}
console.log('✅ すべてパス');
