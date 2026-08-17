#!/usr/bin/env node
/**
 * gas/Code.gs の doGet 応答が、記録済みのスナップショットと一致するか検証する。
 *
 * 停留所の拡張（Issue #177）でデータモデルを作り直すが、`stops` を指定しない
 * 従来のリクエスト（v=1 / v=2 / v=3）の応答は**1バイトも変わってはいけない**。
 * 旧アプリはストア更新をしない限り永久に残るため、ここが崩れると
 * リリース済みの全バージョンに影響する。
 *
 * スナップショットは scripts/fixtures/doget-v{N}-{date}.json に置く。
 *
 * 使い方:
 *   node scripts/check_gas_response.js          検証する
 *   node scripts/check_gas_response.js --update スナップショットを取り直す
 */

const fs = require('fs');
const path = require('path');

const CODE_GS = path.join(__dirname, '..', 'gas', 'Code.gs');
const FIXTURE_DIR = path.join(__dirname, 'fixtures');

// doGet は Utilities.formatDate で「今日」を決めるので、日付を固定して差し替える
const TODAY = { value: '2026-06-17' };
global.Utilities = { formatDate: () => TODAY.value };
global.ContentService = {
  MimeType: { JSON: 'application/json' },
  createTextOutput(s) {
    return { _body: s, setMimeType() { return this; }, getContent() { return this._body; } };
  },
};

eval(fs.readFileSync(CODE_GS, 'utf8'));

/** 応答の分岐に効く日付を網羅する */
const DATES = [
  ['2026-06-17', '授業期・平日'],
  ['2026-08-05', '学休期・平日'],
  ['2026-08-08', '学休期・土曜'],
  ['2026-08-11', '山の日（平日にあたる祝日）'],
  ['2026-11-03', '文化の日（祝日だが平日ダイヤ）'],
  ['2026-01-02', '年末年始・全便運休'],
];

// v=1 は「?v= 無し」と同じ経路
const VERSIONS = [1, 2, 3];

/**
 * v=4（停留所を選べる新形式）は日付で内容が変わらない（絞り込みをアプリに任せ、
 * updatedAt しか日付に依存しない）ので、1日付だけを見る。
 * 代わりに ?stops= の指定パターンを網羅する。
 */
const V4_CASES = [
  ['all', null, '全停留所（stops 無し）'],
  ['default', 'chitose,minamiChitose,kenkyuto,honbuto', 'アプリの初期状態と同じ4停留所'],
  ['single', 'morimoto', '1停留所だけ'],
];
const V4_DATE = '2026-06-17';

function respond(version, date, stops) {
  TODAY.value = date;
  const param = { v: String(version) };
  if (stops) param.stops = stops;
  return doGet({ parameter: param }).getContent();
}

function fixturePath(version, date) {
  return path.join(FIXTURE_DIR, `doget-v${version}-${date}.json`);
}

const update = process.argv.includes('--update');
if (update && !fs.existsSync(FIXTURE_DIR)) fs.mkdirSync(FIXTURE_DIR, { recursive: true });

let failures = 0;
let checked = 0;

/**
 * 便テーブルの整合性を見る。
 *
 * 旧形式のスナップショットは4停留所しか通らないため、残り26停留所は
 * ここで守るしかない。時刻が停留所順に並んでいなければセルの割り付けが
 * ずれている（PDF から起こしたときの典型的な事故）。
 */
function checkRouteData() {
  const ids = new Set();
  for (const s of STOPS) {
    if (ids.has(s.id)) { console.log(`  FAIL 停留所 ID の重複: ${s.id}`); failures++; }
    ids.add(s.id);
    if ('boardable' in s && s.boardable !== false) {
      // true は既定なので書かない。書いてあるのは false だけのはず
      console.log(`  FAIL ${s.id}: boardable は false のときだけ書く（実際: ${s.boardable}）`);
      failures++;
    }
    // 乗車できない停留所が旧形式の乗車地に混ざると、旧アプリが選べない停留所を出す
    if (s.boardable === false && LEGACY_STOPS.indexOf(s.id) >= 0) {
      console.log(`  FAIL ${s.id}: 乗車不可なのに LEGACY_STOPS に含まれている`);
      failures++;
    }
    // 正式名と同じ shortLabel は書かない（アプリは shortLabel ?? label で解決する）
    if (s.shortLabel === s.label) {
      console.log(`  FAIL ${s.id}: shortLabel が label と同じ。同じなら書かない`);
      failures++;
    }
  }

  // shortLabel はタブなど幅の狭い場所で使う短縮名。#177 以降、タブの文字列は
  // GAS が唯一の供給元になり、アプリ側には比較対象が無い。
  //
  // #207 より前は「4停留所だけが持つ」と集合を固定していた。全件に付けたので
  // 固定はやめ、代わりに**全件あること**と**重複が無いこと**を見る。
  // 抜けると正式名がそのままタブに出て頭の1〜2文字しか読めなくなり（#207 の発端）、
  // 重複すると最大5件並ぶタブで別の停留所が同じ名前になる。
  //
  // 足すときは「正式名から削って作る」こと（gas/Code.gs の STOPS のコメント）。
  // 出典の無い略称を発明すると、利用者が実際のバス停の表記と対応付けられなくなる。
  const noShort = STOPS.filter((s) => !s.shortLabel).map((s) => s.id);
  if (noShort.length) {
    console.log(`  FAIL shortLabel が無い停留所: ${noShort.join(' / ')}`);
    failures++;
  }
  const byShort = new Map();
  for (const s of STOPS) {
    if (!s.shortLabel) continue;
    if (!byShort.has(s.shortLabel)) byShort.set(s.shortLabel, []);
    byShort.get(s.shortLabel).push(s.id);
  }
  for (const [short, dupes] of byShort) {
    if (dupes.length > 1) {
      console.log(`  FAIL shortLabel の重複: ${short} (${dupes.join(' / ')})`);
      failures++;
    }
  }

  const toMin = (t) => Number(t.slice(0, 2)) * 60 + Number(t.slice(3));
  let trips = 0;
  let times = 0;

  for (const route of ROUTES) {
    if (!LEGACY_BOARDING[route.direction]) {
      console.log(`  FAIL ${route.routeLabel}: LEGACY_BOARDING に無い direction: ${route.direction}`);
      failures++;
    }
    for (const id of route.stops) {
      if (!ids.has(id)) { console.log(`  FAIL STOPS に無い停留所: ${id}`); failures++; }
    }
    for (const [, , ts] of route.trips) {
      trips++;
      if (ts.length !== route.stops.length) {
        console.log(`  FAIL ${route.routeLabel}: 時刻の数(${ts.length})が停留所数(${route.stops.length})と違う`);
        failures++;
        continue;
      }
      for (let i = 0; i < ts.length; i++) {
        times++;
        if (!/^\d{2}:\d{2}$/.test(ts[i])) {
          console.log(`  FAIL ${route.routeLabel} ${ts[0]}: 時刻の形式が不正 ${ts[i]}`);
          failures++;
        } else if (i > 0 && toMin(ts[i]) < toMin(ts[i - 1])) {
          console.log(`  FAIL ${route.routeLabel} ${ts[0]}: ${route.stops[i]} の時刻 ${ts[i]} が前の停留所より前`);
          failures++;
        }
      }
    }
  }
  // アプリは destination の文字列で行き先を区別する（BusDestination.campus /
  // .station）。行き先の切り替えの並び順もこの2値を前提にしている
  // （home_screen.dart の _StopTab.destinations）。
  // ROUTES に3つ目を足すとアプリ側が知らない行き先になるので、集合を固定する。
  const APP_KNOWN_DESTINATIONS = ['科技大', '千歳駅'];
  const actual = [...new Set(ROUTES.map((r) => r.destination))].sort();
  const expected = [...APP_KNOWN_DESTINATIONS].sort();
  if (actual.join('|') !== expected.join('|')) {
    console.log(`  FAIL destination の集合がアプリの adapter と食い違う`);
    console.log(`         アプリが知っている: ${expected.join(' / ')}`);
    console.log(`         ROUTES にあるもの : ${actual.join(' / ')}`);
    failures++;
  }

  // ROUTES は「系統」ではなく往復・期別に分けた表なので、系統数とは一致しない
  console.log(`  ok   便テーブル ${ROUTES.length}表 / ${trips}便 / ${times}時刻 / 停留所 ${STOPS.length}`);
}

console.log('便テーブルの整合性');
checkRouteData();
console.log('\n応答のスナップショット');

/** 便の配列を取り出す。旧形式は current.schedules、v>=4 は current.trips */
function entriesOf(res) {
  return res.current.schedules || res.current.trips || [];
}

function compareOrSave(file, actual, name) {
  if (update) {
    // 読みやすさのため整形して保存する（比較は再整形した文字列同士で行う）
    fs.writeFileSync(file, JSON.stringify(JSON.parse(actual), null, 1) + '\n');
    console.log(`  saved ${name}`);
    return;
  }

  if (!fs.existsSync(file)) {
    console.log(`  FAIL ${name} — スナップショットが無い: ${path.relative(process.cwd(), file)}`);
    failures++;
    return;
  }

  checked++;
  const expected = fs.readFileSync(file, 'utf8');
  const normalized = JSON.stringify(JSON.parse(actual), null, 1) + '\n';
  if (normalized === expected) {
    console.log(`  ok   ${name}`);
    return;
  }

  failures++;
  const a = entriesOf(JSON.parse(actual));
  const b = entriesOf(JSON.parse(expected));
  console.log(`  FAIL ${name} — 便数 期待=${b.length} 実際=${a.length}`);
  // 最初の差分だけ出す。全部出すと読めない
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const x = JSON.stringify(a[i]);
    const y = JSON.stringify(b[i]);
    if (x !== y) {
      console.log(`         [${i}] 期待: ${y}`);
      console.log(`         [${i}] 実際: ${x}`);
      break;
    }
  }
}

for (const version of VERSIONS) {
  for (const [date, label] of DATES) {
    compareOrSave(
      fixturePath(version, date),
      respond(version, date),
      `v=${version} ${date} (${label})`
    );
  }
}

for (const [name, stops, label] of V4_CASES) {
  compareOrSave(
    path.join(FIXTURE_DIR, `doget-v4-${name}.json`),
    respond(4, V4_DATE, stops),
    `v=4 ${name} (${label})`
  );
}

/**
 * fixture に持つほどでもない v=4 の不変条件。
 * 「何を主張しているか」がそのまま読めるので、応答の全文を置くより意図が伝わる。
 */
function checkV4Invariants() {
  if (update) return;

  const same = (label, a, b) => {
    checked++;
    if (a === b) { console.log(`  ok   ${label}`); return; }
    failures++;
    console.log(`  FAIL ${label}`);
  };

  // 知らない停留所 ID は捨てるだけ。結果は知っている分だけを指定したときと等しい
  same(
    'v=4 知らない ID を捨てる（chitose,does-not-exist === chitose）',
    respond(4, V4_DATE, 'chitose,does-not-exist'),
    respond(4, V4_DATE, 'chitose')
  );

  // 全部が未知なら空の時刻表ではなく全停留所を返す
  same(
    'v=4 全部が未知なら全停留所（does-not-exist === stops 無し）',
    respond(4, V4_DATE, 'does-not-exist'),
    respond(4, V4_DATE, null)
  );

  // 素の {} をマップに使うと Object.prototype のメンバを拾ってしまう
  same(
    'v=4 プロトタイプのキーは停留所として扱わない（toString === stops 無し）',
    respond(4, V4_DATE, 'toString'),
    respond(4, V4_DATE, null)
  );

  // v=4 は絞り込みをアプリに任せるので、updatedAt 以外は日付に依存しない。
  // ここが崩れるのは v=4 にサーバ側フィルタを足してしまったとき
  const strip = (json) => {
    const o = JSON.parse(json);
    delete o.updatedAt;
    return JSON.stringify(o);
  };
  same(
    'v=4 は日付で変わらない（年末年始 === 授業期平日、updatedAt を除く）',
    strip(respond(4, '2026-01-02', null)),
    strip(respond(4, V4_DATE, null))
  );
  same(
    'v=4 は祝日でも変わらない（山の日 === 授業期平日、updatedAt を除く）',
    strip(respond(4, '2026-08-11', null)),
    strip(respond(4, V4_DATE, null))
  );

  // terminus は「一般に降りられる最後の停留所」（#177）。
  // 便が通る停留所のひとつであること、乗車不可の停留所（ラピダス前）を
  // 終点にしないことを固定する。boardable: false が将来増えたときに
  // terminusOf の想定が崩れていないかを見てくれる
  const bad = [];
  ROUTES.forEach(function (route) {
    const t = terminusOf(route.stops);
    const where = `${route.routeLabel} / ${route.destination}`;
    if (route.stops.indexOf(t) < 0) {
      bad.push(`${where}: terminus=${t} が便の停留所に無い`);
    }
    if (!isBoardableStop(t)) {
      bad.push(`${where}: terminus=${t} は乗車不可の停留所`);
    }
  });
  checked++;
  if (bad.length === 0) {
    console.log('  ok   v=4 terminus は便が通る乗車可能な停留所');
  } else {
    failures++;
    console.log('  FAIL v=4 terminus が不正');
    bad.forEach((m) => console.log(`         ${m}`));
  }

  // terminus は絞り込みの前に決まる。選んだ停留所で変わってはいけない
  const terminiOf = (stops) => {
    const o = JSON.parse(respond(4, V4_DATE, stops));
    return [...new Set(o.current.trips.map((t) => t.terminus))].sort().join(',');
  };
  same(
    'v=4 terminus は ?stops= で変わらない（イオンを足しても同じ）',
    terminiOf('chitose,minamiChitose,kenkyuto,honbuto'),
    terminiOf('chitose,minamiChitose,kenkyuto,honbuto,aeon')
  );
}

checkV4Invariants();

if (update) {
  console.log('\nスナップショットを更新した。差分を必ず目視で確認すること。');
  process.exit(0);
}

console.log(`\n${failures ? `不一致 ${failures}` : `全 ${checked} 件一致`}`);
process.exit(failures ? 1 : 0);
