/**
 * 千歳科学技術大学 シャトルバス時刻表 GAS バックエンド
 *
 * 事前準備:
 *   - Webアプリとしてデプロイ（アクセス: 全員）
 */

var CACHE_KEY = 'bus_timetable_v5';
var CACHE_EXPIRY_SECONDS = 6 * 60 * 60; // 6時間

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
  var cache = CacheService.getScriptCache();
  var cached = cache.get(CACHE_KEY);
  if (cached) return buildResponse(cached);
  try {
    var result = getHardcodedTimetable();
    var json = JSON.stringify(result);
    cache.put(CACHE_KEY, json, CACHE_EXPIRY_SECONDS);
    return buildResponse(json);
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

// ---- ハードコード時刻表 ----

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
    schedules.push({ time: tr[0], direction: 'from_chitose',             destination: '科技大', routeLabel: '空港経由', platformNumber: '5番', weekdayOnly: wdOnly, weekendOnly: weOnly, arrivals: { minamiChitose: tr[1], kenkyuto: tr[2], honbuto: tr[3] } });
    schedules.push({ time: tr[1], direction: 'from_minami_chitose',      destination: '科技大', routeLabel: '空港経由', platformNumber: null,  weekdayOnly: wdOnly, weekendOnly: weOnly, arrivals: { kenkyuto: tr[2], honbuto: tr[3] } });
    schedules.push({ time: tr[2], direction: 'from_kenkyuto_to_honbuto', destination: '科技大', routeLabel: '空港経由', platformNumber: null,  weekdayOnly: wdOnly, weekendOnly: weOnly, arrivals: { honbuto: tr[3] } });
  });
}

/**
 * 系統1 復路（科技大 → 空港経由 → 千歳駅）
 *
 * データソース: 時刻表データ_系統1.csv「系統１ to 千歳駅」
 * フラグ行: 停留所名,☆,★,☆,★,,,,,☆,☆
 */
function buildRoute1Inbound(schedules) {
  var trips = [
    // [本部棟, 研究棟, 南千歳, 千歳, フラグ]
    ['11:36', '11:39', '11:51', '12:02', 'D'],
    ['12:42', '12:45', '12:57', '13:08', 'E'],
    ['13:35', '13:38', '13:50', '14:01', 'D'],
    ['14:32', '14:35', '14:47', '14:58', 'E'],
    ['15:24', '15:27', '15:39', '15:50', 'B'],
    ['16:47', '16:50', '17:02', '17:13', 'B'],
    ['17:52', '17:55', '18:07', '18:18', 'B'],
    ['19:02', '19:05', '19:17', '19:28', 'B'],
    ['19:42', '19:45', '19:57', '20:08', 'D'],
    ['21:22', '21:25', '21:37', '21:48', 'D'],
  ];
  trips.forEach(function(tr) {
    var wdOnly = tr[4] === 'D', weOnly = tr[4] === 'E';
    schedules.push({ time: tr[0], direction: 'from_honbuto',             destination: '千歳駅', routeLabel: '空港経由', platformNumber: null, weekdayOnly: wdOnly, weekendOnly: weOnly, arrivals: { kenkyuto: tr[1], minamiChitose: tr[2], chitose: tr[3] } });
    schedules.push({ time: tr[1], direction: 'from_kenkyuto_to_station', destination: '千歳駅', routeLabel: '空港経由', platformNumber: null, weekdayOnly: wdOnly, weekendOnly: weOnly, arrivals: { minamiChitose: tr[2], chitose: tr[3] } });
  });
}

/**
 * 系統2 往路（千歳駅3番乗り場 → 直通 → 科技大）
 *
 * データソース: 時刻表データ_系統2.csv「系統2 to 本部棟」
 * フラグ行なし → 全便 平日・休日ともに運行
 */
function buildRoute2Outbound(schedules) {
  var trips = [
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
  trips.forEach(function(tr) {
    schedules.push({ time: tr[0], direction: 'from_chitose',             destination: '科技大', routeLabel: '直通', platformNumber: '3番', weekdayOnly: false, weekendOnly: false, arrivals: { kenkyuto: tr[1], honbuto: tr[2] } });
    schedules.push({ time: tr[1], direction: 'from_kenkyuto_to_honbuto', destination: '科技大', routeLabel: '直通', platformNumber: null,  weekdayOnly: false, weekendOnly: false, arrivals: { honbuto: tr[2] } });
  });
}

/**
 * 系統2 復路（科技大 → 直通 → 千歳駅）
 *
 * データソース: 時刻表データ_系統2.csv「系統2 to 千歳駅」
 * フラグ行なし → 全便 平日・休日ともに運行
 * 直通のため南千歳駅は経由しない
 */
function buildRoute2Inbound(schedules) {
  var trips = [
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
  trips.forEach(function(tr) {
    schedules.push({ time: tr[0], direction: 'from_honbuto',             destination: '千歳駅', routeLabel: '直通', platformNumber: null, weekdayOnly: false, weekendOnly: false, arrivals: { kenkyuto: tr[1], chitose: tr[2] } });
    schedules.push({ time: tr[1], direction: 'from_kenkyuto_to_station', destination: '千歳駅', routeLabel: '直通', platformNumber: null, weekdayOnly: false, weekendOnly: false, arrivals: { chitose: tr[2] } });
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
    schedules.push({ time: tr[0], direction: 'from_chitose',             destination: '科技大', routeLabel: '長都発', platformNumber: '5番', weekdayOnly: wdOnly, weekendOnly: weOnly, arrivals: { minamiChitose: tr[1], kenkyuto: tr[2], honbuto: tr[3] } });
    schedules.push({ time: tr[1], direction: 'from_minami_chitose',      destination: '科技大', routeLabel: '長都発', platformNumber: null,  weekdayOnly: wdOnly, weekendOnly: weOnly, arrivals: { kenkyuto: tr[2], honbuto: tr[3] } });
    schedules.push({ time: tr[2], direction: 'from_kenkyuto_to_honbuto', destination: '科技大', routeLabel: '長都発', platformNumber: null,  weekdayOnly: wdOnly, weekendOnly: weOnly, arrivals: { honbuto: tr[3] } });
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
    schedules.push({ time: tr[0], direction: 'from_honbuto',             destination: '千歳駅', routeLabel: '長都行き', platformNumber: null, weekdayOnly: false, weekendOnly: false, arrivals: { kenkyuto: tr[1], minamiChitose: tr[2], chitose: tr[3] } });
    schedules.push({ time: tr[1], direction: 'from_kenkyuto_to_station', destination: '千歳駅', routeLabel: '長都行き', platformNumber: null, weekdayOnly: false, weekendOnly: false, arrivals: { minamiChitose: tr[2], chitose: tr[3] } });
  });
}

// ---- テスト用 ----

function testHardcoded() {
  var result = getHardcodedTimetable();
  Logger.log(JSON.stringify(result, null, 2));
}

function clearCache() {
  CacheService.getScriptCache().remove(CACHE_KEY);
  Logger.log('Cache cleared');
}
