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
 * 便ごとに以下のフラグを持ち、期別・運行日の絞り込みはアプリ側で行う。
 * サーバは常に全便を返すため、日付判定のズレでデータが欠落することはない。
 *   weekdayOnly / weekendOnly … 平日のみ / 土日祝のみ
 *   academicOnly / vacationOnly … 授業期のみ / 学休期のみ（Issue #132）
 *
 * 学休期の対象期間（夏季: 8月第1月曜日〜9月第4週金曜日、冬季: 2月第1月曜日〜3/31、
 * お盆: 8/13〜8/16）と年末年始運休（12/31〜1/3）の判定はアプリ側 SeasonType /
 * ServiceCalendar が担当する。
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
    var result = getHardcodedTimetable();
    return buildResponse(JSON.stringify(result));
  } catch (err) {
    return ContentService
      .createTextOutput(JSON.stringify({ error: err.message || String(err) }))
      .setMimeType(ContentService.MimeType.JSON);
  }
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

// ---- ハードコード時刻表 ----

/**
 * 時刻表データのバージョン。
 *
 * GAS は Apps Script への手動デプロイが必要で、リポジトリにマージしただけでは
 * 本番に反映されない。デプロイ漏れを検知できるよう、レスポンスにこの値を含める。
 *
 * ★ 時刻表データ（便の追加・削除・時刻変更・フラグ変更）を変更したら必ず更新する。
 *   形式: YYYY-MM-DD.N（N は同日内の連番）
 *
 * 履歴:
 *   2026-08-04.1  学休期ダイヤを追加（Issue #132）
 *   2025-04-01.1  ハードコード時刻表の初版
 */
var TIMETABLE_DATA_VERSION = '2026-08-04.1';

/**
 * 全便（授業期・学休期の両方）を含む時刻表を返す。
 * 期別・運行日の絞り込みはアプリ側で行うため、ここでは日付による選別をしない。
 */
function getHardcodedTimetable() {
  var today = Utilities.formatDate(new Date(), 'Asia/Tokyo', 'yyyy-MM-dd');
  var schedules = [];
  buildRoute1Outbound(schedules);
  buildRoute1Inbound(schedules);
  buildRoute2Outbound(schedules);
  buildRoute2Inbound(schedules);
  buildRoute3Outbound(schedules);
  buildRoute3Inbound(schedules);
  return {
    updatedAt: today,
    dataVersion: TIMETABLE_DATA_VERSION,
    current: {
      validFrom: '2025-04-01',
      validTo: '2099-12-31',
      schedules: schedules
    },
    upcoming: null
  };
}

/**
 * 系統1 往路（千歳駅5番乗り場 → 空港経由 → 科技大）
 *
 * データソース: 時刻表データ_系統1.csv「系統１ to 科技大」
 * フラグ行: ,,★,★,☆,☆,☆,,,,
 * B=平日・休日ともに運行 / D=平日のみ(☆) / E=休日のみ(★)
 *
 * 授業期・学休期で時刻・運行日ともに同一のため、期別フラグは立てない。
 * （学休期は 13:20 便が平日／土日祝の2行に分かれるが、合わせて毎日運行で等価）
 */
function buildRoute1Outbound(schedules) {
  var trips = [
    // [千歳, 南千歳, 研究棟, 本部棟, フラグ]
    ['07:20', '07:31', '07:44', '07:45', 'B'],
    ['08:18', '08:29', '08:42', '08:43', 'E'],
    ['09:10', '09:21', '09:34', '09:35', 'E'],
    ['10:30', '10:41', '10:54', '10:55', 'D'],
    ['11:00', '11:11', '11:24', '11:25', 'D'],
    ['12:10', '12:21', '12:34', '12:35', 'D'],
    ['13:20', '13:31', '13:44', '13:45', 'B'],
  ];
  trips.forEach(function(tr) {
    var wdOnly = tr[4] === 'D', weOnly = tr[4] === 'E';
    schedules.push({ time: tr[0], direction: 'from_chitose',             destination: '科技大', routeLabel: '空港経由', platformNumber: '5番', weekdayOnly: wdOnly, weekendOnly: weOnly, academicOnly: false, vacationOnly: false, arrivals: { minamiChitose: tr[1], kenkyuto: tr[2], honbuto: tr[3] } });
    schedules.push({ time: tr[1], direction: 'from_minami_chitose',      destination: '科技大', routeLabel: '空港経由', platformNumber: null,  weekdayOnly: wdOnly, weekendOnly: weOnly, academicOnly: false, vacationOnly: false, arrivals: { kenkyuto: tr[2], honbuto: tr[3] } });
    schedules.push({ time: tr[2], direction: 'from_kenkyuto_to_honbuto', destination: '科技大', routeLabel: '空港経由', platformNumber: null,  weekdayOnly: wdOnly, weekendOnly: weOnly, academicOnly: false, vacationOnly: false, arrivals: { honbuto: tr[3] } });
  });
}

/**
 * 系統1 復路（科技大 → 空港経由 → 千歳駅）
 *
 * データソース: 時刻表データ_系統1.csv「系統１ to 千歳駅」
 * フラグ行: 停留所名,☆,★,☆,★,,,,,☆,☆
 *
 * 授業期と学休期の差分は 15:24 便のみ。学休期は南千歳駅を経由しない。
 * それ以外の便は両期で同一。
 */
function buildRoute1Inbound(schedules) {
  var trips = [
    // [本部棟, 研究棟, 南千歳, 千歳, 運行日, 期別]
    // 運行日: B=毎日 / D=平日のみ / E=土日祝のみ
    // 期別:   ''=授業期・学休期共通 / A=授業期のみ / V=学休期のみ
    // 南千歳が null の便は南千歳駅を経由しない
    ['11:36', '11:39', '11:51', '12:02', 'D', ''],
    ['12:42', '12:45', '12:57', '13:08', 'E', ''],
    ['13:35', '13:38', '13:50', '14:01', 'D', ''],
    ['14:32', '14:35', '14:47', '14:58', 'E', ''],
    ['15:24', '15:27', '15:39', '15:50', 'B', 'A'],
    ['15:24', '15:27', null,    '15:50', 'B', 'V'],
    ['16:47', '16:50', '17:02', '17:13', 'B', ''],
    ['17:52', '17:55', '18:07', '18:18', 'B', ''],
    ['19:02', '19:05', '19:17', '19:28', 'B', ''],
    ['19:42', '19:45', '19:57', '20:08', 'D', ''],
    ['21:22', '21:25', '21:37', '21:48', 'D', ''],
  ];
  trips.forEach(function(tr) {
    var wdOnly = tr[4] === 'D', weOnly = tr[4] === 'E';
    var acOnly = tr[5] === 'A', vcOnly = tr[5] === 'V';
    var honbutoArrivals = { kenkyuto: tr[1] };
    var kenkyutoArrivals = {};
    if (tr[2]) {
      honbutoArrivals.minamiChitose = tr[2];
      kenkyutoArrivals.minamiChitose = tr[2];
    }
    honbutoArrivals.chitose = tr[3];
    kenkyutoArrivals.chitose = tr[3];
    schedules.push({ time: tr[0], direction: 'from_honbuto',             destination: '千歳駅', routeLabel: '空港経由', platformNumber: null, weekdayOnly: wdOnly, weekendOnly: weOnly, academicOnly: acOnly, vacationOnly: vcOnly, arrivals: honbutoArrivals });
    schedules.push({ time: tr[1], direction: 'from_kenkyuto_to_station', destination: '千歳駅', routeLabel: '空港経由', platformNumber: null, weekdayOnly: wdOnly, weekendOnly: weOnly, academicOnly: acOnly, vacationOnly: vcOnly, arrivals: kenkyutoArrivals });
  });
}

/**
 * 系統2 往路（千歳駅3番乗り場 → 直通 → 科技大）
 *
 * データソース: 時刻表データ_系統2.csv「系統2 to 本部棟」／美々空港線 時刻表 PDF
 * 全便平日のみ運行（土日祝の運行なし）
 *
 * 授業期（19便）と学休期（6便）で時刻が全く異なるため、両方を別便として登録し
 * academicOnly / vacationOnly で出し分ける。
 */
function buildRoute2Outbound(schedules) {
  var academicTrips = [
    // [千歳, 研究棟, 本部棟]
    ['07:14', '07:32', '07:35'],
    ['07:29', '07:47', '07:50'],
    ['08:04', '08:22', '08:25'],
    ['08:14', '08:32', '08:35'],
    ['08:19', '08:37', '08:40'],
    ['08:24', '08:42', '08:45'],
    ['08:29', '08:47', '08:50'],
    ['09:04', '09:22', '09:25'],
    ['09:19', '09:37', '09:40'],
    ['09:34', '09:52', '09:55'],
    ['09:44', '10:02', '10:05'],
    ['09:54', '10:12', '10:15'],
    ['10:04', '10:22', '10:25'],
    ['10:14', '10:32', '10:35'],
    ['14:24', '14:42', '14:45'],
    ['15:22', '15:40', '15:43'],
    ['15:55', '16:13', '16:16'],
    ['16:04', '16:22', '16:25'],
    ['17:51', '18:09', '18:12'],
  ];
  var vacationTrips = [
    // [千歳, 研究棟, 本部棟]
    ['08:10', '08:28', '08:31'],
    ['08:40', '08:58', '09:01'],
    ['09:10', '09:28', '09:31'],
    ['09:50', '10:08', '10:11'],
    ['16:00', '16:18', '16:21'],
    ['18:00', '18:18', '18:21'],
  ];
  pushRoute2Outbound(schedules, academicTrips, true,  false);
  pushRoute2Outbound(schedules, vacationTrips, false, true);
}

function pushRoute2Outbound(schedules, trips, academicOnly, vacationOnly) {
  trips.forEach(function(tr) {
    schedules.push({ time: tr[0], direction: 'from_chitose',             destination: '科技大', routeLabel: '直通', platformNumber: '3番', weekdayOnly: true, weekendOnly: false, academicOnly: academicOnly, vacationOnly: vacationOnly, arrivals: { kenkyuto: tr[1], honbuto: tr[2] } });
    schedules.push({ time: tr[1], direction: 'from_kenkyuto_to_honbuto', destination: '科技大', routeLabel: '直通', platformNumber: null,  weekdayOnly: true, weekendOnly: false, academicOnly: academicOnly, vacationOnly: vacationOnly, arrivals: { honbuto: tr[2] } });
  });
}

/**
 * 系統2 復路（科技大 → 直通 → 千歳駅）
 *
 * データソース: 時刻表データ_系統2.csv「系統2 to 千歳駅」／美々空港線 時刻表 PDF
 * 全便平日のみ運行（土日祝の運行なし）
 * 直通のため南千歳駅は経由しない
 *
 * 授業期（9便）と学休期（4便）で時刻が全く異なる。
 */
function buildRoute2Inbound(schedules) {
  var academicTrips = [
    // [本部棟, 研究棟, 千歳]
    ['11:02', '11:05', '11:24'],
    ['12:27', '12:30', '12:49'],
    ['13:07', '13:10', '13:29'],
    ['14:17', '14:20', '14:39'],
    ['15:02', '15:05', '15:24'],
    ['16:42', '16:45', '17:04'],
    ['17:02', '17:05', '17:24'],
    ['17:30', '17:33', '17:52'],
    ['18:27', '18:30', '18:49'],
  ];
  var vacationTrips = [
    // [本部棟, 研究棟, 千歳]
    ['12:32', '12:35', '12:54'],
    ['14:32', '14:35', '14:54'],
    ['17:32', '17:35', '17:54'],
    ['18:32', '18:35', '18:54'],
  ];
  pushRoute2Inbound(schedules, academicTrips, true,  false);
  pushRoute2Inbound(schedules, vacationTrips, false, true);
}

function pushRoute2Inbound(schedules, trips, academicOnly, vacationOnly) {
  trips.forEach(function(tr) {
    schedules.push({ time: tr[0], direction: 'from_honbuto',             destination: '千歳駅', routeLabel: '直通', platformNumber: null, weekdayOnly: true, weekendOnly: false, academicOnly: academicOnly, vacationOnly: vacationOnly, arrivals: { kenkyuto: tr[1], chitose: tr[2] } });
    schedules.push({ time: tr[1], direction: 'from_kenkyuto_to_station', destination: '千歳駅', routeLabel: '直通', platformNumber: null, weekdayOnly: true, weekendOnly: false, academicOnly: academicOnly, vacationOnly: vacationOnly, arrivals: { chitose: tr[2] } });
  });
}

/**
 * 系統3 往路（千歳駅5番乗り場 → 長都経由 → 科技大）
 *
 * データソース: 時刻表データ_系統3.csv「系統3 to 科技大」
 * フラグ行: ,,☆,☆  → col1=B, col2=D, col3=D
 * ※バスは長都駅東口発だが千歳駅前（5番）乗車起点として扱う
 */
function buildRoute3Outbound(schedules) {
  var trips = [
    // [千歳, 南千歳, 研究棟, 本部棟, フラグ]
    ['11:29', '11:40', '11:53', '11:54', 'B'],
    ['12:19', '12:30', '12:43', '12:44', 'D'],
    ['14:29', '14:40', '14:53', '14:54', 'D'],
  ];
  trips.forEach(function(tr) {
    var wdOnly = tr[4] === 'D', weOnly = tr[4] === 'E';
    schedules.push({ time: tr[0], direction: 'from_chitose',             destination: '科技大', routeLabel: '長都発', platformNumber: '5番', weekdayOnly: wdOnly, weekendOnly: weOnly, academicOnly: false, vacationOnly: false, arrivals: { minamiChitose: tr[1], kenkyuto: tr[2], honbuto: tr[3] } });
    schedules.push({ time: tr[1], direction: 'from_minami_chitose',      destination: '科技大', routeLabel: '長都発', platformNumber: null,  weekdayOnly: wdOnly, weekendOnly: weOnly, academicOnly: false, vacationOnly: false, arrivals: { kenkyuto: tr[2], honbuto: tr[3] } });
    schedules.push({ time: tr[2], direction: 'from_kenkyuto_to_honbuto', destination: '科技大', routeLabel: '長都発', platformNumber: null,  weekdayOnly: wdOnly, weekendOnly: weOnly, academicOnly: false, vacationOnly: false, arrivals: { honbuto: tr[3] } });
  });
}

/**
 * 系統3 復路（科技大 → 長都行き → 千歳駅）
 *
 * データソース: 時刻表データ_系統3.csv「系統3 to 千歳駅」
 * フラグ行なし → 全便 平日・休日ともに運行
 * ※バスは千歳駅前（4番）通過後に長都駅東口まで続行
 */
function buildRoute3Inbound(schedules) {
  var trips = [
    // [本部棟, 研究棟, 南千歳, 千歳]
    ['20:32', '20:35', '20:47', '21:00'],
    ['22:02', '22:05', '22:17', '22:30'],
  ];
  trips.forEach(function(tr) {
    schedules.push({ time: tr[0], direction: 'from_honbuto',             destination: '千歳駅', routeLabel: '長都行き', platformNumber: null, weekdayOnly: false, weekendOnly: false, academicOnly: false, vacationOnly: false, arrivals: { kenkyuto: tr[1], minamiChitose: tr[2], chitose: tr[3] } });
    schedules.push({ time: tr[1], direction: 'from_kenkyuto_to_station', destination: '千歳駅', routeLabel: '長都行き', platformNumber: null, weekdayOnly: false, weekendOnly: false, academicOnly: false, vacationOnly: false, arrivals: { minamiChitose: tr[2], chitose: tr[3] } });
  });
}

// ---- テスト用 ----

function testHardcoded() {
  var result = getHardcodedTimetable();
  Logger.log(JSON.stringify(result, null, 2));
}
