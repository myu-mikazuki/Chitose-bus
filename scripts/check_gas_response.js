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

// v=1 は「?v= 無し」と同じ経路。v=4 以降は #177 で追加する新形式なのでここでは見ない
const VERSIONS = [1, 2, 3];

function respond(version, date) {
  TODAY.value = date;
  const e = { parameter: { v: String(version) } };
  return doGet(e).getContent();
}

function fixturePath(version, date) {
  return path.join(FIXTURE_DIR, `doget-v${version}-${date}.json`);
}

const update = process.argv.includes('--update');
if (update && !fs.existsSync(FIXTURE_DIR)) fs.mkdirSync(FIXTURE_DIR, { recursive: true });

let failures = 0;
let checked = 0;

for (const version of VERSIONS) {
  for (const [date, label] of DATES) {
    const actual = respond(version, date);
    const file = fixturePath(version, date);

    if (update) {
      // 読みやすさのため整形して保存する（比較は再整形した文字列同士で行う）
      fs.writeFileSync(file, JSON.stringify(JSON.parse(actual), null, 1) + '\n');
      console.log(`  saved v=${version} ${date} (${label})`);
      continue;
    }

    if (!fs.existsSync(file)) {
      console.log(`  FAIL v=${version} ${date} — スナップショットが無い: ${path.relative(process.cwd(), file)}`);
      failures++;
      continue;
    }

    checked++;
    const expected = fs.readFileSync(file, 'utf8');
    const normalized = JSON.stringify(JSON.parse(actual), null, 1) + '\n';
    if (normalized === expected) {
      console.log(`  ok   v=${version} ${date} (${label})`);
    } else {
      failures++;
      const a = JSON.parse(actual);
      const b = JSON.parse(expected);
      const an = a.current.schedules.length;
      const bn = b.current.schedules.length;
      console.log(`  FAIL v=${version} ${date} (${label}) — 便数 期待=${bn} 実際=${an}`);
      // 最初の差分だけ出す。全部出すと読めない
      const max = Math.max(an, bn);
      for (let i = 0; i < max; i++) {
        const x = JSON.stringify(a.current.schedules[i]);
        const y = JSON.stringify(b.current.schedules[i]);
        if (x !== y) {
          console.log(`         [${i}] 期待: ${y}`);
          console.log(`         [${i}] 実際: ${x}`);
          break;
        }
      }
    }
  }
}

if (update) {
  console.log('\nスナップショットを更新した。差分を必ず目視で確認すること。');
  process.exit(0);
}

console.log(`\n${failures ? `不一致 ${failures}` : `全 ${checked} 件一致`}`);
process.exit(failures ? 1 : 0);
