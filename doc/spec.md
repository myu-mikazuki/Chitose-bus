# chitose_bus 仕様書

千歳の大学へのバス（千歳市路線バス 美々空港線）の時刻表を表示するFlutterアプリ。

---

## 概要

| 項目 | 内容 |
|------|------|
| アプリ名 | Kagi-Bus |
| バージョン | 0.1.0+2 |
| ターゲットプラットフォーム | iOS（主）、Android（主）、Web（副） |

---

## アーキテクチャ

Clean Architecture + MVVM。Riverpod で状態管理。

```
presentation/
  views/          # Widget（画面・部品）
  viewmodels/     # Riverpod Notifier（ビジネスロジックの橋渡し）
domain/
  entities/       # ビジネスモデル（BusEntry, BusTimetable, NotificationSettings）
  repositories/   # リポジトリ interface
  services/       # サービス interface
data/
  sources/        # 外部API（GAS）アクセス
  repositories/   # リポジトリ実装
  models/         # JSON デシリアライズ用モデル（freezed）
  services/       # 通知サービス実装
```

---

## バックエンド（Google Apps Script）

`gas/Code.gs`

- **エンドポイント**: GAS WebアプリのデプロイURL（`--dart-define=GAS_ENDPOINT_URL=...` でアプリに渡す）

#### スキーマバージョン（`?v=`）

GAS は Apps Script への手動デプロイ、アプリはストア審査を挟むリリースのため、
両者の反映タイミングは必ずずれる。さらに**更新しないユーザーの旧バージョンは
永続的に残る**。そのためリクエストの `?v=` でレスポンス形式を出し分ける。

| `v` | レスポンス | 絞り込み |
|-----|-----------|---------|
| 未指定 / `1` | 当日の期別に絞った便のみ。期別フラグを含まない | 期別は**サーバ側**、運行日はアプリ側 |
| `2` | 全便 + 期別フラグ | 両方**アプリ側** |

- アプリは `ScheduleRemoteSource.schemaVersion`（現在 `2`）を常に付与する。
  付けないと期別セレクタが機能しない
- `v=1` では年末年始に空の `schedules` を返す（旧アプリは運休を判定できないため）
- **新しい形式を足すときは `v` を増やし、既存の `v` の挙動は変えない**。
  これによりデプロイ順を気にせず GAS を更新できる
- GAS 側の期別判定（`seasonForYmd` / `isSuspendedYmd`）はアプリ側の
  `SeasonType.fromDate` / `ServiceCalendar.isSuspended` と**同一でなければならない**。
  `scripts/check_gas_season.js` が境界値を検証し、CI で実行される
- **処理内容**:
  1. `https://www.chitose.ac.jp/info/access` のHTMLをスクレイピング
  2. ファイル名に `%E6%99%82%E5%88%BB%E8%A1%A8`（「時刻表」）を含むPDFを抽出
  3. Google Drive APIでPDF→Google Doc変換し、テキストを取得（変換後のDocは即削除）
  4. テキストをパースして時刻・方面・到着時刻を構造化
  5. CacheService に6時間キャッシュして返却

- **レスポンス形式**:
```json
{
  "updatedAt": "2025-03-08",
  "current": {
    "validFrom": "2025-03-01",
    "validTo": "2025-03-31",
    "pdfUrl": "https://www.chitose.ac.jp/uploads/files/...",
    "schedules": [
      {
        "time": "08:10",
        "direction": "from_chitose",
        "destination": "科技大",
        "arrivals": { "kenkyuto": "08:35", "honbuto": "08:40" }
      }
    ]
  },
  "upcoming": { ... }  // 翌週以降のダイヤが公開済みの場合のみ
}
```

- **方面 `direction` の値**:

| 値 | 意味 |
|----|------|
| `from_chitose` | 千歳駅 → 科技大 |
| `from_minami_chitose` | 南千歳駅 → 科技大 |
| `from_kenkyuto_to_honbuto` | 研究棟 → 本部棟 |
| `from_kenkyuto_to_station` | 研究棟 → 千歳駅 |
| `from_honbuto` | 本部棟 → 千歳駅 |

- **有効期間の取得**: PDFファイル名の `_MMDD-MMDD.pdf` パターンから年内日付として解釈

---

## Flutterアプリ

### 画面構成

#### ホーム画面（`HomeScreen`）

タブバー4タブ構成：

| タブ | 表示内容 |
|------|----------|
| 千歳駅 | `from_chitose` の次バス・本日の時刻表 |
| 南千歳 | `from_minami_chitose` の次バス・本日の時刻表 |
| 研究棟 | `from_kenkyuto_to_honbuto` と `from_kenkyuto_to_station` の次バス・本日の時刻表 |
| 本部棟 | `from_honbuto` の次バス・本日の時刻表 |

AppBar のアクション：
- **時刻表原文ボタン**（`open_in_browser`）: `pdfUrl` が存在する場合のみ表示。ブラウザでPDFを開く
- **来週のダイヤボタン**（`calendar_month`）: `upcoming` が存在する場合のみ表示。モーダルボトムシートで全方面の来週ダイヤを表示
- **通知設定ボタン**（`notifications_outlined`）: 通知設定画面へ遷移
- **更新ボタン**（`refresh`）: スケジュールを手動再取得
- **デバッグ時刻ボタン**（`access_time`）: `kDebugMode` のみ表示（後述）

#### 通知設定画面（`NotificationSettingsScreen`）

- 出発通知の ON/OFF スイッチ（ON 時に iOS パーミッションダイアログを表示）
- 通知タイミング選択: 5 / 10 / 15 / 30 分前
- 通知する路線選択: 5方面から1つ選択
- 設定は `SharedPreferences` に永続化（キー: `notif_enabled`, `notif_minutes_before`, `notif_direction`）

---

### ウィジェット

#### `NextBusDisplay`
- `countdownProvider`（30秒ごとに更新）を watch し、次のバスを表示
- 出発時刻を大フォント（64px）で表示
- カウントダウン: 0分以下→「発車中」、1〜59分→「あと n 分」、60分以上→「あと h:mm」
- 5分以内は赤色、それ以上は黄色
- `arrivals` データがあれば到着時刻も表示
- 当日の運行終了時は「本日の運行は終了しました」

#### `ScheduleList`
- 指定方面の本日全便を一覧表示（実装詳細は `schedule_list.dart` 参照）

#### `WeekendWarningBanner`
- 土日は「土日祝日はバスが運行していない場合があります」を黄色バナーで表示
- 現在は `_enabled = false` で表示を無効化中

#### `SeasonNoticeBanner`
- 学休期は「学休期ダイヤで運行中です（直通便が減便されます）」を表示
- 年末年始（12/31〜1/3）は「年末年始（12/31〜1/3）は全便運休です」を表示
- 当日以外のダイヤ表示中は、期別セレクタが別途出るため非表示

---

### ダイヤの絞り込み（運行日 × 期別）

各便は4つのフラグを持つ。

| フラグ | 意味 |
|--------|------|
| `weekdayOnly` | 平日のみ運行 |
| `weekendOnly` | 土日祝のみ運行 |
| `academicOnly` | 授業期のみ運行 |
| `vacationOnly` | 学休期のみ運行 |

いずれも未指定（false）なら両方で運行する。`BusEntry.runsOn(DayType, SeasonType)`
が両軸を AND で評価する。

#### `DayType`（運行日）

土日は `weekendHoliday`、それ以外は `weekday`。

> **未対応**: 祝日判定は未実装のため、平日に当たる祝日は `weekday` として扱われる。
> なお 4/29・7/20・10/12・11/3・11/23 は「祝日だが平日ダイヤ」と時刻表に明記
> されているため、これらの日は結果的に正しく動作する。

#### `SeasonType`（期別 / Issue #132）

大学の学休期間中、美々空港線は「学休期ダイヤ」で運行する。

| 期間 | 対象 |
|------|------|
| 夏季 | 8月第1月曜日 〜 9月第4週金曜日 |
| 冬季 | 2月第1月曜日 〜 3月31日 |
| お盆 | 8/13 〜 8/16 |

「9月第4週金曜日」は第4金曜日として実装している（9月1日が土曜日の年のみ
両解釈が1週ずれる）。

学休期の主な差分:
- **直通（直17）**: 往路 19便 → 6便、復路 9便 → 4便に大幅減便
- **空港経由（空17）**: 15:24 本部棟発が南千歳駅を経由しなくなる
- それ以外の便は授業期と同一

#### `ServiceCalendar`（特例日）

年末年始（12/31〜1/3）は全便運休。`todayBuses()` は空リストを返し、
`isRunningToday()` は常に false を返す。

---

### 状態管理（Riverpod）

| Provider | 型 | 説明 |
|----------|----|------|
| `scheduleViewModelProvider` | `AsyncNotifier<ScheduleResponse>` | GAS APIからスケジュール取得・30分ごと自動更新 |
| `countdownProvider` | `StateNotifier<DateTime>` | 現在時刻（30秒更新）。`debugTimeProvider` が設定されていればその値を使用 |
| `debugTimeProvider` | `StateProvider<DateTime?>` | デバッグ用時刻オーバーライド（`null` = 実時刻） |
| `dayTypeOverrideProvider` | `StateProvider<DayType?>` | 当日以外のダイヤ表示（`null` = 当日表示） |
| `seasonOverrideProvider` | `StateProvider<SeasonType?>` | 当日以外表示での期別。`dayTypeOverrideProvider` と同時に設定・解除される |
| `notificationSettingsProvider` | `AsyncNotifier<NotificationSettings>` | 通知設定の読み込み・保存 |
| `notificationServiceProvider` | `Provider<NotificationService>` | `LocalNotificationService.instance` |

---

### 通知機能

`flutter_local_notifications` を使用。

- **スケジュール登録**: スケジュールデータ取得後、設定された方面の次の3便分をスケジュール登録
- **通知チャンネル** (Android): `bus_departure` /「バス出発通知」
- **通知内容**: タイトル「バスが出発します」、本文「N分後に〇〇行きバスが出発します」
- **タイムゾーン**: `Asia/Tokyo` 固定
- **通知 ID**: `bus.time.hashCode & 0x7FFFFFFF`
- **iOS 設定**: 初期化時にパーミッション要求しない（スイッチ ON 時に明示的に要求）

---

### デバッグ機能（`kDebugMode` のみ）

`debugTimeProvider` で任意の時刻を設定できる。

- AppBar の時計アイコンをタップ → TimePicker で時刻を選択
- オーバーライド中はアイコンが黄色に変わる
- タップ→ダイアログ → 「リセット」で実時刻に戻す / 「変更」で再設定

この時刻は `countdownProvider` と `BusTimetable.nextBus()` の計算に反映されるため、任意の時間帯のバス表示を確認できる。

---

## ビルド設定

### dart-define

コンパイル時定数として渡す必要がある：

| キー | 説明 |
|------|------|
| `GAS_ENDPOINT_URL` | GAS WebアプリのデプロイURL |

`.dart_defines` ファイル（リポジトリルート直下、`.gitignore` 済み）に記載し、以下のように指定：

```bash
flutter run --dart-define-from-file ../.dart_defines
flutter build ios --dart-define-from-file ../.dart_defines
```

`.dart_defines` の形式：
```json
{
  "GAS_ENDPOINT_URL": "https://script.google.com/macros/s/.../exec"
}
```

### iOS 要件

- Deployment Target: iOS 14.0+（`google_mobile_ads` 依存）
- 通知使用のため `NSUserNotificationUsageDescription` が必要

---

## 主要な依存パッケージ

| パッケージ | 用途 |
|------------|------|
| `flutter_riverpod` | 状態管理 |
| `http` | GAS API通信 |
| `freezed` / `json_serializable` | JSON モデル生成 |
| `flutter_local_notifications` | ローカル通知 |
| `shared_preferences` | 通知設定の永続化 |
| `timezone` | タイムゾーン付きスケジュール通知 |
| `url_launcher` | PDFをブラウザで開く |
| `intl` | 日時フォーマット |
