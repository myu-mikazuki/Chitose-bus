/**
 * 千歳科学技術大学 シャトルバス時刻表 GAS バックエンド
 * (美々エアポートライン対応 - 授業期ダイヤ固定実装)
 *
 * 系統1: 千歳駅（5番）→ 南千歳 → 空港 → 研究棟 → 本部棟
 * 系統2: 千歳駅（3番）→ 直通 → 研究棟 → 本部棟 (weekdayOnly)
 * 系統3: 長都駅 → 千歳駅（5番）→ 南千歳 → 空港 → 研究棟 → 本部棟
 */

var CACHE_KEY = 'bus_timetable_mibi_v1';
var CACHE_EXPIRY_SECONDS = 6 * 60 * 60; // 6時間

function doGet(e) {
  var cache = CacheService.getScriptCache();
  var cached = cache.get(CACHE_KEY);

  if (cached) {
    return buildResponse(cached);
  }

  try {
    var result = buildTimetable();
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

// ---- 時刻表データ（授業期ダイヤ）----
//
// weekdayOnly: 土日祝は運休（系統2全便、系統1/3の一部）☆
// weekendOnly: 土日祝のみ運行（系統1の一部）★
//
// 各エントリ:
//   { chitose, minamiChitose, kenkyuto, honbuto, weekdayOnly, weekendOnly }
// 復路エントリ:
//   { kenkyuto, honbuto, weekdayOnly, weekendOnly }

// 系統1 千歳駅発（5番） → 南千歳 → 空港 → 研究棟 → 本部棟
var ROUTE1_OUTBOUND = [
  { chitose: '7:20',  minamiChitose: '7:31',  kenkyuto: '7:44',  honbuto: '7:45',  weekdayOnly: false, weekendOnly: false },
  { chitose: '8:18',  minamiChitose: '8:29',  kenkyuto: '8:42',  honbuto: '8:43',  weekdayOnly: false, weekendOnly: true  },
  { chitose: '9:10',  minamiChitose: '9:21',  kenkyuto: '9:34',  honbuto: '9:35',  weekdayOnly: false, weekendOnly: true  },
  { chitose: '10:30', minamiChitose: '10:41', kenkyuto: '10:54', honbuto: '10:55', weekdayOnly: true,  weekendOnly: false },
  { chitose: '11:00', minamiChitose: '11:11', kenkyuto: '11:24', honbuto: '11:25', weekdayOnly: true,  weekendOnly: false },
  { chitose: '12:10', minamiChitose: '12:21', kenkyuto: '12:34', honbuto: '12:35', weekdayOnly: true,  weekendOnly: false },
  { chitose: '13:20', minamiChitose: '13:31', kenkyuto: '13:44', honbuto: '13:45', weekdayOnly: false, weekendOnly: false }
];

// 系統2 千歳駅発（3番） → 直通 → 研究棟 → 本部棟（全便weekdayOnly）
var ROUTE2_OUTBOUND = [
  { chitose: '7:14',  kenkyuto: '7:32',  honbuto: '7:35'  },
  { chitose: '7:29',  kenkyuto: '7:47',  honbuto: '7:50'  },
  { chitose: '8:04',  kenkyuto: '8:22',  honbuto: '8:25'  },
  { chitose: '8:14',  kenkyuto: '8:32',  honbuto: '8:35'  },
  { chitose: '8:19',  kenkyuto: '8:37',  honbuto: '8:40'  },
  { chitose: '8:24',  kenkyuto: '8:42',  honbuto: '8:45'  },
  { chitose: '8:29',  kenkyuto: '8:47',  honbuto: '8:50'  },
  { chitose: '9:04',  kenkyuto: '9:22',  honbuto: '9:25'  },
  { chitose: '9:19',  kenkyuto: '9:37',  honbuto: '9:40'  },
  { chitose: '9:34',  kenkyuto: '9:52',  honbuto: '9:55'  },
  { chitose: '9:44',  kenkyuto: '10:02', honbuto: '10:05' },
  { chitose: '9:54',  kenkyuto: '10:12', honbuto: '10:15' },
  { chitose: '10:04', kenkyuto: '10:22', honbuto: '10:25' },
  { chitose: '10:14', kenkyuto: '10:32', honbuto: '10:35' },
  { chitose: '14:24', kenkyuto: '14:42', honbuto: '14:45' },
  { chitose: '15:22', kenkyuto: '15:40', honbuto: '15:43' },
  { chitose: '15:55', kenkyuto: '16:13', honbuto: '16:16' },
  { chitose: '16:04', kenkyuto: '16:22', honbuto: '16:25' },
  { chitose: '17:51', kenkyuto: '18:09', honbuto: '18:12' }
];

// 系統3 長都駅 → 千歳駅（5番）→ 南千歳 → 空港 → 研究棟 → 本部棟
var ROUTE3_OUTBOUND = [
  { chitose: '11:29', minamiChitose: '11:40', kenkyuto: '11:53', honbuto: '11:54', weekdayOnly: false, weekendOnly: false },
  { chitose: '12:19', minamiChitose: '12:30', kenkyuto: '12:43', honbuto: '12:44', weekdayOnly: true,  weekendOnly: false },
  { chitose: '14:29', minamiChitose: '14:40', kenkyuto: '14:53', honbuto: '14:54', weekdayOnly: true,  weekendOnly: false }
];

// 系統1 大学発 → 空港 → 千歳駅（研究棟発・本部棟発）
var ROUTE1_INBOUND = [
  { kenkyuto: '11:39', honbuto: '11:36', weekdayOnly: true,  weekendOnly: false },
  { kenkyuto: '12:45', honbuto: '12:42', weekdayOnly: false, weekendOnly: true  },
  { kenkyuto: '13:38', honbuto: '13:35', weekdayOnly: true,  weekendOnly: false },
  { kenkyuto: '14:35', honbuto: '14:32', weekdayOnly: false, weekendOnly: true  },
  { kenkyuto: '15:27', honbuto: '15:24', weekdayOnly: false, weekendOnly: false },
  { kenkyuto: '16:50', honbuto: '16:47', weekdayOnly: false, weekendOnly: false },
  { kenkyuto: '17:55', honbuto: '17:52', weekdayOnly: false, weekendOnly: false },
  { kenkyuto: '19:05', honbuto: '19:02', weekdayOnly: false, weekendOnly: false },
  { kenkyuto: '19:45', honbuto: '19:42', weekdayOnly: true,  weekendOnly: false },
  { kenkyuto: '21:25', honbuto: '21:22', weekdayOnly: true,  weekendOnly: false }
];

// 系統2 大学発 → 直通 → 千歳駅（研究棟発・本部棟発、全便weekdayOnly）
var ROUTE2_INBOUND = [
  { kenkyuto: '11:05', honbuto: '11:02' },
  { kenkyuto: '12:30', honbuto: '12:27' },
  { kenkyuto: '13:10', honbuto: '13:07' },
  { kenkyuto: '14:20', honbuto: '14:17' },
  { kenkyuto: '15:05', honbuto: '15:02' },
  { kenkyuto: '16:45', honbuto: '16:42' },
  { kenkyuto: '17:05', honbuto: '17:02' },
  { kenkyuto: '17:33', honbuto: '17:30' },
  { kenkyuto: '18:30', honbuto: '18:27' }
];

// 系統3 大学発 → 長都駅（研究棟発・本部棟発、全便毎日）
var ROUTE3_INBOUND = [
  { kenkyuto: '20:35', honbuto: '20:32' },
  { kenkyuto: '22:05', honbuto: '22:02' }
];

// ---- 時刻フォーマット ----

function padTime(t) {
  var parts = t.split(':');
  var h = parseInt(parts[0], 10);
  var m = parseInt(parts[1], 10);
  return (h < 10 ? '0' + h : '' + h) + ':' + (m < 10 ? '0' + m : '' + m);
}

// ---- 時刻表組み立て ----

function buildTimetable() {
  var today = Utilities.formatDate(new Date(), 'Asia/Tokyo', 'yyyy-MM-dd');
  var schedules = [];

  // --- fromChitose: 系統1+2+3 の千歳駅発時刻（時刻順混在）---
  ROUTE1_OUTBOUND.forEach(function(e) {
    schedules.push({
      time: padTime(e.chitose),
      direction: 'from_chitose',
      destination: '本部棟',
      routeNumber: 1,
      platformNumber: 5,
      arrivals: { kenkyuto: padTime(e.kenkyuto), honbuto: padTime(e.honbuto) },
      weekdayOnly: e.weekdayOnly,
      weekendOnly: e.weekendOnly
    });
  });
  ROUTE2_OUTBOUND.forEach(function(e) {
    schedules.push({
      time: padTime(e.chitose),
      direction: 'from_chitose',
      destination: '本部棟',
      routeNumber: 2,
      platformNumber: 3,
      arrivals: { kenkyuto: padTime(e.kenkyuto), honbuto: padTime(e.honbuto) },
      weekdayOnly: true,
      weekendOnly: false
    });
  });
  ROUTE3_OUTBOUND.forEach(function(e) {
    schedules.push({
      time: padTime(e.chitose),
      direction: 'from_chitose',
      destination: '本部棟',
      routeNumber: 3,
      platformNumber: 5,
      arrivals: { kenkyuto: padTime(e.kenkyuto), honbuto: padTime(e.honbuto) },
      weekdayOnly: e.weekdayOnly,
      weekendOnly: e.weekendOnly
    });
  });

  // --- fromMinamiChitose: 系統1+3 の南千歳通過時刻 ---
  ROUTE1_OUTBOUND.forEach(function(e) {
    schedules.push({
      time: padTime(e.minamiChitose),
      direction: 'from_minami_chitose',
      destination: '本部棟',
      routeNumber: 1,
      arrivals: { kenkyuto: padTime(e.kenkyuto), honbuto: padTime(e.honbuto) },
      weekdayOnly: e.weekdayOnly,
      weekendOnly: e.weekendOnly
    });
  });
  ROUTE3_OUTBOUND.forEach(function(e) {
    schedules.push({
      time: padTime(e.minamiChitose),
      direction: 'from_minami_chitose',
      destination: '本部棟',
      routeNumber: 3,
      arrivals: { kenkyuto: padTime(e.kenkyuto), honbuto: padTime(e.honbuto) },
      weekdayOnly: e.weekdayOnly,
      weekendOnly: e.weekendOnly
    });
  });

  // --- fromKenkyutoToHonbuto: 系統1+2+3 の研究棟着時刻（大学行き） ---
  ROUTE1_OUTBOUND.forEach(function(e) {
    schedules.push({
      time: padTime(e.kenkyuto),
      direction: 'from_kenkyuto_to_honbuto',
      destination: '本部棟',
      routeNumber: 1,
      arrivals: { honbuto: padTime(e.honbuto) },
      weekdayOnly: e.weekdayOnly,
      weekendOnly: e.weekendOnly
    });
  });
  ROUTE2_OUTBOUND.forEach(function(e) {
    schedules.push({
      time: padTime(e.kenkyuto),
      direction: 'from_kenkyuto_to_honbuto',
      destination: '本部棟',
      routeNumber: 2,
      arrivals: { honbuto: padTime(e.honbuto) },
      weekdayOnly: true,
      weekendOnly: false
    });
  });
  ROUTE3_OUTBOUND.forEach(function(e) {
    schedules.push({
      time: padTime(e.kenkyuto),
      direction: 'from_kenkyuto_to_honbuto',
      destination: '本部棟',
      routeNumber: 3,
      arrivals: { honbuto: padTime(e.honbuto) },
      weekdayOnly: e.weekdayOnly,
      weekendOnly: e.weekendOnly
    });
  });

  // --- fromKenkyutoToStation: 系統1+2+3 の研究棟発時刻（大学発） ---
  ROUTE1_INBOUND.forEach(function(e) {
    schedules.push({
      time: padTime(e.kenkyuto),
      direction: 'from_kenkyuto_to_station',
      destination: '千歳駅',
      routeNumber: 1,
      arrivals: {},
      weekdayOnly: e.weekdayOnly,
      weekendOnly: e.weekendOnly
    });
  });
  ROUTE2_INBOUND.forEach(function(e) {
    schedules.push({
      time: padTime(e.kenkyuto),
      direction: 'from_kenkyuto_to_station',
      destination: '千歳駅',
      routeNumber: 2,
      arrivals: {},
      weekdayOnly: true,
      weekendOnly: false
    });
  });
  ROUTE3_INBOUND.forEach(function(e) {
    schedules.push({
      time: padTime(e.kenkyuto),
      direction: 'from_kenkyuto_to_station',
      destination: '長都駅',
      routeNumber: 3,
      arrivals: {},
      weekdayOnly: false,
      weekendOnly: false
    });
  });

  // --- fromHonbuto: 系統1+2+3 の本部棟着・本部棟発時刻 ---
  ROUTE1_OUTBOUND.forEach(function(e) {
    schedules.push({
      time: padTime(e.honbuto),
      direction: 'from_honbuto',
      destination: '本部棟',
      routeNumber: 1,
      arrivals: {},
      weekdayOnly: e.weekdayOnly,
      weekendOnly: e.weekendOnly
    });
  });
  ROUTE2_OUTBOUND.forEach(function(e) {
    schedules.push({
      time: padTime(e.honbuto),
      direction: 'from_honbuto',
      destination: '本部棟',
      routeNumber: 2,
      arrivals: {},
      weekdayOnly: true,
      weekendOnly: false
    });
  });
  ROUTE3_OUTBOUND.forEach(function(e) {
    schedules.push({
      time: padTime(e.honbuto),
      direction: 'from_honbuto',
      destination: '本部棟',
      routeNumber: 3,
      arrivals: {},
      weekdayOnly: e.weekdayOnly,
      weekendOnly: e.weekendOnly
    });
  });
  ROUTE1_INBOUND.forEach(function(e) {
    schedules.push({
      time: padTime(e.honbuto),
      direction: 'from_honbuto',
      destination: '千歳駅',
      routeNumber: 1,
      arrivals: {},
      weekdayOnly: e.weekdayOnly,
      weekendOnly: e.weekendOnly
    });
  });
  ROUTE2_INBOUND.forEach(function(e) {
    schedules.push({
      time: padTime(e.honbuto),
      direction: 'from_honbuto',
      destination: '千歳駅',
      routeNumber: 2,
      arrivals: {},
      weekdayOnly: true,
      weekendOnly: false
    });
  });
  ROUTE3_INBOUND.forEach(function(e) {
    schedules.push({
      time: padTime(e.honbuto),
      direction: 'from_honbuto',
      destination: '長都駅',
      routeNumber: 3,
      arrivals: {},
      weekdayOnly: false,
      weekendOnly: false
    });
  });

  // 方向ごと・時刻順ソート
  schedules.sort(function(a, b) {
    if (a.direction !== b.direction) return a.direction < b.direction ? -1 : 1;
    return a.time < b.time ? -1 : 1;
  });

  return {
    updatedAt: today,
    current: {
      validFrom: '2025-04-01',
      validTo: '2026-03-31',
      pdfUrl: '',
      schedules: schedules
    },
    upcoming: null
  };
}

// ---- テスト用 ----

function testBuildTimetable() {
  var result = buildTimetable();
  Logger.log(JSON.stringify(result, null, 2));
}

function clearCache() {
  CacheService.getScriptCache().remove(CACHE_KEY);
  Logger.log('Cache cleared');
}
