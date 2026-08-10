/**
 * 千歳科学技術大学 シャトルバス時刻表 GAS バックエンド
 *
 * 事前準備:
 *   - Webアプリとしてデプロイ（アクセス: 全員）
 *
 * 時刻表はハードコードされており、doGet は外部 I/O なしで応答を組み立てる。
 * 意図的にキャッシュを持たない設計のため、再デプロイすれば即座に反映される。
 * かつては CacheService に6時間キャッシュしていたが、コードを更新しても
 * 旧データが配信され続ける事故が起きたため廃止した（Issue #153）。
 *
 * 便ごとに以下のフラグを持つ。
 *   weekdayOnly / weekendOnly … 平日のみ / 土日祝のみ
 *   academicOnly / vacationOnly … 授業期のみ / 学休期のみ（Issue #132）
 *
 * ---- スキーマバージョン（?v=）----
 *
 * GAS は Apps Script への手動デプロイ、アプリはストア審査を挟むリリースのため、
 * 両者の反映タイミングは必ずずれる。さらに更新しないユーザーの旧バージョンは
 * 永続的に残る。そこでリクエストの ?v= でレスポンス形式を出し分ける。
 *
 *   v=1（無指定を含む）… 期別も祝日も知らない旧アプリ向け。
 *                        サーバ側で当日の期別・運行日に絞り、期別フラグを取り除く。
 *   v=2 ……………………… 期別は分かるが祝日を知らないアプリ向け（v1.2.0）。
 *                        全便 + 期別フラグを返すが、祝日の日だけ運行日で絞る。
 *   v=3 ……………………… 期別・祝日ともに判定できるアプリ向け。全便 + 期別フラグ。
 *   v=4 ……………………… 任意の停留所を扱えるアプリ向け（#177）。応答の構造が変わり、
 *                        1便を1件として停留所と時刻の並びを返す。?stops= で絞れる。
 *
 * これによりデプロイ順を気にせず GAS を更新できる。
 *
 * ★ ?stops= は単なる絞り込みで、形式の分岐には使わない。「stops があれば新形式」に
 *   すると、アプリが stops を送らなかったとき（選択が空・不具合）に旧形式が返って壊れる。
 *
 * ★ v はレスポンスの「形式」ではなく、アプリが持つ判定ロジックの世代を表す。
 *   祝日判定（#158）のようにアプリ側の規則を後から足すと、既存の v はその規則を
 *   持たないため、サーバ側で吸収したうえで v を増やす必要がある。
 *   新しい v を足すときは、既存の v の挙動を変えないこと。
 */

// ---- 旧スクレイピング処理（コメントアウト） ----
/*
var CHITOSE_TOP_URL = 'https://www.chitose.ac.jp/info/access';
// URLエンコード済み「時刻表」= %E6%99%82%E5%88%BC%E8%A1%A8 を含むPDFを対象とする
var PDF_PATTERN_SRC = '\/uploads\/files\/[^"\'\\s]*%E6%99%82%E5%88%BC%E8%A1%A8[^"\'\\s]*\\.pdf';
// ファイル名末尾の _MMDD-MMDD.pdf 形式から有効期間を取得
var DATE_RANGE_PATTERN_FILENAME = /_(\d{2})(\d{2})-(\d{2})(\d{2})\.pdf/i;

function fetchAndParseTimetable() {
  var html = UrlFetchApp.fetch(CHITOSE_TOP_URL, { muteHttpExceptions: true }).getContentText('UTF-8');
  var re = new RegExp(PDF_PATTERN_SRC, 'gi');
  var pdfPaths = [];
  var m;
  while ((m = re.exec(html)) !== null) {
    if (pdfPaths.indexOf(m[0]) === -1) pdfPaths.push(m[0]);
  }
  if (pdfPaths.length === 0) throw new Error('時刻表PDFが見つかりませんでした');
  var today = Utilities.formatDate(new Date(), 'Asia/Tokyo', 'yyyy-MM-dd');
  var year = parseInt(today.substring(0, 4), 10);
  var timetables = pdfPaths.map(function(pdfPath) { return parsePdf(pdfPath, year, today); });
  timetables.sort(function(a, b) { return a.validFrom < b.validFrom ? -1 : 1; });
  var current = null, upcoming = null;
  for (var i = 0; i < timetables.length; i++) {
    var t = timetables[i];
    if (t.validFrom <= today && today <= t.validTo) current = t;
    else if (t.validFrom > today && !upcoming) upcoming = t;
  }
  if (!current && timetables.length > 0) current = timetables[0];
  return { updatedAt: today, current: current, upcoming: upcoming };
}

function parsePdf(pdfPath, year, today) {
  var pdfUrl = 'https://www.chitose.ac.jp' + pdfPath;
  var validFrom = '', validTo = '';
  var dateMatch = pdfPath.match(DATE_RANGE_PATTERN_FILENAME);
  if (dateMatch) {
    validFrom = year + '-' + pad(dateMatch[1]) + '-' + pad(dateMatch[2]);
    validTo   = year + '-' + pad(dateMatch[3]) + '-' + pad(dateMatch[4]);
  }
  var text = extractTextFromPdf(pdfUrl);
  var schedules = parseTimetableText(text);
  return { validFrom: validFrom, validTo: validTo, pdfUrl: pdfUrl, schedules: schedules };
}

function pad(n) { return String(parseInt(n, 10)).padStart(2, '0'); }

function extractTextFromPdf(pdfUrl) {
  var blob = UrlFetchApp.fetch(pdfUrl).getBlob().setContentType('application/pdf');
  var file = null;
  try {
    file = Drive.Files.create(
      { name: 'tmp_bus_timetable', mimeType: 'application/vnd.google-apps.document' },
      blob
    );
    var doc = DocumentApp.openById(file.id);
    return doc.getBody().getText();
  } finally {
    if (file) { try { Drive.Files.remove(file.id); } catch (e) {} }
  }
}

function parseTimetableText(text) {
  var lines = text.split(/\r?\n/);
  var schedules = [];
  var section = null;
  var pendingTimes = [];
  function flushTrip() {
    if (pendingTimes.length === 0 || !section) { pendingTimes = []; return; }
    if (section === 'outbound') {
      var kenkyutoTime = pendingTimes.length > 2 ? pendingTimes[2] : null;
      var honbutoTime  = pendingTimes.length > 3 ? pendingTimes[3] : null;
      var outboundArrivals = {};
      if (kenkyutoTime) outboundArrivals['kenkyuto'] = kenkyutoTime;
      if (honbutoTime)  outboundArrivals['honbuto']  = honbutoTime;
      if (pendingTimes.length > 0)
        schedules.push({ time: pendingTimes[0], direction: 'from_chitose',           destination: '千歳科学技術大学', arrivals: outboundArrivals });
      if (pendingTimes.length > 1)
        schedules.push({ time: pendingTimes[1], direction: 'from_minami_chitose',    destination: '千歳科学技術大学', arrivals: outboundArrivals });
      if (pendingTimes.length > 2) {
        var kenkyutoArrivals = {};
        if (honbutoTime) kenkyutoArrivals['honbuto'] = honbutoTime;
        schedules.push({ time: pendingTimes[2], direction: 'from_kenkyuto_to_honbuto', destination: '本部棟', arrivals: kenkyutoArrivals });
      }
    } else if (section === 'inbound') {
      if (pendingTimes.length > 0) {
        var honbutoArrivals = {};
        if (pendingTimes.length > 1) honbutoArrivals['kenkyuto']      = pendingTimes[1];
        if (pendingTimes.length > 2) honbutoArrivals['minamiChitose'] = pendingTimes[2];
        if (pendingTimes.length > 3) honbutoArrivals['chitose']       = pendingTimes[3];
        schedules.push({ time: pendingTimes[0], direction: 'from_honbuto', destination: '千歳駅', arrivals: honbutoArrivals });
      }
      if (pendingTimes.length > 1) {
        var kenkyutoStationArrivals = {};
        if (pendingTimes.length > 2) kenkyutoStationArrivals['minamiChitose'] = pendingTimes[2];
        if (pendingTimes.length > 3) kenkyutoStationArrivals['chitose']       = pendingTimes[3];
        schedules.push({ time: pendingTimes[1], direction: 'from_kenkyuto_to_station', destination: '千歳駅', arrivals: kenkyutoStationArrivals });
      }
    }
    pendingTimes = [];
  }
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim();
    if (/有料バス/.test(line)) break;
    if (/千歳駅発/.test(line)) { flushTrip(); section = 'outbound'; continue; }
    if (/本部棟発/.test(line)) { flushTrip(); section = 'inbound'; continue; }
    if (!section) continue;
    var timeMatch = line.match(/^(\d{1,2}):([0-5]\d)$/);
    if (timeMatch) {
      var hour = parseInt(timeMatch[1], 10);
      var minute = parseInt(timeMatch[2], 10);
      if (hour >= 6 && hour <= 22) pendingTimes.push(pad(hour) + ':' + pad(minute));
    } else if (line === '') {
      flushTrip();
    }
  }
  flushTrip();
  schedules.sort(function(a, b) {
    if (a.direction !== b.direction) return a.direction < b.direction ? -1 : 1;
    return a.time < b.time ? -1 : 1;
  });
  return schedules;
}

function testFetch() {
  var result = fetchAndParseTimetable();
  Logger.log(JSON.stringify(result, null, 2));
}

function testFindPdfLinks() {
  var html = UrlFetchApp.fetch(CHITOSE_TOP_URL, { muteHttpExceptions: true }).getContentText('UTF-8');
  var allPdfs = html.match(/\/uploads\/files\/[^"'\s]*\.pdf/gi) || [];
  Logger.log('全PDFリンク数: ' + allPdfs.length);
  allPdfs.forEach(function(p) { Logger.log(p); });
  var re = new RegExp(PDF_PATTERN_SRC, 'gi');
  var m;
  Logger.log('--- 時刻表PDF ---');
  while ((m = re.exec(html)) !== null) Logger.log(m[0]);
}

function testPdfText() {
  var html = UrlFetchApp.fetch(CHITOSE_TOP_URL, { muteHttpExceptions: true }).getContentText('UTF-8');
  var re = new RegExp(PDF_PATTERN_SRC, 'i');
  var match = html.match(re);
  if (!match) { Logger.log('PDFが見つかりません'); return; }
  var pdfUrl = 'https://www.chitose.ac.jp' + match[0];
  Logger.log('URL: ' + pdfUrl);
  var text = extractTextFromPdf(pdfUrl);
  Logger.log('=== PDF生テキスト ===');
  Logger.log(text.substring(0, 3000));
}
*/

function doGet(e) {
  try {
    var v = requestedSchemaVersion(e);

    // v>=4 は停留所を選べる新形式。旧バージョンとは応答の構造が違うので
    // 先に分岐する（?stops= の有無では分岐しない — 下の buildStopsResponse 参照）
    if (v >= 4) {
      return buildResponse(JSON.stringify(buildStopsResponse(requestedStops(e))));
    }

    var result = getHardcodedTimetable();
    if (v < 2) {
      result = toLegacyResponse(result);
    } else if (v < 3) {
      result = toV2Response(result);
    }
    return buildResponse(JSON.stringify(result));
  } catch (err) {
    return ContentService
      .createTextOutput(JSON.stringify({ error: err.message || String(err) }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

/** リクエストの ?v= を読む。未指定・不正値は 1（旧形式）として扱う。 */
function requestedSchemaVersion(e) {
  if (!e || !e.parameter || !e.parameter.v) return 1;
  var v = parseInt(e.parameter.v, 10);
  return isNaN(v) ? 1 : v;
}

/**
 * リクエストの ?stops= を読む。カンマ区切りの停留所 ID。
 *
 * 未指定なら null を返し、呼び出し側は全停留所を返す。
 * 知らない ID は黙って捨てる。アプリが新しい停留所を知らないまま古い選択を
 * 送ってくる場合があり、エラーにすると時刻表が全く出せなくなるため。
 */
function requestedStops(e) {
  if (!e || !e.parameter || !e.parameter.stops) return null;
  var raw = String(e.parameter.stops).split(',');

  // Object.create(null) にすること。素の {} だと known['toString'] が
  // Object.prototype のメンバを拾って truthy になり、実在しない停留所を
  // 指定できてしまう（結果として全便が0停留所になり時刻表が空になる）
  var known = Object.create(null);
  STOPS.forEach(function(s) { known[s.id] = true; });

  var wanted = Object.create(null);
  var count = 0;
  raw.forEach(function(id) {
    id = id.trim();
    if (id && known[id] && !wanted[id]) { wanted[id] = true; count++; }
  });
  // 全部が未知だった場合も全停留所として扱う（空の時刻表を返さない）
  return count === 0 ? null : wanted;
}

/**
 * v=1（期別を知らない旧アプリ）向けにレスポンスを変換する。
 *
 * 旧アプリは academicOnly / vacationOnly を無視するため、全便をそのまま返すと
 * 授業期と学休期の便が混ざって表示される（学休期の千歳駅発が 14便 → 33便になる）。
 * そのためサーバ側で当日の期別に絞り、期別フラグを取り除いて返す。
 *
 * 祝日も同様にサーバ側で処理する（Issue #158）。旧アプリの DayType.fromDate は
 * 土日しか見ないため、祝日には土日祝ダイヤの便だけを返したうえで
 * weekdayOnly / weekendOnly を落とし、アプリ側の曜日判定を通り抜けさせる。
 */
function toLegacyResponse(result) {
  var ymd = parseYmd(result.updatedAt);
  var current = result.current;

  // 年末年始は全便運休。旧アプリはこれを判定できないため空で返す
  if (isSuspendedYmd(ymd)) {
    return {
      updatedAt: result.updatedAt,
      current: {
        validFrom: current.validFrom,
        validTo: current.validTo,
        schedules: []
      },
      upcoming: null
    };
  }

  var season = seasonForYmd(ymd);
  var dayType = dayTypeForYmd(ymd);
  // 平日に当たる祝日のみ、アプリ側の曜日判定と食い違う。
  // このときだけ運行日フラグを落として絞り込み済みの結果を渡す。
  var dow = new Date(Date.UTC(ymd.y, ymd.m - 1, ymd.d)).getUTCDay();
  var isHolidayOnWeekday = dayType === 'weekendHoliday' && dow !== 0 && dow !== 6;

  var schedules = current.schedules
    .filter(function(en) {
      if (season === 'vacation' && en.academicOnly) return false;
      if (season === 'academic' && en.vacationOnly) return false;
      if (dayType === 'weekendHoliday' && en.weekdayOnly) return false;
      if (dayType === 'weekday' && en.weekendOnly) return false;
      return true;
    })
    .map(stripSeasonFlags)
    .map(isHolidayOnWeekday ? stripDayFlags : identity);

  return {
    updatedAt: result.updatedAt,
    current: {
      validFrom: current.validFrom,
      validTo: current.validTo,
      schedules: schedules
    },
    upcoming: result.upcoming
  };
}

/**
 * v=2（期別は分かるが祝日を知らないアプリ）向けにレスポンスを変換する。
 *
 * v=2 を送るのは v1.2.0 以降だが、祝日判定（Issue #158）は v1.2.0 より後に
 * 入ったため、v1.2.0 の DayType.fromDate は土日しか見ない。全便をそのまま返すと
 * 平日に当たる祝日で平日ダイヤが表示される（8/11 の千歳駅発が 5便 → 14便）。
 *
 * ?v= はレスポンスの「形式」を表すもので、クライアントが持つ判定ロジックの
 * 世代ではない。祝日のようにアプリ側の規則を後から足した場合、既存の v は
 * その規則を持たないため、サーバ側で吸収する必要がある。
 *
 * 祝日の日だけ運行日で絞ってフラグを落とす。期別フラグは残すので、
 * 学休期の絞り込みは従来どおりアプリ側で動く。
 * 平日・土日は変換せず、そのまま全便を返す（当日以外のダイヤ表示のため）。
 */
function toV2Response(result) {
  var ymd = parseYmd(result.updatedAt);
  var dow = new Date(Date.UTC(ymd.y, ymd.m - 1, ymd.d)).getUTCDay();
  var dayType = dayTypeForYmd(ymd);
  if (!(dayType === 'weekendHoliday' && dow !== 0 && dow !== 6)) {
    return result;
  }

  var current = result.current;
  return {
    updatedAt: result.updatedAt,
    current: {
      validFrom: current.validFrom,
      validTo: current.validTo,
      schedules: current.schedules
        .filter(function(en) { return !en.weekdayOnly; })
        .map(stripDayFlags)
    },
    upcoming: result.upcoming
  };
}

function stripSeasonFlags(entry) {
  var out = {};
  for (var k in entry) {
    if (k === 'academicOnly' || k === 'vacationOnly') continue;
    out[k] = entry[k];
  }
  return out;
}

/**
 * 運行日フラグを落とす（平日に当たる祝日でのみ使う）。
 *
 * 旧アプリは祝日を平日として扱うため、weekendOnly が付いた便を捨ててしまう。
 * サーバ側で絞り込み済みの結果を「毎日運行」として渡すことで、
 * アプリ側の曜日判定に関係なく正しい便が表示される。
 */
function stripDayFlags(entry) {
  var out = {};
  for (var k in entry) {
    if (k === 'weekdayOnly' || k === 'weekendOnly') continue;
    out[k] = entry[k];
  }
  out.weekdayOnly = false;
  out.weekendOnly = false;
  return out;
}

function identity(x) {
  return x;
}

function buildResponse(jsonString) {
  return ContentService
    .createTextOutput(jsonString)
    .setMimeType(ContentService.MimeType.JSON);
}

function doPost(e) {
  try {
    var data = JSON.parse(e.postData.contents);
    var category = data.category || '';
    var description = data.description || '';
    var steps = data.steps || '';

    if (!description) {
      return ContentService
        .createTextOutput(JSON.stringify({ error: 'description is required' }))
        .setMimeType(ContentService.MimeType.JSON);
    }

    var now = Utilities.formatDate(new Date(), 'Asia/Tokyo', 'yyyy-MM-dd HH:mm:ss');
    var props = PropertiesService.getScriptProperties();

    var sheetId = props.getProperty('BUG_REPORT_SHEET_ID');
    if (sheetId) {
      var sheet = SpreadsheetApp.openById(sheetId).getSheets()[0];
      sheet.appendRow([now, category, description, steps]);
    }

    var notifyEmail = props.getProperty('BUG_REPORT_NOTIFY_EMAIL');
    if (notifyEmail) {
      var subject = '[Kagi-Bus] お問い合わせが届きました';
      var body = '日時: ' + now + '\n\n種類: ' + (category || '（未選択）') + '\n\nお問い合わせ内容:\n' + description + '\n\n詳細:\n' + (steps || '（未入力）');
      var mailOptions = {};
      var fromEmail = props.getProperty('BUG_REPORT_FROM_EMAIL');
      if (fromEmail) mailOptions.from = fromEmail;
      GmailApp.sendEmail(notifyEmail, subject, body, mailOptions);
    }

    return ContentService
      .createTextOutput(JSON.stringify({ success: true }))
      .setMimeType(ContentService.MimeType.JSON);
  } catch (err) {
    return ContentService
      .createTextOutput(JSON.stringify({ error: err.message || String(err) }))
      .setMimeType(ContentService.MimeType.JSON);
  }
}

// ---- 期別・特例日の判定（v=1 向けのサーバ側絞り込み用）----
//
// アプリ側 SeasonType.fromDate / ServiceCalendar.isSuspended と同一のロジック。
// 片方だけ変更すると v=1 と v=2 で結果が食い違うため、必ず両方を揃えること。
// 境界値は flutter_app/test/unit/domain/season_type_test.dart と
// scripts/check_gas_season.js が担保している。
//
// 日付は JST の 'yyyy-MM-dd' 文字列から取り出し、比較は UTC で行う。
// GAS のスクリプトタイムゾーンに依存させないため。

/** 'yyyy-MM-dd' → { y, m, d }（m は 1 始まり） */
function parseYmd(dateString) {
  return {
    y: parseInt(dateString.substring(0, 4), 10),
    m: parseInt(dateString.substring(5, 7), 10),
    d: parseInt(dateString.substring(8, 10), 10)
  };
}

/**
 * year年month月の第n【weekday】曜日を UTC ミリ秒で返す。
 * weekday は Dart の DateTime.weekday に合わせて 1=月 … 7=日。
 */
function nthWeekdayUtc(year, month, weekday, n) {
  var firstDow = new Date(Date.UTC(year, month - 1, 1)).getUTCDay(); // 0=日
  var firstWeekday = firstDow === 0 ? 7 : firstDow;
  var offset = (weekday - firstWeekday + 7) % 7;
  return Date.UTC(year, month - 1, 1 + offset + (n - 1) * 7);
}

/**
 * 期別を返す（'academic' | 'vacation'）。
 * - 夏季: 8月第1月曜日 〜 9月第4金曜日
 * - 冬季: 2月第1月曜日 〜 3月31日
 * - お盆: 8/13 〜 8/16
 */
function seasonForYmd(ymd) {
  var day = Date.UTC(ymd.y, ymd.m - 1, ymd.d);

  // お盆（夏季学休期に内包されるが、PDF に明記されているため独立して判定する）
  if (ymd.m === 8 && ymd.d >= 13 && ymd.d <= 16) return 'vacation';

  var summerFrom = nthWeekdayUtc(ymd.y, 8, 1, 1); // 8月第1月曜日
  var summerTo   = nthWeekdayUtc(ymd.y, 9, 5, 4); // 9月第4金曜日
  if (day >= summerFrom && day <= summerTo) return 'vacation';

  var winterFrom = nthWeekdayUtc(ymd.y, 2, 1, 1); // 2月第1月曜日
  var winterTo   = Date.UTC(ymd.y, 2, 31);        // 3月31日
  if (day >= winterFrom && day <= winterTo) return 'vacation';

  return 'academic';
}

/** 年末年始（12/31 〜 1/3）は全便運休 */
function isSuspendedYmd(ymd) {
  return (ymd.m === 12 && ymd.d === 31) || (ymd.m === 1 && ymd.d <= 3);
}

/**
 * 「祝日だが平日ダイヤで運行する」日（時刻表 PDF 注記より）
 *
 * > 以下の日付は、祝日ですが、平日ダイヤでの運行となりますので、ご留意ください。
 * > 【対象日】 4/29・7/20・10/12・11/3・11/23
 *
 * これらは祝日でも weekday として扱う。7/20（海の日）と 10/12（スポーツの日）は
 * ハッピーマンデーで日付が動くが、PDF が固定日で列挙しているためそれに従う。
 */
function isWeekdayScheduleHoliday(ymd) {
  var md = ymd.m * 100 + ymd.d;
  return md === 429 || md === 720 || md === 1012 || md === 1103 || md === 1123;
}

/**
 * 日本の祝日か（振替休日・国民の休日を含む）。
 *
 * 外部 API に依存すると GAS の実行時間とクォータを消費し、障害時に
 * 時刻表全体が返せなくなるため、計算で求める。
 * 春分・秋分は天文学的な近似式を使う（2150年まで有効）。
 */
function isJapaneseHoliday(ymd) {
  return holidayNameOf(ymd.y, ymd.m, ymd.d) !== null;
}

/** 祝日名を返す（祝日でなければ null）。テストで判定根拠を確認できるようにしている。 */
function holidayNameOf(y, m, d) {
  var name = fixedOrHappyMondayHoliday(y, m, d);
  if (name) return name;

  // 振替休日: 直前の日曜が祝日で、そこから連続して祝日が続く場合
  // （例: 日曜が祝日 → 月曜が振替休日）
  var dow = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
  if (dow !== 0) {
    var prev = new Date(Date.UTC(y, m - 1, d));
    while (true) {
      prev.setUTCDate(prev.getUTCDate() - 1);
      var pm = prev.getUTCMonth() + 1, pd = prev.getUTCDate();
      if (!fixedOrHappyMondayHoliday(prev.getUTCFullYear(), pm, pd)) break;
      if (prev.getUTCDay() === 0) return '振替休日';
    }
  }

  // 国民の休日: 前日と翌日がともに祝日で、自身は祝日でない平日
  // （例: 9/21 敬老の日・9/23 秋分の日 に挟まれた 9/22）
  if (dow !== 0 && dow !== 6) {
    var before = new Date(Date.UTC(y, m - 1, d - 1));
    var after = new Date(Date.UTC(y, m - 1, d + 1));
    if (fixedOrHappyMondayHoliday(before.getUTCFullYear(), before.getUTCMonth() + 1, before.getUTCDate()) &&
        fixedOrHappyMondayHoliday(after.getUTCFullYear(), after.getUTCMonth() + 1, after.getUTCDate())) {
      return '国民の休日';
    }
  }

  return null;
}

/** 固定日・ハッピーマンデー・春分秋分の祝日（振替休日と国民の休日は含まない） */
function fixedOrHappyMondayHoliday(y, m, d) {
  var dow = new Date(Date.UTC(y, m - 1, d)).getUTCDay(); // 0=日 1=月
  var nth = Math.floor((d - 1) / 7) + 1;                 // 第n週

  if (m === 1 && d === 1) return '元日';
  if (m === 1 && dow === 1 && nth === 2) return '成人の日';
  if (m === 2 && d === 11) return '建国記念の日';
  if (m === 2 && d === 23) return '天皇誕生日';
  if (m === 3 && d === vernalEquinoxDay(y)) return '春分の日';
  if (m === 4 && d === 29) return '昭和の日';
  if (m === 5 && d === 3) return '憲法記念日';
  if (m === 5 && d === 4) return 'みどりの日';
  if (m === 5 && d === 5) return 'こどもの日';
  if (m === 7 && dow === 1 && nth === 3) return '海の日';
  if (m === 8 && d === 11) return '山の日';
  if (m === 9 && dow === 1 && nth === 3) return '敬老の日';
  if (m === 9 && d === autumnalEquinoxDay(y)) return '秋分の日';
  if (m === 10 && dow === 1 && nth === 2) return 'スポーツの日';
  if (m === 11 && d === 3) return '文化の日';
  if (m === 11 && d === 23) return '勤労感謝の日';
  return null;
}

/** 春分の日（1900〜2150年で有効な近似式） */
function vernalEquinoxDay(y) {
  return Math.floor(20.8431 + 0.242194 * (y - 1980) - Math.floor((y - 1980) / 4));
}

/** 秋分の日（1900〜2150年で有効な近似式） */
function autumnalEquinoxDay(y) {
  return Math.floor(23.2488 + 0.242194 * (y - 1980) - Math.floor((y - 1980) / 4));
}

/**
 * その日の運行日区分を返す（'weekday' | 'weekendHoliday'）。
 *
 * 土日、および祝日は土日祝ダイヤ。ただし PDF が「平日ダイヤで運行」と明記する
 * 5日（4/29・7/20・10/12・11/3・11/23）は祝日でも平日ダイヤ。
 */
function dayTypeForYmd(ymd) {
  var dow = new Date(Date.UTC(ymd.y, ymd.m - 1, ymd.d)).getUTCDay();
  if (dow === 0 || dow === 6) return 'weekendHoliday';
  if (isWeekdayScheduleHoliday(ymd)) return 'weekday';
  if (isJapaneseHoliday(ymd)) return 'weekendHoliday';
  return 'weekday';
}

// ---- ハードコード時刻表 ----

/**
 * 停留所の一覧（路線上のおおよその並び順）。
 *
 * 名称は大学配付物「美々空港線」に準拠する。
 *
 * shortLabel はタブなど幅の狭い場所で使う短縮名。**略称を勝手に作らないこと。**
 * アプリが以前から短い名前で表示していた4停留所にだけ付けてある。
 * 出典の無い略称を発明すると、利用者が実際のバス停の表記と対応付けられなくなる。
 *
 * 千歳市の PDF を一次情報にしないこと。空17・空18 の表が画像で、
 * pdftotext で読めず目視に頼ることになる。実際に #159 で誤読した
 * （詳細は系統1復路のコメント）。
 */
var STOPS = [
  { id: 'osatsu', label: '長都駅東口' },
  { id: 'arcs', label: 'アークス前' },
  { id: 'isamai7', label: '勇舞7丁目' },
  { id: 'isamaiPark', label: '勇舞公園前' },
  { id: 'isamaiJhs', label: '勇舞中学校前' },
  { id: 'isamai2', label: '勇舞2丁目' },
  { id: 'alice', label: 'アリスこども園前' },
  { id: 'hokuyoHs', label: '北陽高校前' },
  { id: 'hokuyo3', label: '北陽3丁目' },
  { id: 'hokko6', label: '北光6丁目' },
  { id: 'fuji4', label: '富士4丁目' },
  { id: 'shinano4', label: '信濃4丁目' },
  { id: 'yao', label: '矢尾外科胃腸科前' },
  { id: 'hoyukai', label: '千歳豊友会病院前' },
  { id: 'hokuei2', label: '北栄2丁目' },
  { id: 'aeon', label: 'イオン千歳店前' },
  { id: 'chitose', label: '千歳駅前', shortLabel: '千歳駅' },
  { id: 'morimoto', label: 'もりもと本店前' },
  { id: 'koizumi', label: '古泉循環器内科クリニック前' },
  { id: 'shiyakusho', label: '市役所前' },
  { id: 'asahicho4', label: '朝日町4丁目' },
  { id: 'asahicho7', label: '朝日町7丁目' },
  { id: 'arcadia', label: 'オフィス・アルカディア入口' },
  { id: 'minamiChitose', label: '南千歳駅', shortLabel: '南千歳' },
  { id: 'airCargo', label: 'エアカーゴ前' },
  { id: 'domestic28', label: '空港国内線28番' },
  { id: 'domestic1', label: '空港国内線1番' },
  { id: 'international85', label: '空港国際線85番' },
  { id: 'kenkyuto', label: '科技大研究棟', shortLabel: '研究棟' },
  { id: 'honbuto', label: '科技大本部棟', shortLabel: '本部棟' },
  { id: 'rapidus', label: 'ラピダス前', boardable: false },
];

/**
 * 便の一覧。
 *
 * stops は「その便が通る停留所」の並びで、times は同じ並びの時刻。
 * 運行日: B=毎日 / D=平日のみ / E=土日祝のみ
 * 期別:   ''=授業期・学休期共通 / A=授業期のみ / V=学休期のみ
 *
 * direction は旧形式へ展開する際の乗車地の選び方を決める（LEGACY_BOARDING）。
 * destination は表示用の文字列なので、分岐の条件には使わないこと。
 *
 * データは大学配付物 PDF（授業期・学休期修正版）から機械抽出し、
 * 抽出前の4停留所分と突き合わせて全60便の一致を確認している（#177）。
 */
var ROUTES = [
  /*
   * 系統1 往路（千歳駅5番乗り場 → 空港経由 → 科技大）
   *
   * 授業期・学休期で時刻・運行日ともに同一のため、期別フラグは立てない。
   * 両 PDF の共通停留所91時刻が一致することを確認済み（#177）。
   * （学休期は 13:20 便が平日／土日祝の2行に分かれるが、合わせて毎日運行で等価）
   */
  {
    direction: 'outbound',
    routeLabel: '空港経由', destination: '科技大',
    platform: { chitose: '5番' },
    stops: ['chitose', 'morimoto', 'koizumi', 'shiyakusho', 'asahicho4', 'asahicho7', 'minamiChitose', 'airCargo', 'domestic28', 'domestic1', 'international85', 'kenkyuto', 'honbuto', 'rapidus'],
    trips: [
      ['B', '', ['07:20', '07:23', '07:24', '07:25', '07:26', '07:27', '07:31', '07:32', '07:33', '07:34', '07:37', '07:44', '07:45', '07:48']],
      ['E', '', ['08:18', '08:21', '08:22', '08:23', '08:24', '08:25', '08:29', '08:30', '08:31', '08:32', '08:35', '08:42', '08:43', '08:46']],
      ['E', '', ['09:10', '09:13', '09:14', '09:15', '09:16', '09:17', '09:21', '09:22', '09:23', '09:24', '09:27', '09:34', '09:35', '09:38']],
      ['D', '', ['10:30', '10:33', '10:34', '10:35', '10:36', '10:37', '10:41', '10:42', '10:43', '10:44', '10:47', '10:54', '10:55', '10:58']],
      ['D', '', ['11:00', '11:03', '11:04', '11:05', '11:06', '11:07', '11:11', '11:12', '11:13', '11:14', '11:17', '11:24', '11:25', '11:28']],
      ['D', '', ['12:10', '12:13', '12:14', '12:15', '12:16', '12:17', '12:21', '12:22', '12:23', '12:24', '12:27', '12:34', '12:35', '12:38']],
      ['B', '', ['13:20', '13:23', '13:24', '13:25', '13:26', '13:27', '13:31', '13:32', '13:33', '13:34', '13:37', '13:44', '13:45', '13:48']],
    ],
  },
  /*
   * 系統1 復路（科技大 → 空港経由 → 千歳駅）
   *
   * 全10便が南千歳駅を経由する。大学配付物「美々空港線 学休期ダイヤ（修正版）」
   * 02 科技大 ▶ 空港経由 ▶ 千歳駅行き で確認済み。
   *
   * 【消さないこと】千歳市の PDF はこの南千歳駅のセルが黒塗りに見えるが、
   * これは「通過」を意味しない。実際に通過と誤読して該当の到着時刻を削除し、
   * 本番に出してしまった（#159／PR #176 で差し戻し済み）。
   * 大学版では 11:51 / 12:57 / 13:50 / 14:47 / 15:39 / 17:02 / 18:07 / 19:17 /
   * 19:57 / 21:37 と切れ目なく並んでおり、こちらを正とする。
   *
   * 期別フラグは立てない。両 PDF の共通停留所140時刻が一致することを確認済み（#177）。
   */
  {
    direction: 'inbound',
    routeLabel: '空港経由', destination: '千歳駅',
    stops: ['rapidus', 'honbuto', 'kenkyuto', 'domestic28', 'domestic1', 'international85', 'airCargo', 'minamiChitose', 'asahicho7', 'asahicho4', 'shiyakusho', 'koizumi', 'morimoto', 'chitose'],
    trips: [
      ['D', '', ['11:34', '11:36', '11:39', '11:46', '11:47', '11:48', '11:50', '11:51', '11:54', '11:55', '11:56', '11:57', '11:58', '12:02']],
      ['E', '', ['12:40', '12:42', '12:45', '12:52', '12:53', '12:54', '12:56', '12:57', '13:00', '13:01', '13:02', '13:03', '13:04', '13:08']],
      ['D', '', ['13:33', '13:35', '13:38', '13:45', '13:46', '13:47', '13:49', '13:50', '13:53', '13:54', '13:55', '13:56', '13:57', '14:01']],
      ['E', '', ['14:30', '14:32', '14:35', '14:42', '14:43', '14:44', '14:46', '14:47', '14:50', '14:51', '14:52', '14:53', '14:54', '14:58']],
      ['B', '', ['15:22', '15:24', '15:27', '15:34', '15:35', '15:36', '15:38', '15:39', '15:42', '15:43', '15:44', '15:45', '15:46', '15:50']],
      ['B', '', ['16:45', '16:47', '16:50', '16:57', '16:58', '16:59', '17:01', '17:02', '17:05', '17:06', '17:07', '17:08', '17:09', '17:13']],
      ['B', '', ['17:50', '17:52', '17:55', '18:02', '18:03', '18:04', '18:06', '18:07', '18:10', '18:11', '18:12', '18:13', '18:14', '18:18']],
      ['B', '', ['19:00', '19:02', '19:05', '19:12', '19:13', '19:14', '19:16', '19:17', '19:20', '19:21', '19:22', '19:23', '19:24', '19:28']],
      ['D', '', ['19:40', '19:42', '19:45', '19:52', '19:53', '19:54', '19:56', '19:57', '20:00', '20:01', '20:02', '20:03', '20:04', '20:08']],
      ['D', '', ['21:20', '21:22', '21:25', '21:32', '21:33', '21:34', '21:36', '21:37', '21:40', '21:41', '21:42', '21:43', '21:44', '21:48']],
    ],
  },
  /*
   * 系統2 往路（千歳駅3番乗り場 → 直通 → 科技大）授業期
   *
   * 全便が平日のみ運行（土日祝の運行なし）。
   * 授業期（19便）と学休期（6便）で時刻が全く異なるため、別の便として登録し
   * academicOnly / vacationOnly で出し分ける。
   */
  {
    direction: 'outbound',
    routeLabel: '直通', destination: '科技大',
    platform: { chitose: '3番' },
    stops: ['chitose', 'morimoto', 'koizumi', 'shiyakusho', 'asahicho4', 'asahicho7', 'arcadia', 'kenkyuto', 'honbuto', 'rapidus'],
    trips: [
      ['D', 'A', ['07:14', '07:17', '07:18', '07:19', '07:20', '07:21', '07:25', '07:32', '07:35', '07:38']],
      ['D', 'A', ['07:29', '07:32', '07:33', '07:34', '07:35', '07:36', '07:40', '07:47', '07:50', '07:53']],
      ['D', 'A', ['08:04', '08:07', '08:08', '08:09', '08:10', '08:11', '08:15', '08:22', '08:25', '08:28']],
      ['D', 'A', ['08:14', '08:17', '08:18', '08:19', '08:20', '08:21', '08:25', '08:32', '08:35', '08:38']],
      ['D', 'A', ['08:19', '08:22', '08:23', '08:24', '08:25', '08:26', '08:30', '08:37', '08:40', '08:43']],
      ['D', 'A', ['08:24', '08:27', '08:28', '08:29', '08:30', '08:31', '08:35', '08:42', '08:45', '08:48']],
      ['D', 'A', ['08:29', '08:32', '08:33', '08:34', '08:35', '08:36', '08:40', '08:47', '08:50', '08:53']],
      ['D', 'A', ['09:04', '09:07', '09:08', '09:09', '09:10', '09:11', '09:15', '09:22', '09:25', '09:28']],
      ['D', 'A', ['09:19', '09:22', '09:23', '09:24', '09:25', '09:26', '09:30', '09:37', '09:40', '09:43']],
      ['D', 'A', ['09:34', '09:37', '09:38', '09:39', '09:40', '09:41', '09:45', '09:52', '09:55', '09:58']],
      ['D', 'A', ['09:44', '09:47', '09:48', '09:49', '09:50', '09:51', '09:55', '10:02', '10:05', '10:08']],
      ['D', 'A', ['09:54', '09:57', '09:58', '09:59', '10:00', '10:01', '10:05', '10:12', '10:15', '10:18']],
      ['D', 'A', ['10:04', '10:07', '10:08', '10:09', '10:10', '10:11', '10:15', '10:22', '10:25', '10:28']],
      ['D', 'A', ['10:14', '10:17', '10:18', '10:19', '10:20', '10:21', '10:25', '10:32', '10:35', '10:38']],
      ['D', 'A', ['14:24', '14:27', '14:28', '14:29', '14:30', '14:31', '14:35', '14:42', '14:45', '14:48']],
      ['D', 'A', ['15:22', '15:25', '15:26', '15:27', '15:28', '15:29', '15:33', '15:40', '15:43', '15:46']],
      ['D', 'A', ['15:55', '15:58', '15:59', '16:00', '16:01', '16:02', '16:06', '16:13', '16:16', '16:19']],
      ['D', 'A', ['16:04', '16:07', '16:08', '16:09', '16:10', '16:11', '16:15', '16:22', '16:25', '16:28']],
      ['D', 'A', ['17:51', '17:54', '17:55', '17:56', '17:57', '17:58', '18:02', '18:09', '18:12', '18:15']],
    ],
  },
  /*
   * 系統2 往路（千歳駅3番乗り場 → 直通 → 科技大）学休期
   *
   * 学休期 PDF は「※『ラピダス前』のダイヤは省略しています」と明記しており、
   * 往路のラピダス前の時刻が載っていない。推測で補わず、持たせていない。
   */
  {
    direction: 'outbound',
    routeLabel: '直通', destination: '科技大',
    platform: { chitose: '3番' },
    stops: ['chitose', 'morimoto', 'koizumi', 'shiyakusho', 'asahicho4', 'asahicho7', 'arcadia', 'kenkyuto', 'honbuto'],
    trips: [
      ['D', 'V', ['08:10', '08:13', '08:14', '08:15', '08:16', '08:17', '08:21', '08:28', '08:31']],
      ['D', 'V', ['08:40', '08:43', '08:44', '08:45', '08:46', '08:47', '08:51', '08:58', '09:01']],
      ['D', 'V', ['09:10', '09:13', '09:14', '09:15', '09:16', '09:17', '09:21', '09:28', '09:31']],
      ['D', 'V', ['09:50', '09:53', '09:54', '09:55', '09:56', '09:57', '10:01', '10:08', '10:11']],
      ['D', 'V', ['16:00', '16:03', '16:04', '16:05', '16:06', '16:07', '16:11', '16:18', '16:21']],
      ['D', 'V', ['18:00', '18:03', '18:04', '18:05', '18:06', '18:07', '18:11', '18:18', '18:21']],
    ],
  },
  /*
   * 系統2 復路（科技大 → 直通 → 千歳駅）授業期
   *
   * 全便が平日のみ運行。直通のため南千歳駅は経由しない。
   */
  {
    direction: 'inbound',
    routeLabel: '直通', destination: '千歳駅',
    stops: ['rapidus', 'honbuto', 'kenkyuto', 'arcadia', 'asahicho7', 'asahicho4', 'shiyakusho', 'koizumi', 'morimoto', 'chitose'],
    trips: [
      ['D', 'A', ['11:00', '11:02', '11:05', '11:12', '11:16', '11:17', '11:18', '11:19', '11:20', '11:24']],
      ['D', 'A', ['12:25', '12:27', '12:30', '12:37', '12:41', '12:42', '12:43', '12:44', '12:45', '12:49']],
      ['D', 'A', ['13:05', '13:07', '13:10', '13:17', '13:21', '13:22', '13:23', '13:24', '13:25', '13:29']],
      ['D', 'A', ['14:15', '14:17', '14:20', '14:27', '14:31', '14:32', '14:33', '14:34', '14:35', '14:39']],
      ['D', 'A', ['15:00', '15:02', '15:05', '15:12', '15:16', '15:17', '15:18', '15:19', '15:20', '15:24']],
      ['D', 'A', ['16:40', '16:42', '16:45', '16:52', '16:56', '16:57', '16:58', '16:59', '17:00', '17:04']],
      ['D', 'A', ['17:00', '17:02', '17:05', '17:12', '17:16', '17:17', '17:18', '17:19', '17:20', '17:24']],
      ['D', 'A', ['17:28', '17:30', '17:33', '17:40', '17:44', '17:45', '17:46', '17:47', '17:48', '17:52']],
      ['D', 'A', ['18:25', '18:27', '18:30', '18:37', '18:41', '18:42', '18:43', '18:44', '18:45', '18:49']],
    ],
  },
  /*
   * 系統2 復路（科技大 → 直通 → 千歳駅）学休期
   */
  {
    direction: 'inbound',
    routeLabel: '直通', destination: '千歳駅',
    stops: ['rapidus', 'honbuto', 'kenkyuto', 'arcadia', 'asahicho7', 'asahicho4', 'shiyakusho', 'koizumi', 'morimoto', 'chitose'],
    trips: [
      ['D', 'V', ['12:30', '12:32', '12:35', '12:42', '12:46', '12:47', '12:48', '12:49', '12:50', '12:54']],
      ['D', 'V', ['14:30', '14:32', '14:35', '14:42', '14:46', '14:47', '14:48', '14:49', '14:50', '14:54']],
      ['D', 'V', ['17:30', '17:32', '17:35', '17:42', '17:46', '17:47', '17:48', '17:49', '17:50', '17:54']],
      ['D', 'V', ['18:30', '18:32', '18:35', '18:42', '18:46', '18:47', '18:48', '18:49', '18:50', '18:54']],
    ],
  },
  /*
   * 系統3 往路（長都駅東口 → 千歳駅5番 → 空港経由 → 科技大）
   *
   * バスは長都駅東口発だが、旧形式では千歳駅前（5番）を乗車起点として扱う。
   * platform を千歳駅に付けているのはそのため。
   *
   * 期別フラグは立てない。両 PDF の共通停留所45時刻が一致することを確認済み（#177）。
   * 学休期 PDF は途中の停留所を15個しか載せていないが、両端と途中の時刻が
   * 完全に一致するため表記の省略であり、経路の違いではない。
   */
  {
    direction: 'outbound',
    routeLabel: '長都発', destination: '科技大',
    platform: { chitose: '5番' },
    stops: ['osatsu', 'arcs', 'isamai7', 'isamaiPark', 'isamaiJhs', 'isamai2', 'alice', 'hokuyoHs', 'hokuyo3', 'hokko6', 'fuji4', 'shinano4', 'yao', 'hoyukai', 'hokuei2', 'aeon', 'chitose', 'morimoto', 'koizumi', 'shiyakusho', 'asahicho4', 'asahicho7', 'minamiChitose', 'airCargo', 'domestic28', 'domestic1', 'international85', 'kenkyuto', 'honbuto', 'rapidus'],
    trips: [
      ['B', '', ['11:10', '11:11', '11:12', '11:12', '11:13', '11:14', '11:15', '11:16', '11:16', '11:17', '11:18', '11:19', '11:20', '11:21', '11:22', '11:23', '11:29', '11:32', '11:33', '11:34', '11:35', '11:36', '11:40', '11:41', '11:42', '11:43', '11:46', '11:53', '11:54', '12:02']],
      ['D', '', ['12:00', '12:01', '12:02', '12:02', '12:03', '12:04', '12:05', '12:06', '12:06', '12:07', '12:08', '12:09', '12:10', '12:11', '12:12', '12:13', '12:19', '12:22', '12:23', '12:24', '12:25', '12:26', '12:30', '12:31', '12:32', '12:33', '12:36', '12:43', '12:44', '12:52']],
      ['D', '', ['14:10', '14:11', '14:12', '14:12', '14:13', '14:14', '14:15', '14:16', '14:16', '14:17', '14:18', '14:19', '14:20', '14:21', '14:22', '14:23', '14:29', '14:32', '14:33', '14:34', '14:35', '14:36', '14:40', '14:41', '14:42', '14:43', '14:46', '14:53', '14:54', '15:02']],
    ],
  },
  /*
   * 系統3 復路（科技大 → 空港・千歳駅経由 → 長都駅東口）
   *
   * バスは千歳駅前（4番）通過後に長都駅東口まで続行するが、
   * destination は旧形式の応答を保つため '千歳駅' のままにしてある。
   * 分岐には direction を使うこと（destination は表示用）。
   *
   * この系統だけ千歳駅が**途中停留所**で、ここから長都方面へ乗車できる。
   * そのため復路だが platform を持つ（大学配付物では「千歳駅前（４番）」）。
   * 系統1・系統2 の復路は千歳駅が終点（西口降専・降車専用）なので持たない。
   *
   * フラグ行なし → 全便が平日・土日祝ともに運行。
   * 期別フラグは立てない。両 PDF の共通停留所26時刻が一致することを確認済み（#177）。
   */
  {
    direction: 'inbound',
    routeLabel: '長都行き', destination: '千歳駅',
    platform: { chitose: '4番' },
    stops: ['rapidus', 'honbuto', 'kenkyuto', 'domestic28', 'domestic1', 'international85', 'airCargo', 'minamiChitose', 'asahicho7', 'asahicho4', 'shiyakusho', 'koizumi', 'morimoto', 'chitose', 'aeon', 'hokuei2', 'hoyukai', 'yao', 'shinano4', 'fuji4', 'hokko6', 'hokuyo3', 'hokuyoHs', 'alice', 'isamai2', 'isamaiJhs', 'isamaiPark', 'isamai7', 'arcs', 'osatsu'],
    trips: [
      ['B', '', ['20:30', '20:32', '20:35', '20:42', '20:43', '20:44', '20:46', '20:47', '20:50', '20:51', '20:52', '20:53', '20:54', '21:00', '21:01', '21:02', '21:03', '21:04', '21:05', '21:06', '21:07', '21:08', '21:08', '21:09', '21:10', '21:10', '21:11', '21:11', '21:12', '21:22']],
      ['B', '', ['22:00', '22:02', '22:05', '22:12', '22:13', '22:14', '22:16', '22:17', '22:20', '22:21', '22:22', '22:23', '22:24', '22:30', '22:31', '22:32', '22:33', '22:34', '22:35', '22:36', '22:37', '22:38', '22:38', '22:39', '22:40', '22:40', '22:41', '22:41', '22:42', '22:52']],
    ],
  },
];

/**
 * 旧形式（v<=3）で「乗車地」として出す停留所と direction 名。
 *
 * 停留所を増やしても旧アプリの応答を変えてはいけないため、ここは**明示的に列挙する**。
 * 「後に別の停留所がある停留所すべて」のような規則にすると、復路の南千歳が
 * 乗車地として増えてしまい、現行の応答と食い違う。
 *
 * キーは ROUTES の direction（outbound / inbound）。表示用の destination を
 * キーにすると、行き先の表記を足したときに解決できず doGet ごと落ちる。
 */
var LEGACY_BOARDING = {
  outbound: [
    ['chitose', 'from_chitose'],
    ['minamiChitose', 'from_minami_chitose'],
    ['kenkyuto', 'from_kenkyuto_to_honbuto'],
  ],
  inbound: [
    ['honbuto', 'from_honbuto'],
    ['kenkyuto', 'from_kenkyuto_to_station'],
  ],
};

/** 旧形式が扱える4停留所。arrivals はこれだけに絞る */
var LEGACY_STOPS = ['chitose', 'minamiChitose', 'kenkyuto', 'honbuto'];

function getHardcodedTimetable() {
  var today = Utilities.formatDate(new Date(), 'Asia/Tokyo', 'yyyy-MM-dd');
  return {
    updatedAt: today,
    current: {
      validFrom: '2025-04-01',
      validTo: '2099-12-31',
      schedules: toLegacySchedules()
    },
    upcoming: null
  };
}

/**
 * v>=4 の応答を組み立てる。
 *
 * 旧形式は1便を乗車地ごとに展開するため、停留所 n 個で n(n-1)/2 組の到着時刻を
 * 持つことになり、全31停留所では約1MB に膨れる。そこで新形式では
 * **1便を1件**とし、停留所と時刻の並びをそのまま渡す。O(n) になり、実測で
 * 全停留所 約35KB / デフォルトの4停留所 約17KB（旧形式の同条件は約31KB）。
 * どの停留所から乗るかはアプリが配列を切って決める。
 *
 * wanted が null なら全停留所。指定があってもその便が通らない停留所は出さない。
 *
 * stopMaster は wanted に関係なく**常に全停留所**を返す。設定画面の選択肢が
 * ここから来るため、絞ると選べる停留所が増えなくなる。
 */
function buildStopsResponse(wanted) {
  var today = Utilities.formatDate(new Date(), 'Asia/Tokyo', 'yyyy-MM-dd');
  var trips = [];

  ROUTES.forEach(function(route) {
    route.trips.forEach(function(tr) {
      var flag = tr[0], season = tr[1], times = tr[2];

      var stops = [];
      route.stops.forEach(function(id, i) {
        if (wanted && !wanted[id]) return;
        var stop = { id: id, time: times[i] };
        var platform = route.platform && route.platform[id];
        if (platform) stop.platform = platform;
        stops.push(stop);
      });
      // 選んだ停留所を1つも通らない便は返さない
      if (stops.length === 0) return;

      trips.push({
        destination: route.destination,
        routeLabel: route.routeLabel,
        weekdayOnly: flag === 'D',
        weekendOnly: flag === 'E',
        academicOnly: season === 'A',
        vacationOnly: season === 'V',
        stops: stops
      });
    });
  });

  return {
    updatedAt: today,
    stopMaster: STOPS.map(function(s) {
      var out = { id: s.id, label: s.label };
      // 正式名と同じなら返さない（アプリ側は shortLabel || label で解決する）
      if (s.shortLabel) out.shortLabel = s.shortLabel;
      // 乗車できない停留所（ラピダス前）は選択肢から外すための印。
      // stopMaster から省くことはできない — ラベルの供給元がここしかないため
      if (s.boardable === false) out.boardable = false;
      return out;
    }),
    current: {
      validFrom: '2025-04-01',
      validTo: '2099-12-31',
      trips: trips
    },
    upcoming: null
  };
}

/**
 * ROUTES を旧形式（乗車地ごとに1件）へ展開する。
 *
 * ROUTES の並び順・LEGACY_BOARDING の並び順・arrivals のキー順は、
 * いずれも応答のバイト列に影響する。scripts/check_gas_response.js が
 * リファクタ前のスナップショットと比較して守っている。
 */
function toLegacySchedules() {
  var out = [];
  ROUTES.forEach(function(route) {
    var boarding = LEGACY_BOARDING[route.direction];
    if (!boarding) {
      throw new Error('LEGACY_BOARDING に無い direction: ' + route.direction);
    }
    route.trips.forEach(function(tr) {
      var flag = tr[0], season = tr[1], times = tr[2];
      var at = {};
      route.stops.forEach(function(id, i) { at[id] = times[i]; });

      boarding.forEach(function(b) {
        var stopId = b[0], direction = b[1];
        if (at[stopId] == null) return;

        // 乗車地より後にある停留所のうち、旧形式が扱える4つだけを到着として持つ
        var arrivals = {};
        var passed = false;
        route.stops.forEach(function(id) {
          if (id === stopId) { passed = true; return; }
          if (!passed) return;
          if (LEGACY_STOPS.indexOf(id) < 0) return;
          arrivals[id] = at[id];
        });
        if (Object.keys(arrivals).length === 0) return;

        out.push({
          time: at[stopId],
          direction: direction,
          destination: route.destination,
          routeLabel: route.routeLabel,
          platformNumber: (route.platform && route.platform[stopId]) || null,
          weekdayOnly: flag === 'D',
          weekendOnly: flag === 'E',
          academicOnly: season === 'A',
          vacationOnly: season === 'V',
          arrivals: arrivals
        });
      });
    });
  });
  return out;
}

// ---- テスト用 ----

function testHardcoded() {
  var result = getHardcodedTimetable();
  Logger.log(JSON.stringify(result, null, 2));
}
