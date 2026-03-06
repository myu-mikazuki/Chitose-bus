/**
 * 千歳科学技術大学 シャトルバス時刻表 GAS バックエンド
 *
 * 事前準備:
 *   - GASプロジェクトの「サービス」→ Drive API を有効化（高度なGoogleサービス）
 *   - Webアプリとしてデプロイ（アクセス: 全員）
 */

var CACHE_KEY = 'bus_timetable_v4';
var CACHE_EXPIRY_SECONDS = 6 * 60 * 60; // 6時間
var CHITOSE_TOP_URL = 'https://www.chitose.ac.jp/info/access';
// URLエンコード済み「時刻表」= %E6%99%82%E5%88%BB%E8%A1%A8 を含むPDFを対象とする
var PDF_PATTERN_SRC = '\/uploads\/files\/[^"\'\\s]*%E6%99%82%E5%88%BB%E8%A1%A8[^"\'\\s]*\\.pdf';
// ファイル名末尾の _MMDD-MMDD.pdf 形式から有効期間を取得
var DATE_RANGE_PATTERN_FILENAME = /_(\d{2})(\d{2})-(\d{2})(\d{2})\.pdf/i;

function doGet(e) {
  var cache = CacheService.getScriptCache();
  var cached = cache.get(CACHE_KEY);

  if (cached) {
    return buildResponse(cached);
  }

  try {
    var result = fetchAndParseTimetable();
    var json = JSON.stringify(result);
    cache.put(CACHE_KEY, json, CACHE_EXPIRY_SECONDS);
    return buildResponse(json);
  } catch (err) {
    var errorBody = JSON.stringify({ error: err.message || String(err) });
    return ContentService
      .createTextOutput(errorBody)
      .setMimeType(ContentService.MimeType.JSON);
  }
}

function buildResponse(jsonString) {
  return ContentService
    .createTextOutput(jsonString)
    .setMimeType(ContentService.MimeType.JSON);
}

// ---- メイン処理 ----

function fetchAndParseTimetable() {
  var html = UrlFetchApp.fetch(CHITOSE_TOP_URL, { muteHttpExceptions: true }).getContentText('UTF-8');

  // グローバルフラグで全てのマッチを取得
  var re = new RegExp(PDF_PATTERN_SRC, 'gi');
  var pdfPaths = [];
  var m;
  while ((m = re.exec(html)) !== null) {
    if (pdfPaths.indexOf(m[0]) === -1) {
      pdfPaths.push(m[0]);
    }
  }

  if (pdfPaths.length === 0) {
    throw new Error('時刻表PDFが見つかりませんでした');
  }

  var today = Utilities.formatDate(new Date(), 'Asia/Tokyo', 'yyyy-MM-dd');
  var year = parseInt(today.substring(0, 4), 10);

  // 各PDFをパースしてtimetable配列を作成
  var timetables = pdfPaths.map(function(pdfPath) {
    return parsePdf(pdfPath, year, today);
  });

  // validFrom昇順でソート（古い→新しい）
  timetables.sort(function(a, b) {
    return a.validFrom < b.validFrom ? -1 : 1;
  });

  // current: 今日が有効期間内 or 最も近い将来のもの
  var current = null;
  var upcoming = null;

  for (var i = 0; i < timetables.length; i++) {
    var t = timetables[i];
    if (t.validFrom <= today && today <= t.validTo) {
      current = t;
    } else if (t.validFrom > today) {
      if (!upcoming) upcoming = t;
    }
  }
  // currentが見つからなければ最初のものを使用
  if (!current && timetables.length > 0) current = timetables[0];

  return {
    updatedAt: today,
    current: current,
    upcoming: upcoming
  };
}

function parsePdf(pdfPath, year, today) {
  var pdfUrl = 'https://www.chitose.ac.jp' + pdfPath;

  var validFrom = '';
  var validTo = '';
  var dateMatch = pdfPath.match(DATE_RANGE_PATTERN_FILENAME);
  if (dateMatch) {
    validFrom = year + '-' + pad(dateMatch[1]) + '-' + pad(dateMatch[2]);
    validTo   = year + '-' + pad(dateMatch[3]) + '-' + pad(dateMatch[4]);
  }

  var text = extractTextFromPdf(pdfUrl);
  var schedules = parseTimetableText(text);

  return {
    validFrom: validFrom,
    validTo: validTo,
    pdfUrl: pdfUrl,
    schedules: schedules
  };
}

function pad(n) {
  return String(parseInt(n, 10)).padStart(2, '0');
}

// ---- PDF → テキスト変換 ----

function extractTextFromPdf(pdfUrl) {
  var blob = UrlFetchApp.fetch(pdfUrl).getBlob().setContentType('application/pdf');
  var file = null;
  try {
    // Drive API v3: Files.create でPDF→Google Doc変換
    file = Drive.Files.create(
      { name: 'tmp_bus_timetable', mimeType: 'application/vnd.google-apps.document' },
      blob
    );
    var doc = DocumentApp.openById(file.id);
    return doc.getBody().getText();
  } finally {
    if (file) {
      try { Drive.Files.remove(file.id); } catch (e) { /* ignore */ }
    }
  }
}

// ---- テキストパース ----
//
// PDFをGoogle Docに変換すると、表の各セルが独立した行になる。
// 往路テーブルの列順: 千歳駅発 / 南千歳駅発 / 研究実験棟発 / 本部棟着 / 備考
// 復路テーブルの列順: 本部棟発 / 研究実験棟着 / 南千歳駅着 / 千歳駅着 / 備考
//
// 1便 = 最大5セル（列数）が空行で区切られたグループを形成する。
// グループ先頭の時刻 = その便の出発時刻として採用する。
//
// セクション検出:
//   「千歳駅発」が現れた行 → 往路（outbound）セクション開始
//   「本部棟発」が現れた行 → 復路（inbound）セクション開始
//   「有料バス」が現れた行 → シャトルバス以外なので以降を無視

function parseTimetableText(text) {
  var lines = text.split(/\r?\n/);
  var schedules = [];
  var section = null;
  var pendingTimes = [];

  function flushTrip() {
    if (pendingTimes.length === 0 || !section) {
      pendingTimes = [];
      return;
    }
    if (section === 'outbound') {
      var kenkyutoTime = pendingTimes.length > 2 ? pendingTimes[2] : null;
      var honbutoTime  = pendingTimes.length > 3 ? pendingTimes[3] : null;
      var outboundArrivals = {};
      if (kenkyutoTime) outboundArrivals['kenkyuto'] = kenkyutoTime;
      if (honbutoTime)  outboundArrivals['honbuto']  = honbutoTime;

      if (pendingTimes.length > 0)
        schedules.push({ time: pendingTimes[0], direction: 'from_chitose',        destination: '千歳科学技術大学', arrivals: outboundArrivals });
      if (pendingTimes.length > 1)
        schedules.push({ time: pendingTimes[1], direction: 'from_minami_chitose', destination: '千歳科学技術大学', arrivals: outboundArrivals });
      if (pendingTimes.length > 2) {
        var kenkyutoArrivals = {};
        if (honbutoTime) kenkyutoArrivals['honbuto'] = honbutoTime;
        schedules.push({ time: pendingTimes[2], direction: 'from_kenkyuto_to_honbuto', destination: '本部棟', arrivals: kenkyutoArrivals });
      }
    } else if (section === 'inbound') {
      if (pendingTimes.length > 0) {
        var honbutoArrivals = {};
        if (pendingTimes.length > 1) honbutoArrivals['kenkyuto']     = pendingTimes[1];
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

    if (/千歳駅発/.test(line)) {
      flushTrip();
      section = 'outbound';
      continue;
    }
    if (/本部棟発/.test(line)) {
      flushTrip();
      section = 'inbound';
      continue;
    }

    if (!section) continue;

    var timeMatch = line.match(/^(\d{1,2}):([0-5]\d)$/);
    if (timeMatch) {
      var hour = parseInt(timeMatch[1], 10);
      var minute = parseInt(timeMatch[2], 10);
      if (hour >= 6 && hour <= 22) {
        pendingTimes.push(pad(hour) + ':' + pad(minute));
      }
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

// ---- テスト用 ----

function testFetch() {
  var result = fetchAndParseTimetable();
  Logger.log(JSON.stringify(result, null, 2));
}

/** PDFリンク一覧を確認（どのPDFがマッチするか確認用） */
function testFindPdfLinks() {
  var html = UrlFetchApp.fetch(CHITOSE_TOP_URL, { muteHttpExceptions: true }).getContentText('UTF-8');
  var allPdfs = html.match(/\/uploads\/files\/[^"'\s]*\.pdf/gi) || [];
  Logger.log('全PDFリンク数: ' + allPdfs.length);
  allPdfs.forEach(function(p) { Logger.log(p); });

  var re = new RegExp(PDF_PATTERN_SRC, 'gi');
  var m;
  Logger.log('--- 時刻表PDF ---');
  while ((m = re.exec(html)) !== null) {
    Logger.log(m[0]);
  }
}

/** PDFのテキストだけを確認（パース前の生テキスト） */
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

function clearCache() {
  CacheService.getScriptCache().remove(CACHE_KEY);
  Logger.log('Cache cleared');
}
