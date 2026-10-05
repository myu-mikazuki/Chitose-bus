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
      // 期別は v=1 のアプリが判定できないため、常にサーバ側で絞る。
      if (season === 'vacation' && en.academicOnly) return false;
      if (season === 'academic' && en.vacationOnly) return false;
      // 運行日は v=1 のアプリも曜日から判定できるので、絞るのは判定が食い違う
      // 「平日に当たる祝日」だけにする。毎日絞ると、v1.1.0 の「当日以外のダイヤ」
      // （同じ current.schedules をクライアント側で絞り直す）が 0 件になる。
      // isHolidayOnWeekday が真なら dayType は必ず weekendHoliday なので、
      // 落とすのは weekdayOnly の便だけでよい。
      if (isHolidayOnWeekday && en.weekdayOnly) return false;
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
 * shortLabel はタブなど幅の狭い場所で使う短縮名。全停留所に付ける（#207）。
 * 正式名（最長 143px）はタブに入らず、頭の1〜2文字しか出ないため。
 *
 * ラベルに使える幅は実測で **4タブ 45.8px・上限の5タブ 27.0px**（375px 端末で
 * HomeScreen を実際に描画。#207）。**全角3字（33px）を目安**にすれば4タブで確実に
 * 収まる。4字は上限ぎりぎりで（もりもと 44.2px / O･A入口 43.1px）、5タブでは
 * どのみち1字＋… に切れる（#204）。
 *
 * issue #207 の「残り 27〜33px」は3字ラベル自体の幅であって、使える幅ではない。
 * タブには3つの経路がある（中央＋星 → 横並び → 11px 縮小）うえ、labelPadding の
 * 左右16px も引かれるので、幅は経路ごとに違う。
 *
 * **正式名に無い言葉を足さないこと。** 削るだけで作る:
 *
 * - 末尾の「前」「入口」「東口」などを落とす（アークス前 → アークス、
 *   長都駅東口 → 長都駅）
 * - 「N丁目」は地名＋N にする。地名が長ければそれも削る（朝日町4丁目 → 朝日4）
 * - 区別に効かない頭を落とす（空港国内線28番 → 国内28）
 * - 種別を表す語は頭だけ残すか落とす（勇舞中学校前 → 勇舞中、
 *   古泉循環器内科クリニック前 → 古泉）
 *
 * 出典の無い略称を発明すると、利用者が実際のバス停の表記と対応付けられなくなる。
 * 例外は arcadia のみ（下記のコメント）。
 *
 * **31件で重複させないこと。** 同時に最大5停留所がタブに並ぶので、朝日4／朝日7 や
 * 勇舞7／勇舞2／勇舞中 のように紛らわしい組ほど確実に別物として読める必要がある。
 * **正式名と同じ短縮名にもしないこと**（削れないなら別の削り方を探す）。
 * 全件必須・重複なし・正式名と別・全角4字以内は check_gas_response.js が見る。
 *
 * **短縮名はタブ以外にも出る。** アプリは labelOf（= shortLabel ?? label）を
 * タブ・行き先の見出し・NEXT BUS カード・時刻表の「◯◯ 着」で共有している。
 * 幅が足りているそれらの場所にも短縮名が出るので、**短縮名だけでどの停留所か
 * 伝わるか**で選ぶこと。出し分けはアプリ側の作りを変える話になる（#208）。
 *
 * 千歳市の PDF を一次情報にしないこと。空17・空18 の表が画像で、
 * pdftotext で読めず目視に頼ることになる。実際に #159 で誤読した
 * （詳細は系統1復路のコメント）。
 */
var STOPS = [
  { id: 'osatsu', label: '長都駅東口', shortLabel: '長都駅' },
  { id: 'arcs', label: 'アークス前', shortLabel: 'アークス' },
  { id: 'isamai7', label: '勇舞7丁目', shortLabel: '勇舞7' },
  { id: 'isamaiPark', label: '勇舞公園前', shortLabel: '勇舞公園' },
  { id: 'isamaiJhs', label: '勇舞中学校前', shortLabel: '勇舞中' },
  { id: 'isamai2', label: '勇舞2丁目', shortLabel: '勇舞2' },
  { id: 'alice', label: 'アリスこども園前', shortLabel: 'アリス' },
  { id: 'hokuyoHs', label: '北陽高校前', shortLabel: '北陽高' },
  { id: 'hokuyo3', label: '北陽3丁目', shortLabel: '北陽3' },
  { id: 'hokko6', label: '北光6丁目', shortLabel: '北光6' },
  { id: 'fuji4', label: '富士4丁目', shortLabel: '富士4' },
  { id: 'shinano4', label: '信濃4丁目', shortLabel: '信濃4' },
  { id: 'yao', label: '矢尾外科胃腸科前', shortLabel: '矢尾' },
  { id: 'hoyukai', label: '千歳豊友会病院前', shortLabel: '豊友会' },
  { id: 'hokuei2', label: '北栄2丁目', shortLabel: '北栄2' },
  { id: 'aeon', label: 'イオン千歳店前', shortLabel: 'イオン' },
  { id: 'chitose', label: '千歳駅前', shortLabel: '千歳駅' },
  { id: 'morimoto', label: 'もりもと本店前', shortLabel: 'もりもと' },
  { id: 'koizumi', label: '古泉循環器内科クリニック前', shortLabel: '古泉' },
  { id: 'shiyakusho', label: '市役所前', shortLabel: '市役所' },
  { id: 'asahicho4', label: '朝日町4丁目', shortLabel: '朝日4' },
  { id: 'asahicho7', label: '朝日町7丁目', shortLabel: '朝日7' },
  // 「オフィス・アルカディア」は3字に縮めようがないため頭字語で受ける。
  // 半角カナ（ｱﾙｶﾃﾞｨｱ）はここだけ表記が浮くので採らなかった。
  //
  // 中点が半角（U+FF65 ･）なのは実測の都合。全角の「・」（U+30FB）だと 49.1px で
  // 4タブの 45.8px に入らず省略される（半角なら 43.6px）。**全角に直さないこと。**
  { id: 'arcadia', label: 'オフィス・アルカディア入口', shortLabel: 'O･A入口' },
  { id: 'minamiChitose', label: '南千歳駅', shortLabel: '南千歳' },
  // 南17（令和8年10月1日新設）の起終点。南千歳駅とは別の停留所なので分けてある。
  // 「南千歳北」（4字）だと5タブで「南千…」に切れ、隣の「南千歳」と読み分けられない
  // （#271）。5タブでラベルに残るのは 375px で 27px 程度で、**2字でないと切れない**。
  // 3字の「南千北」は 411px 以上でしか収まらず、375・390px では「南…」になって
  // 「南千歳」（同じく「南…」）と区別できなかった（実測）。
  // 「駅」を削り、頭の「南千歳」を落として「北口」だけにしている。足してはいない。
  { id: 'minamiChitoseNorth', label: '南千歳駅北口', shortLabel: '北口' },
  // 「エアカーゴ」だと4タブでも「エアカ…」に切れる（31件で唯一の省略だった）
  { id: 'airCargo', label: 'エアカーゴ前', shortLabel: 'カーゴ' },
  { id: 'domestic28', label: '空港国内線28番', shortLabel: '国内28' },
  { id: 'domestic1', label: '空港国内線1番', shortLabel: '国内1' },
  { id: 'international85', label: '空港国際線85番', shortLabel: '国際85' },
  { id: 'kenkyuto', label: '科技大研究棟', shortLabel: '研究棟' },
  { id: 'honbuto', label: '科技大本部棟', shortLabel: '本部棟' },
  { id: 'rapidus', label: 'ラピダス前', shortLabel: 'ラピダス', boardable: false },
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
 * ---- 令和8年10月1日改正（#253）----
 *
 * 原典は千歳市の2枚組 PDF（掲載ページ「令和８年10月から路線バスがもっと便利に
 * なります！」・2026-09-25 公開）。**旧 bibikuuko.pdf とは別物**で、
 * こちらは全面がテキストレイヤーのため機械抽出できる。
 *
 *   平日ダイヤ: .../_page_/001/006/967/bibi_jikoku.pdf
 *   休日ダイヤ: .../_page_/001/006/967/bibi_jikoku_kyujitsu.pdf
 *
 * 抽出は座標（pdftotext -bbox-layout）で列を決め、**全161便 × 34列で時刻が
 * 並び順どおりに増えること**を検査して列ズレが無いことを確かめている。
 * うち科技大に来るのは126便で、平日／土日祝で時刻が完全に一致する26組を
 * 'B'（毎日）にまとめた結果が下の100便。
 *
 * **系統16（勇舞空港線）は載せていない。** 同じ PDF に載るが科技大に来ない。
 *
 * ★ 期別（学休期）フラグはこの改正で**全便 '' にしてある**。新 PDF は運行日を
 *   「平日」「土日祝」の2種類でしか持たず、学休期ダイヤが存在しない。
 *   **大学配付物に別途あるかは未確認**。あれば #132 の仕組みに載せ直すこと。
 *
 * ★ 千歳駅は PDF が「4番のりば」「5番のりば」「（降専）」と列を分けているが、
 *   アプリは従来どおり chitose 1件 + platform で表す。同じ便が2つ以上の
 *   千歳駅の列を持つことは無いので衝突しない。
 */
var ROUTES = [
  /*
   * 系統1 往路（千歳駅5番のりば → 空港経由 → 科技大）
   *
   * 原典: 千歳市「（平日ダイヤ）／（休日ダイヤ）美々空港線・勇舞空港線 時刻表」
   * （令和8年10月1日改正・PDF 表記は「空17」）。
   */
  {
    direction: 'outbound',
    routeLabel: '空港経由', destination: '科技大',
    platform: { chitose: '5番' },
    stops: ['chitose', 'morimoto', 'koizumi', 'shiyakusho', 'asahicho4', 'asahicho7', 'minamiChitose', 'airCargo', 'domestic28', 'domestic1', 'international85', 'kenkyuto', 'honbuto', 'rapidus'],
    trips: [
      ['D', '', ['06:45', '06:48', '06:49', '06:50', '06:51', '06:52', '06:56', '06:57', '06:58', '06:59', '07:02', '07:09', '07:10', '07:13']],
      ['B', '', ['07:15', '07:18', '07:19', '07:20', '07:21', '07:22', '07:26', '07:27', '07:28', '07:29', '07:32', '07:39', '07:40', '07:43']],
      ['B', '', ['09:50', '09:53', '09:54', '09:55', '09:56', '09:57', '10:01', '10:02', '10:03', '10:04', '10:07', '10:14', '10:15', '10:18']],
      ['B', '', ['10:45', '10:48', '10:49', '10:50', '10:51', '10:52', '10:56', '10:57', '10:58', '10:59', '11:02', '11:09', '11:10', '11:13']],
      ['D', '', ['11:00', '11:03', '11:04', '11:05', '11:06', '11:07', '11:11', '11:12', '11:13', '11:14', '11:17', '11:24', '11:25', '11:28']],
      ['D', '', ['11:50', '11:53', '11:54', '11:55', '11:56', '11:57', '12:01', '12:02', '12:03', '12:04', '12:07', '12:14', '12:15', '12:18']],
      ['D', '', ['12:10', '12:13', '12:14', '12:15', '12:16', '12:17', '12:21', '12:22', '12:23', '12:24', '12:27', '12:34', '12:35', '12:38']],
      ['B', '', ['12:40', '12:43', '12:44', '12:45', '12:46', '12:47', '12:51', '12:52', '12:53', '12:54', '12:57', '13:04', '13:05', '13:08']],
      ['D', '', ['13:20', '13:23', '13:24', '13:25', '13:26', '13:27', '13:31', '13:32', '13:33', '13:34', '13:37', '13:44', '13:45', '13:48']],
      ['E', '', ['13:40', '13:43', '13:44', '13:45', '13:46', '13:47', '13:51', '13:52', '13:53', '13:54', '13:57', '14:04', '14:05', '14:08']],
      ['D', '', ['14:50', '14:53', '14:54', '14:55', '14:56', '14:57', '15:01', '15:02', '15:03', '15:04', '15:07', '15:14', '15:15', '15:18']],
      ['D', '', ['15:18', '15:21', '15:22', '15:23', '15:24', '15:25', '15:29', '15:30', '15:31', '15:32', '15:35', '15:42', '15:43', '15:46']],
      ['B', '', ['16:00', '16:03', '16:04', '16:05', '16:06', '16:07', '16:11', '16:12', '16:13', '16:14', '16:17', '16:24', '16:25', '16:28']],
      ['E', '', ['17:30', '17:33', '17:34', '17:35', '17:36', '17:37', '17:41', '17:42', '17:43', '17:44', '17:47', '17:54', '17:55', '17:58']],
    ],
  },
  /*
   * 系統1 復路（科技大 → 空港経由 → 千歳駅（降車専用））
   *
   * 原典: 千歳市「（平日ダイヤ）／（休日ダイヤ）美々空港線・勇舞空港線 時刻表」
   * （令和8年10月1日改正・PDF 表記は「空17」）。
   *
   * 【消さないこと】**全便が南千歳駅を経由する。** 旧 bibikuuko.pdf ではこの
   * セルが黒塗りに見えたため通過と誤読し、到着時刻を削除して本番に出した
   * （#159／PR #176 で差し戻し）。改正版 PDF はテキストレイヤーを持ち、
   * 復路の空17・空18 全25便に南千歳の時刻が並んでいることを確認済み。
   * check_gas_season.js が「空港を通る復路便は必ず南千歳の到着を持つ」で見張る。
   */
  {
    direction: 'inbound',
    routeLabel: '空港経由', destination: '千歳駅',
    stops: ['rapidus', 'honbuto', 'kenkyuto', 'domestic28', 'domestic1', 'international85', 'airCargo', 'minamiChitose', 'asahicho7', 'asahicho4', 'shiyakusho', 'koizumi', 'morimoto', 'chitose'],
    trips: [
      ['B', '', ['08:20', '08:22', '08:25', '08:32', '08:33', '08:34', '08:36', '08:37', '08:40', '08:41', '08:42', '08:43', '08:44', '08:48']],
      ['B', '', ['09:00', '09:02', '09:05', '09:12', '09:13', '09:14', '09:16', '09:17', '09:20', '09:21', '09:22', '09:23', '09:24', '09:28']],
      ['B', '', ['09:30', '09:32', '09:35', '09:42', '09:43', '09:44', '09:46', '09:47', '09:50', '09:51', '09:52', '09:53', '09:54', '09:58']],
      ['B', '', ['10:40', '10:42', '10:45', '10:52', '10:53', '10:54', '10:56', '10:57', '11:00', '11:01', '11:02', '11:03', '11:04', '11:08']],
      ['E', '', ['11:34', '11:36', '11:39', '11:46', '11:47', '11:48', '11:50', '11:51', '11:54', '11:55', '11:56', '11:57', '11:58', '12:02']],
      ['D', '', ['12:40', '12:42', '12:45', '12:52', '12:53', '12:54', '12:56', '12:57', '13:00', '13:01', '13:02', '13:03', '13:04', '13:08']],
      ['B', '', ['13:33', '13:35', '13:38', '13:45', '13:46', '13:47', '13:49', '13:50', '13:53', '13:54', '13:55', '13:56', '13:57', '14:01']],
      ['D', '', ['14:15', '14:17', '14:20', '14:27', '14:28', '14:29', '14:31', '14:32', '14:35', '14:36', '14:37', '14:38', '14:39', '14:43']],
      ['E', '', ['14:30', '14:32', '14:35', '14:42', '14:43', '14:44', '14:46', '14:47', '14:50', '14:51', '14:52', '14:53', '14:54', '14:58']],
      ['D', '', ['15:22', '15:24', '15:27', '15:34', '15:35', '15:36', '15:38', '15:39', '15:42', '15:43', '15:44', '15:45', '15:46', '15:50']],
      ['D', '', ['15:45', '15:47', '15:50', '15:57', '15:58', '15:59', '16:01', '16:02', '16:05', '16:06', '16:07', '16:08', '16:09', '16:13']],
      ['B', '', ['16:45', '16:47', '16:50', '16:57', '16:58', '16:59', '17:01', '17:02', '17:05', '17:06', '17:07', '17:08', '17:09', '17:13']],
    ],
  },
  /*
   * 系統2 往路（千歳駅4番のりば → 直通 → 科技大）
   *
   * 原典: 千歳市「（平日ダイヤ）／（休日ダイヤ）美々空港線・勇舞空港線 時刻表」
   * （令和8年10月1日改正・PDF 表記は「直17」）。
   */
  {
    direction: 'outbound',
    routeLabel: '直通', destination: '科技大',
    platform: { chitose: '4番' },
    stops: ['chitose', 'morimoto', 'koizumi', 'shiyakusho', 'asahicho4', 'asahicho7', 'arcadia', 'kenkyuto', 'honbuto', 'rapidus'],
    trips: [
      ['D', '', ['07:00', '07:03', '07:04', '07:05', '07:06', '07:07', '07:11', '07:18', '07:21', '07:24']],
      ['D', '', ['07:29', '07:32', '07:33', '07:34', '07:35', '07:36', '07:40', '07:47', '07:50', '07:53']],
      ['B', '', ['07:50', '07:53', '07:54', '07:55', '07:56', '07:57', '08:01', '08:08', '08:11', '08:14']],
      ['D', '', ['08:00', '08:03', '08:04', '08:05', '08:06', '08:07', '08:11', '08:18', '08:21', '08:24']],
      ['D', '', ['08:10', '08:13', '08:14', '08:15', '08:16', '08:17', '08:21', '08:28', '08:31', '08:34']],
      ['D', '', ['08:16', '08:19', '08:20', '08:21', '08:22', '08:23', '08:27', '08:34', '08:37', '08:40']],
      ['D', '', ['08:19', '08:22', '08:23', '08:24', '08:25', '08:26', '08:30', '08:37', '08:40', '08:43']],
      ['B', '', ['08:24', '08:27', '08:28', '08:29', '08:30', '08:31', '08:35', '08:42', '08:45', '08:48']],
      ['D', '', ['08:29', '08:32', '08:33', '08:34', '08:35', '08:36', '08:40', '08:47', '08:50', '08:53']],
      ['D', '', ['08:50', '08:53', '08:54', '08:55', '08:56', '08:57', '09:01', '09:08', '09:11', '09:14']],
      ['D', '', ['09:04', '09:07', '09:08', '09:09', '09:10', '09:11', '09:15', '09:22', '09:25', '09:28']],
      ['D', '', ['09:19', '09:22', '09:23', '09:24', '09:25', '09:26', '09:30', '09:37', '09:40', '09:43']],
      ['D', '', ['09:34', '09:37', '09:38', '09:39', '09:40', '09:41', '09:45', '09:52', '09:55', '09:58']],
      ['D', '', ['09:54', '09:57', '09:58', '09:59', '10:00', '10:01', '10:05', '10:12', '10:15', '10:18']],
      ['D', '', ['10:04', '10:07', '10:08', '10:09', '10:10', '10:11', '10:15', '10:22', '10:25', '10:28']],
      ['D', '', ['10:14', '10:17', '10:18', '10:19', '10:20', '10:21', '10:25', '10:32', '10:35', '10:38']],
      ['D', '', ['14:24', '14:27', '14:28', '14:29', '14:30', '14:31', '14:35', '14:42', '14:45', '14:48']],
    ],
  },
  /*
   * 系統2 復路（科技大 → 直通 → 千歳駅（降車専用））
   *
   * 原典: 千歳市「（平日ダイヤ）／（休日ダイヤ）美々空港線・勇舞空港線 時刻表」
   * （令和8年10月1日改正・PDF 表記は「直17」）。
   */
  {
    direction: 'inbound',
    routeLabel: '直通', destination: '千歳駅',
    stops: ['rapidus', 'honbuto', 'kenkyuto', 'arcadia', 'asahicho7', 'asahicho4', 'shiyakusho', 'koizumi', 'morimoto', 'chitose'],
    trips: [
      ['D', '', ['12:25', '12:27', '12:30', '12:37', '12:41', '12:42', '12:43', '12:44', '12:45', '12:49']],
      ['D', '', ['13:05', '13:07', '13:10', '13:17', '13:21', '13:22', '13:23', '13:24', '13:25', '13:29']],
      ['D', '', ['14:50', '14:52', '14:55', '15:02', '15:06', '15:07', '15:08', '15:09', '15:10', '15:14']],
      ['D', '', ['16:00', '16:02', '16:05', '16:12', '16:16', '16:17', '16:18', '16:19', '16:20', '16:24']],
      ['D', '', ['16:40', '16:42', '16:45', '16:52', '16:56', '16:57', '16:58', '16:59', '17:00', '17:04']],
      ['D', '', ['17:00', '17:02', '17:05', '17:12', '17:16', '17:17', '17:18', '17:19', '17:20', '17:24']],
      ['D', '', ['17:15', '17:17', '17:20', '17:27', '17:31', '17:32', '17:33', '17:34', '17:35', '17:39']],
      ['D', '', ['17:28', '17:30', '17:33', '17:40', '17:44', '17:45', '17:46', '17:47', '17:48', '17:52']],
      ['D', '', ['17:40', '17:42', '17:45', '17:52', '17:56', '17:57', '17:58', '17:59', '18:00', '18:04']],
      ['D', '', ['18:25', '18:27', '18:30', '18:37', '18:41', '18:42', '18:43', '18:44', '18:45', '18:49']],
      ['D', '', ['18:45', '18:47', '18:50', '18:57', '19:01', '19:02', '19:03', '19:04', '19:05', '19:09']],
      ['D', '', ['19:10', '19:12', '19:15', '19:22', '19:26', '19:27', '19:28', '19:29', '19:30', '19:34']],
      ['D', '', ['19:30', '19:32', '19:35', '19:42', '19:46', '19:47', '19:48', '19:49', '19:50', '19:54']],
    ],
  },
  /*
   * 系統3 往路（長都駅東口 → 千歳駅5番 → 空港経由 → 科技大）
   *
   * 原典: 千歳市「（平日ダイヤ）／（休日ダイヤ）美々空港線・勇舞空港線 時刻表」
   * （令和8年10月1日改正・PDF 表記は「空18」）。
   *
   * バスは長都駅東口発だが、旧形式では千歳駅前（5番）を乗車起点として扱う。
   * platform を千歳駅に付けているのはそのため。
   */
  {
    direction: 'outbound',
    routeLabel: '長都発', destination: '科技大',
    platform: { chitose: '5番' },
    stops: ['osatsu', 'arcs', 'isamai7', 'isamaiPark', 'isamaiJhs', 'isamai2', 'alice', 'hokuyoHs', 'hokuyo3', 'hokko6', 'fuji4', 'shinano4', 'yao', 'hoyukai', 'hokuei2', 'aeon', 'chitose', 'morimoto', 'koizumi', 'shiyakusho', 'asahicho4', 'asahicho7', 'minamiChitose', 'airCargo', 'domestic28', 'domestic1', 'international85', 'kenkyuto', 'honbuto', 'rapidus'],
    trips: [
      ['B', '', ['06:10', '06:11', '06:12', '06:12', '06:13', '06:13', '06:15', '06:16', '06:16', '06:17', '06:18', '06:19', '06:20', '06:21', '06:22', '06:23', '06:29', '06:32', '06:33', '06:34', '06:35', '06:36', '06:40', '06:41', '06:42', '06:43', '06:46', '06:53', '06:54', '07:02']],
      ['D', '', ['06:40', '06:41', '06:42', '06:42', '06:43', '06:43', '06:45', '06:46', '06:46', '06:47', '06:48', '06:49', '06:50', '06:51', '06:52', '06:53', '06:59', '07:02', '07:03', '07:04', '07:05', '07:06', '07:10', '07:11', '07:12', '07:13', '07:16', '07:23', '07:24', '07:32']],
      ['B', '', ['07:10', '07:11', '07:12', '07:12', '07:13', '07:13', '07:14', '07:15', '07:16', '07:17', '07:19', '07:21', '07:22', '07:24', '07:26', '07:28', '07:34', '07:37', '07:38', '07:39', '07:40', '07:41', '07:45', '07:46', '07:47', '07:48', '07:51', '07:58', '07:59', '08:07']],
      ['B', '', ['11:10', '11:11', '11:12', '11:12', '11:13', '11:13', '11:15', '11:16', '11:16', '11:17', '11:18', '11:19', '11:20', '11:21', '11:22', '11:23', '11:29', '11:32', '11:33', '11:34', '11:35', '11:36', '11:40', '11:41', '11:42', '11:43', '11:46', '11:53', '11:54', '12:02']],
      ['D', '', ['12:00', '12:01', '12:02', '12:02', '12:03', '12:03', '12:05', '12:06', '12:06', '12:07', '12:08', '12:09', '12:10', '12:11', '12:12', '12:13', '12:19', '12:22', '12:23', '12:24', '12:25', '12:26', '12:30', '12:31', '12:32', '12:33', '12:36', '12:43', '12:44', '12:52']],
      ['B', '', ['18:10', '18:11', '18:12', '18:12', '18:13', '18:14', '18:15', '18:16', '18:16', '18:17', '18:18', '18:19', '18:20', '18:21', '18:22', '18:23', '18:29', '18:32', '18:33', '18:34', '18:35', '18:36', '18:40', '18:41', '18:42', '18:43', '18:46', '18:53', '18:54', '19:02']],
      ['B', '', ['19:10', '19:11', '19:12', '19:12', '19:13', '19:13', '19:15', '19:16', '19:16', '19:17', '19:18', '19:19', '19:20', '19:21', '19:22', '19:23', '19:29', '19:32', '19:33', '19:34', '19:35', '19:36', '19:40', '19:41', '19:42', '19:43', '19:46', '19:53', '19:54', '20:02']],
    ],
  },
  /*
   * 系統3 復路（科技大 → 空港・千歳駅経由 → 長都駅東口）
   *
   * 原典: 千歳市「（平日ダイヤ）／（休日ダイヤ）美々空港線・勇舞空港線 時刻表」
   * （令和8年10月1日改正・PDF 表記は「空18」）。
   *
   * destination は旧形式の応答を保つため '千歳駅' のままにしてある。
   * 分岐には direction を使うこと（destination は表示用）。
   *
   * この系統だけ千歳駅が**途中停留所**で、ここから長都方面へ乗車できる。
   * そのため復路だが platform を持つ（PDF では「千歳駅前4番のりば」）。
   * 系統1・系統2 の復路は千歳駅が終点（降車専用）なので持たない。
   */
  {
    direction: 'inbound',
    routeLabel: '長都行き', destination: '千歳駅',
    platform: { chitose: '4番' },
    stops: ['rapidus', 'honbuto', 'kenkyuto', 'domestic28', 'domestic1', 'international85', 'airCargo', 'minamiChitose', 'asahicho7', 'asahicho4', 'shiyakusho', 'koizumi', 'morimoto', 'chitose', 'aeon', 'hokuei2', 'hoyukai', 'yao', 'shinano4', 'fuji4', 'hokko6', 'hokuyo3', 'hokuyoHs', 'alice', 'isamai2', 'isamaiJhs', 'isamaiPark', 'isamai7', 'arcs', 'osatsu'],
    trips: [
      ['B', '', ['12:20', '12:22', '12:25', '12:32', '12:33', '12:34', '12:36', '12:37', '12:40', '12:41', '12:42', '12:42', '12:44', '12:50', '12:51', '12:52', '12:53', '12:54', '12:55', '12:56', '12:57', '12:58', '12:58', '12:59', '13:00', '13:00', '13:00', '13:01', '13:02', '13:12']],
      ['B', '', ['15:10', '15:12', '15:15', '15:22', '15:23', '15:24', '15:26', '15:27', '15:30', '15:31', '15:32', '15:32', '15:34', '15:40', '15:41', '15:42', '15:43', '15:44', '15:45', '15:46', '15:47', '15:48', '15:48', '15:49', '15:50', '15:50', '15:50', '15:51', '15:52', '16:02']],
      ['B', '', ['18:05', '18:07', '18:10', '18:17', '18:18', '18:19', '18:21', '18:22', '18:25', '18:26', '18:27', '18:27', '18:29', '18:35', '18:36', '18:37', '18:38', '18:39', '18:40', '18:41', '18:42', '18:43', '18:43', '18:44', '18:45', '18:45', '18:45', '18:46', '18:47', '18:57']],
      ['E', '', ['18:40', '18:42', '18:45', '18:52', '18:53', '18:54', '18:56', '18:57', '19:00', '19:01', '19:02', '19:03', '19:04', '19:10', '19:11', '19:12', '19:13', '19:14', '19:15', '19:16', '19:17', '19:18', '19:18', '19:19', '19:20', '19:20', '19:20', '19:21', '19:22', '19:32']],
      ['D', '', ['18:57', '18:59', '19:02', '19:09', '19:10', '19:11', '19:13', '19:14', '19:17', '19:18', '19:19', '19:20', '19:21', '19:27', '19:28', '19:29', '19:30', '19:31', '19:32', '19:33', '19:34', '19:35', '19:35', '19:36', '19:37', '19:37', '19:37', '19:38', '19:39', '19:49']],
      ['B', '', ['19:15', '19:17', '19:20', '19:27', '19:28', '19:29', '19:31', '19:32', '19:35', '19:36', '19:37', '19:37', '19:39', '19:45', '19:46', '19:47', '19:48', '19:49', '19:50', '19:51', '19:52', '19:53', '19:53', '19:54', '19:55', '19:55', '19:55', '19:56', '19:57', '20:07']],
      ['D', '', ['19:40', '19:42', '19:45', '19:52', '19:53', '19:54', '19:56', '19:57', '20:00', '20:01', '20:02', '20:03', '20:04', '20:10', '20:11', '20:12', '20:13', '20:14', '20:15', '20:16', '20:17', '20:18', '20:18', '20:19', '20:20', '20:20', '20:20', '20:21', '20:22', '20:32']],
      ['B', '', ['20:20', '20:22', '20:25', '20:32', '20:33', '20:34', '20:36', '20:37', '20:40', '20:41', '20:42', '20:43', '20:44', '20:50', '20:51', '20:52', '20:53', '20:54', '20:55', '20:56', '20:57', '20:58', '20:58', '20:59', '21:00', '21:00', '21:00', '21:01', '21:02', '21:12']],
      ['D', '', ['21:00', '21:02', '21:05', '21:12', '21:13', '21:14', '21:16', '21:17', '21:20', '21:21', '21:22', '21:23', '21:24', '21:30', '21:31', '21:32', '21:33', '21:34', '21:35', '21:36', '21:37', '21:38', '21:38', '21:39', '21:40', '21:40', '21:40', '21:41', '21:42', '21:52']],
      ['E', '', ['21:20', '21:22', '21:25', '21:32', '21:33', '21:34', '21:36', '21:37', '21:40', '21:41', '21:42', '21:43', '21:44', '21:50', '21:51', '21:52', '21:53', '21:54', '21:55', '21:56', '21:57', '21:58', '21:58', '21:59', '22:00', '22:00', '22:00', '22:01', '22:02', '22:12']],
      ['D', '', ['21:50', '21:52', '21:55', '22:02', '22:03', '22:04', '22:06', '22:07', '22:10', '22:11', '22:12', '22:13', '22:14', '22:20', '22:21', '22:22', '22:23', '22:24', '22:25', '22:26', '22:27', '22:28', '22:28', '22:29', '22:30', '22:30', '22:30', '22:31', '22:32', '22:42']],
      ['D', '', ['22:30', '22:32', '22:35', '22:42', '22:43', '22:44', '22:46', '22:47', '22:50', '22:51', '22:52', '22:53', '22:54', '23:00', '23:01', '23:02', '23:03', '23:04', '23:05', '23:06', '23:07', '23:08', '23:08', '23:09', '23:10', '23:10', '23:10', '23:11', '23:12', '23:22']],
      ['B', '', ['23:30', '23:32', '23:35', '23:42', '23:43', '23:44', '23:46', '23:47', '23:50', '23:51', '23:52', '23:53', '23:54', '24:00', '24:01', '24:02', '24:03', '24:04', '24:05', '24:06', '24:07', '24:08', '24:08', '24:09', '24:10', '24:10', '24:10', '24:11', '24:12', '24:22']],
    ],
  },
  /*
   * 系統4 往路（南千歳駅北口 → 直通 → 科技大）
   *
   * 原典: 千歳市「（平日ダイヤ）／（休日ダイヤ）美々空港線・勇舞空港線 時刻表」
   * （令和8年10月1日改正・PDF 表記は「南17」）。
   */
  {
    direction: 'outbound',
    routeLabel: '南千歳発', destination: '科技大',
    stops: ['minamiChitoseNorth', 'kenkyuto', 'honbuto', 'rapidus'],
    trips: [
      ['B', '', ['06:50', '06:58', '07:01', '07:06']],
      ['D', '', ['07:10', '07:18', '07:21', '07:26']],
      ['D', '', ['07:25', '07:33', '07:36', '07:41']],
      ['D', '', ['07:30', '07:38', '07:41', '07:46']],
      ['B', '', ['07:50', '07:58', '08:01', '08:06']],
      ['D', '', ['08:05', '08:13', '08:16', '08:21']],
      ['E', '', ['08:30', '08:38', '08:41', '08:46']],
      ['D', '', ['08:35', '08:43', '08:46', '08:51']],
      ['D', '', ['08:40', '08:48', '08:51', '08:56']],
      ['D', '', ['08:55', '09:03', '09:06', '09:11']],
      ['D', '', ['09:25', '09:33', '09:36', '09:41']],
      ['D', '', ['09:40', '09:48', '09:51', '09:56']],
      ['D', '', ['10:05', '10:13', '10:16', '10:21']],
      ['D', '', ['10:20', '10:28', '10:31', '10:36']],
    ],
  },
  /*
   * 系統4 復路（科技大 → 直通 → 南千歳駅北口）
   *
   * 原典: 千歳市「（平日ダイヤ）／（休日ダイヤ）美々空港線・勇舞空港線 時刻表」
   * （令和8年10月1日改正・PDF 表記は「南17」）。
   *
   * **南千歳駅（minamiChitose）ではなく南千歳駅北口（minamiChitoseNorth）。**
   * PDF も別の列として持っている。空17 が通るのは前者。
   */
  {
    direction: 'inbound',
    routeLabel: '南千歳行き', destination: '千歳駅',
    // 旧形式（v<=3）には出さない。旧アプリは terminus を知らず destination を
    // そのまま行き先として出すため、**千歳駅に行かないこの便を「→ 千歳駅」と
    // 表示してしまう**。destination は BusDestination の2値しか取れないので
    // （アプリが行き先で絞る・check_gas_response.js が検査する）、'南千歳駅' に
    // 逃がすこともできない。v>=4 は terminus で正しく「→ 南千歳駅北口」と出る。
    legacy: false,
    stops: ['rapidus', 'honbuto', 'kenkyuto', 'minamiChitoseNorth'],
    trips: [
      ['D', '', ['15:15', '15:17', '15:20', '15:31']],
      ['D', '', ['16:33', '16:35', '16:38', '16:49']],
      ['D', '', ['16:42', '16:44', '16:47', '16:58']],
      ['D', '', ['17:05', '17:07', '17:10', '17:21']],
      ['D', '', ['17:10', '17:12', '17:15', '17:26']],
      ['D', '', ['17:45', '17:47', '17:50', '18:01']],
      ['D', '', ['18:10', '18:12', '18:15', '18:26']],
      ['D', '', ['18:20', '18:22', '18:25', '18:36']],
      ['D', '', ['18:30', '18:32', '18:35', '18:46']],
      ['D', '', ['19:00', '19:02', '19:05', '19:16']],
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
 * 便の終点。**一般に降りられる最後の停留所**の ID を返す。
 *
 * 並びの末尾そのものではない。系統1・2・3 の往路はラピダス前で終わるが、
 * ここは工場敷地内で一般利用できない（`boardable: false`）ため、利用者から見た
 * 終点は本部棟になる。
 *
 * **絞り込み（wanted）より前に決めること。** アプリは「→ 長都駅東口」のように
 * 行き先の見出しに使う。便の通る停留所から導くと、選んだ停留所によって
 * 見出しが変わってしまう（イオン千歳店前を足すと「→ イオン千歳店前」になる）。
 */
function terminusOf(stopIds) {
  for (var i = stopIds.length - 1; i >= 0; i--) {
    if (isBoardableStop(stopIds[i])) return stopIds[i];
  }
  return stopIds[stopIds.length - 1];
}

/** id → boardable。初回に1度だけ組む（STOPS の定義順に依存しないよう遅延で） */
var _boardableById = null;

function isBoardableStop(id) {
  if (_boardableById === null) {
    // requestedStops と同じく Object.create(null) にする。ここは既定が true な
    // ため素の {} でも結果は変わらないが、片方だけ対策してあるように読める
    _boardableById = Object.create(null);
    STOPS.forEach(function(s) { _boardableById[s.id] = s.boardable !== false; });
  }
  // STOPS に無い ID は ROUTES 側の書き間違い。ここでは判断しない
  return _boardableById[id] !== false;
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
    // 便ごとに変わらないので、trips のループの外で1回だけ求める
    var terminus = terminusOf(route.stops);

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
        terminus: terminus,
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
    // legacy: false の系統は旧形式に出さない（#253 の南17 復路）。
    // v>=4 の buildStopsResponse は見ないので、新しいアプリには出る。
    if (route.legacy === false) return;
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
