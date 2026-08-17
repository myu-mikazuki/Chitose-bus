# chitose_bus 仕様書

千歳の大学へのバス（千歳市路線バス 美々空港線）の時刻表を表示するFlutterアプリ。

---

## 概要

| 項目 | 内容 |
|------|------|
| アプリ名 | Kagi-Bus |
| バージョン | `flutter_app/pubspec.yaml` を参照（ここには書かない） |
| ターゲットプラットフォーム | iOS（主）、Android（主）、Web（副） |

> バージョンをこの表に書くと更新漏れで嘘になる（実際 `0.1.0+2` のまま放置されていた）。
> 唯一の情報源は `pubspec.yaml`。リリース履歴は [`README.md`](../README.md) を参照。

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
永続的に残る**。そのためリクエストの `?v=` で応答を出し分ける。

> [!IMPORTANT]
> **`v` はレスポンスの「形式」ではなく、アプリが持つ判定ロジックの世代を表す。**
> GAS は古い `v` に対して、そのアプリが判定できない分をサーバ側で絞ってから返す。

| `v` | アプリが判定できるもの | GAS がサーバ側で絞るもの | 応答の形 |
|-----|---------------------|----------------------|---------|
| 未指定 / `1` | 運行日（土日のみ） | 期別・祝日（期別フラグも除去） | 旧形式 |
| `2` | 運行日（土日のみ）・期別 | 祝日 | 旧形式 |
| `3` | 運行日・期別・**祝日** | なし（全便を返す） | 旧形式 |
| `4` | `v=3` と同じ + **任意の停留所** | なし | **新形式**（後述） |

- アプリは `ScheduleRemoteSource.schemaVersion` を常に付与する。
  **現在の値は `3`**。GAS 側の `v=4` は実装済みだが、アプリが送り始めるのは
  乗車地選択の UI を入れるとき（#177 のアプリ側対応）
- `v=1` では年末年始に空の `schedules` を返す（旧アプリは運休を判定できないため）
- `v=2` / `v=3` は平日・土日には全便を返す（「当日以外のダイヤ」表示のため）。
  `v=2` のみ、祝日の日だけ運行日で絞って運行日フラグを落とす

> **アプリ側に新しい判定ロジックを足したら `v` を増やすこと。**
> 祝日判定（#158）は v1.2.0 のリリース後に追加したため、`v=2` を送る v1.2.0 は
> 祝日を判定できない。`v=2` の挙動をそのままにしていたら、8/11（山の日）に
> 千歳駅発が 5便 のところ 14便 表示されるところだった。
> 既存の `v` の挙動は変えず、新しい `v` を足して対応する。

- GAS 側の判定（`seasonForYmd` / `isSuspendedYmd` / `dayTypeForYmd`）はアプリ側の
  `SeasonType.fromDate` / `ServiceCalendar.isSuspended` / `DayType.fromDate` と
  **同一でなければならない**。`scripts/check_gas_season.js` が境界値と
  バージョンごとの出し分けを検証し、CI で実行される
- `scripts/check_gas_response.js` が `doGet` の応答をスナップショットと比較する。
  **`v<=3` の応答は1バイトも変えてはいけない**（旧アプリは永久に残るため）。
  便テーブルの整合性（停留所順に時刻が非減少であること等）もここで見る
- **処理内容**: 時刻表は `gas/Code.gs` にハードコードされており、`doGet` は
  **外部 I/O なし**で応答を組み立てる。キャッシュも持たない

この設計には理由がある。

- **外部 I/O が無い** … 応答が速く、大学サイトや Drive の障害に引きずられない
- **キャッシュが無い** … 再デプロイすれば即座に反映される。かつて `CacheService` に
  6時間キャッシュしていたが、コードを更新しても旧データが配信され続ける事故が
  起きたため廃止した（#153）

時刻表データは千歳市および大学が公開する美々空港線の時刻表をもとに**手動で更新**する。
かつては大学サイトから PDF を自動取得・解析していたが現在は使っておらず、
該当コードは `gas/Code.gs` にブロックコメントとして残置されている。

> 自動取得の再開は #146（増便情報の取得）で検討中。ただし時刻表本体の
> 自動反映は誤りが本番に直行するため、PR を作成して人がレビューする方式を想定している。

- **レスポンス形式**（`?v=3` の例）:
```json
{
  "updatedAt": "2026-08-08",
  "current": {
    "validFrom": "2025-04-01",
    "validTo": "2099-12-31",
    "schedules": [
      {
        "time": "07:20",
        "direction": "from_chitose",
        "destination": "科技大",
        "routeLabel": "空港経由",
        "platformNumber": "5番",
        "weekdayOnly": false,
        "weekendOnly": false,
        "academicOnly": false,
        "vacationOnly": false,
        "arrivals": {
          "minamiChitose": "07:31",
          "kenkyuto": "07:44",
          "honbuto": "07:45"
        }
      }
    ]
  },
  "upcoming": null
}
```

| フィールド | 内容 |
|-----------|------|
| `updatedAt` | 応答を生成した日付（JST）。期別・運行日の判定にも使う |
| `validFrom` / `validTo` | 時刻表の有効期間。現在は `2025-04-01` 〜 `2099-12-31` 固定 |
| `routeLabel` | `空港経由` / `直通` / `長都発` / `長都行き`。アプリでタグ表示する |
| `platformNumber` | 千歳駅ののりば（`5番` / `3番`）。乗車地が千歳駅のときのみ表示。旧形式では千歳駅発の便しか乗車地にならないため 4番 は現れない |
| `arrivals` | 経由地の到着時刻。キーは `chitose` / `minamiChitose` / `kenkyuto` / `honbuto` |
| `upcoming` | 翌週以降のダイヤ。現在は常に `null` |

`pdfUrl` は返していない（スクレイピング廃止に伴い廃止）。アプリ側の
`BusTimetable.pdfUrl` は空文字のままで、時刻表原文ボタンは表示されない。

### 新形式（`?v=4` / Issue #177）

`v=4` は**任意の停留所を乗車地として選べる**形式。旧形式が1便を乗車地ごとに展開して
いたのに対し、**1便を1件**とし、停留所と時刻の並びをそのまま返す。

> [!NOTE]
> **GAS 側のみ実装済み。**現在アプリが送るのは `v=3` で、この形式はまだ使っていない。
> アプリ側（設定画面での乗車地選択・タブ生成・`BusDirection` の廃止）は #177 の続きで対応する。
> なお GAS を先にデプロイしないと、`v=4` を送るアプリが旧形式を受け取って動かない。

旧形式のままで全停留所に広げると、停留所 n 個に対し `n(n-1)/2` 組の到着時刻を持つ
ことになり、全31停留所では**約1MB** に膨れる。新形式は O(n) で、全停留所でも約35KB。
デフォルトの4停留所なら約17KB で、旧形式の約31KB より小さい。

#### `?stops=`

カンマ区切りの停留所 ID で、返す停留所を絞る。

| 指定 | 応答 |
|------|------|
| 省略 | 全停留所（ブラウザで開いて確認する用途にも使える） |
| `?stops=chitose,morimoto` | その2停留所だけ |
| 知らない ID を含む | 知らない ID は黙って捨てる |
| 全部が知らない ID | 全停留所（空の時刻表を返さない） |

選んだ停留所を1つも通らない便は返さない。

> `?v=` と `?stops=` は役割が別。`v` は**アプリが持つ判定ロジックの世代**、
> `stops` は**単なる絞り込み**。「`stops` があれば新形式」という暗黙の結合にすると、
> アプリが `stops` を送らなかったとき（選択が空・不具合）に旧形式が返って壊れる。

```json
{
  "updatedAt": "2026-06-17",
  "stopMaster": [
    { "id": "chitose", "label": "千歳駅前", "shortLabel": "千歳駅" },
    { "id": "morimoto", "label": "もりもと本店前", "shortLabel": "もりもと" },
    { "id": "rapidus", "label": "ラピダス前", "shortLabel": "ラピダス", "boardable": false }
  ],
  "current": {
    "validFrom": "2025-04-01",
    "validTo": "2099-12-31",
    "trips": [
      {
        "destination": "科技大",
        "routeLabel": "空港経由",
        "terminus": "honbuto",
        "weekdayOnly": false,
        "weekendOnly": false,
        "academicOnly": false,
        "vacationOnly": false,
        "stops": [
          { "id": "chitose", "time": "07:20", "platform": "5番" },
          { "id": "morimoto", "time": "07:23" },
          { "id": "kenkyuto", "time": "07:44" },
          { "id": "honbuto", "time": "07:45" }
        ]
      }
    ]
  },
  "upcoming": null
}
```

| フィールド | 内容 |
|-----------|------|
| `stopMaster` | **全停留所**の一覧（`?stops=` の絞り込みに関わらず常に全件）。設定画面の選択肢がここから来るため |
| `boardable` | `false` のときだけ現れる。乗車地の選択肢から外す停留所 |
| `shortLabel` | タブなど幅の狭い場所で使う短縮名。正式名と同じなら**返さない**ので、アプリ側は `shortLabel ?? label` で解決する |
| `terminus` | その便の終点。**一般に降りられる最後の停留所**の ID |
| `trips[].stops` | その便が通る停留所と時刻の並び（通過順） |
| `platform` | のりば。便ではなく**停留所ごと**の属性 |

千歳駅ののりばは系統によって違う。

| 系統 | のりば | 備考 |
|------|--------|------|
| 系統1 往路（空港経由） | `5番` | |
| 系統2 往路（直通） | `3番` | |
| 系統3 往路（長都発） | `5番` | |
| 系統3 復路（長都行き） | `4番` | **千歳駅が途中停留所**で、ここから長都方面へ乗車できる |
| 系統1・系統2 復路 | なし | 千歳駅が終点（西口降専・降車専用）で乗車地にならない |

系統3復路の `4番` は `v=4` で初めて意味を持つ。旧形式では千歳駅発の便しか
乗車地として展開しないため、この便の千歳駅は到着としてしか現れなかった。

`stopMaster` から `rapidus` を省くことはできない。ラベルの供給元がここしか無く、
省くと `trips[].stops` に出てくる `rapidus` の表示名が引けなくなる。

> **`terminus` を `stops` の末尾から導かないこと。** `stops` は `?stops=` で
> 絞られているため、選んだ停留所によって末尾が変わる。イオン千歳店前を足すと
> 長都行きの終点がそこになってしまう（#177 で実際に起きた）。
> GAS は**絞り込みの前に**便の並び全体から決めている。
>
> また `terminus` は並びの末尾そのものでもない。**一般に降りられる最後の停留所**を返す。
> 系統1・2・3 の往路はラピダス前で終わるが、そこは `boardable: false` なので
> 終点は科技大本部棟になる。アプリはこれを「→ 本部棟」のように行き先の見出しに使う。

| 系統 | 並びの末尾 | `terminus` |
|------|-----------|-----------|
| 系統1・2・3 往路 | ラピダス前 | `honbuto`（科技大本部棟） |
| 系統1・2 復路 | 千歳駅前 | `chitose`（千歳駅前） |
| 系統3 復路（長都行き） | 長都駅東口 | `osatsu`（長都駅東口） |

> **`shortLabel` は全停留所に付けてある**（#207）。正式名（最長 143px）はタブに入らず、
> 頭の1〜2文字しか出ないため。ラベルに使える幅は実測で **4タブ 45.8px・上限の5タブ
> 27.0px**（375px 端末）。**全角3字（33px）が目安**で、4字は上限ぎりぎり。
> 5タブではどの短縮名も1字＋`…`に切れる（#204）。
>
> **正式名に無い言葉を足さないこと。** 削るだけで作る — 末尾の「前」「入口」「東口」
> などを落とす（長都駅東口 → 長都駅）、「N丁目」は地名＋N にして地名が長ければそれも
> 削る（朝日町4丁目 → 朝日4）、区別に効かない頭を落とす（空港国内線28番 → 国内28）、
> 種別を表す語は頭だけ残すか落とす（古泉循環器内科クリニック前 → 古泉）。出典の無い
> 略称を発明すると、利用者が実際のバス停の表記と対応付けられなくなる。例外は
> `arcadia`（オフィス・アルカディア入口 → `O･A入口`）だけ。
>
> **31件で重複させないこと。** 同時に最大5停留所がタブに並ぶ。
> 全件必須・重複なし・正式名と別・全角4字以内は `scripts/check_gas_response.js` が見る。

> **`shortLabel` はタブ専用ではない。** アプリは `labelOf`（= `shortLabel ?? label`）を
> 次の5箇所で共有しているため、短縮名を付けた停留所はタブ以外にも短い名前で出る。
>
> | 出る場所 | 幅 |
> |---|---|
> | タブ（`home_screen.dart`） | **足りない**（4タブ 45.8px）。短縮名が要る理由 |
> | 行き先の見出し「→ ◯◯」（`home_screen.dart`） | 足りている |
> | NEXT BUS カードの行き先・「◯◯ 着」（`next_bus_display.dart`） | 足りている |
> | 時刻表リストの「◯◯ 着」（`schedule_list.dart`） | 足りている |
>
> つまり `古泉循環器内科クリニック前 着` は **`古泉 着`** と出る。幅が足りている
> 場所にまで短縮名が及ぶので、**短縮名だけでどの停留所か伝わるか**で選ぶこと。
>
> 正式名（`label`）が出るのは設定画面だけで、そこでは「タブ表示: ◯◯」と短縮名を
> 併記している。出し分けたい場合は `labelOf` の呼び出し側を分ける必要がある（#208）。

> **ラピダス前は一般利用できない。** 「終点『ラピダス前』は工場敷地内のため、
> 関係者以外の方はご利用できません」（大学配付物）。時刻は実在するのでデータとしては
> 持つが、`boardable: false` を見て選択肢から外す。

- **方面 `direction` の値**（旧形式のみ）:

| 値 | 意味 |
|----|------|
| `from_chitose` | 千歳駅 → 科技大 |
| `from_minami_chitose` | 南千歳駅 → 科技大 |
| `from_kenkyuto_to_honbuto` | 研究棟 → 本部棟 |
| `from_kenkyuto_to_station` | 研究棟 → 千歳駅 |
| `from_honbuto` | 本部棟 → 千歳駅 |

- **お問い合わせの受信（`doPost`）**: お問い合わせ画面から送信された内容を
  スプレッドシートに追記し、メールで通知する。宛先などはスクリプトプロパティ
  （`BUG_REPORT_SHEET_ID` / `BUG_REPORT_NOTIFY_EMAIL` / `BUG_REPORT_FROM_EMAIL`）で設定し、
  未設定の項目は黙ってスキップする。**現在この経路に認証は無い**

- **デプロイ**: `gas/Code.gs` は CI のデプロイ対象外。マージしても本番には反映されない。
  手順は [`README.md`](../README.md#更新時の再デプロイ) を参照

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
- **時刻表原文ボタン**（`open_in_browser`）: `pdfUrl` が存在する場合のみ表示。ブラウザでPDFを開く。
  **現在 GAS は `pdfUrl` を返さないため表示されない**（スクレイピング廃止に伴う。実装は残置）
- **来週のダイヤボタン**（`calendar_month`）: `upcoming` が存在する場合のみ表示。モーダルボトムシートで全方面の来週ダイヤを表示
- **通知設定ボタン**（`notifications_outlined`）: 通知設定画面へ遷移
- **更新ボタン**（`refresh`）: スケジュールを手動再取得
- **デバッグ時刻ボタン**（`access_time`）: `kDebugMode` のみ表示（後述）

#### 通知設定画面（`NotificationSettingsScreen`）

- 出発通知の ON/OFF スイッチ（ON 時に iOS パーミッションダイアログを表示）
- 通知タイミング選択: 5 / 10 / 15 / 30 分前
- 設定は `SharedPreferences` に永続化
  （キー: `notif_enabled`, `notif_minutes_before`, `notif_scheduled_bus_keys`）

通知する便は**時刻表の各行のベルアイコン**で個別に選ぶ。選択した便は
`scheduledBusKeys` に保持される。

> かつては「通知する路線を5方面から1つ選ぶ」方式だったが、便ごとの個別選択に
> 置き換わっている。路線選択 UI は削除済み。

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

#### `DayType`（運行日 / Issue #158）

土日と祝日は `weekendHoliday`、それ以外は `weekday`。

祝日は `JapaneseHoliday`（`bus_schedule.dart`）が**計算で判定**する。外部 API に
依存すると通信失敗時に時刻表全体が返せなくなるため、固定日・ハッピーマンデー・
春分秋分の近似式・振替休日・国民の休日をコードで求めている（2150年まで有効）。

ただし時刻表に「**祝日だが平日ダイヤで運行**」と明記された次の5日は `weekday` として扱う。

> 【対象日】 4/29・7/20・10/12・11/3・11/23

7/20（海の日）と 10/12（スポーツの日）はハッピーマンデーで日付が動くが、
時刻表が固定日で列挙しているためそれに従っている。

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

- **スケジュール登録**: 時刻表の取得後、`scheduledBusKeys` に入っている便のうち
  当日これから発車するものを登録する（ベルアイコンで選んだ便のみ）
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
