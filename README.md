# Kagi-Bus — 千歳の大学へ通う人のバス時刻表アプリ

千歳の大学へのバス（千歳市路線バス 美々空港線）の時刻表を表示する Flutter アプリと、その GAS バックエンドのリポジトリです。学生有志による非公式アプリで、大学および各バス事業者とは関係ありません。

## ダウンロード

iOS・Android とも無料で公開しています。

| プラットフォーム | |
|----------------|---|
| iOS | [App Store](https://apps.apple.com/jp/app/kagi-bus/id6761445725) |
| Android | [Google Play](https://play.google.com/store/apps/details?id=com.myu_mikazuki.kagibus) |

紹介ページ: <https://myu-mikazuki.com/>

## 主な機能

- 千歳駅・南千歳・研究棟・本部棟 各方向のバス時刻表を表示
- 次のバスまでのカウントダウン表示
- **学休期ダイヤの自動切り替え**（夏季・冬季・お盆）
- **祝日ダイヤの判定**（「祝日だが平日ダイヤ」の例外日にも対応）
- 年末年始（12/31〜1/3）の全便運休表示
- 当日以外のダイヤ表示（平日／土日祝 × 授業期／学休期）
- お気に入りタブ登録（起動時に自動選択）
- バス出発前の通知
- オフライン表示（取得済みの時刻表を端末に保存）
- 講時タグ表示（1講・昼休み・放課後など）
- バナー広告（AdMob）

## システム構成

```
[GAS バックエンド] ── JSON API (?v=) ──→ [Flutter アプリ]
  gas/Code.gs                             flutter_app/
```

- **GAS バックエンド** (`gas/`): 時刻表をハードコードで保持し、JSON で返す Google Apps Script。
  外部 I/O を持たないため応答が速く、障害点も少ない
- **Flutter フロントエンド** (`flutter_app/`): GAS API を呼び出して時刻表を表示する iOS/Android アプリ

時刻表データは千歳市および大学が公開する美々空港線の時刻表をもとに手動で更新する。
かつては大学 Web サイトから PDF を自動取得・解析していたが、現在は使っていない
（該当コードは `gas/Code.gs` にコメントとして残置）。

### スキーマバージョン（`?v=`）

GAS は手動デプロイ、アプリはストア審査を挟むリリースのため反映タイミングが必ずずれ、
更新しないユーザーの旧バージョンは永続的に残る。そこでリクエストの `?v=` で
**アプリが持つ判定ロジックの世代**を伝え、判定できない分は GAS がサーバ側で絞ってから返す。

これにより、期限のある時刻表の修正を**ストア審査を待たず全ユーザーに届けられる**。
詳細は [`doc/spec.md`](doc/spec.md) を参照。

### 乗車地の選択（`?stops=`）

`?v=4` 以降は、美々空港線の全31停留所から乗車地を選べる。

```bash
curl -sL "<GAS_ENDPOINT_URL>?v=4"                        # 全停留所
curl -sL "<GAS_ENDPOINT_URL>?v=4&stops=chitose,morimoto" # 指定した停留所だけ
```

`?stops=` は絞り込みのみで、形式の分岐には関与しない（形式は `?v=` が決める）。

## ディレクトリ構成

```
.
├── gas/                  # Google Apps Script バックエンド
│   ├── Code.gs           # メインスクリプト
│   └── appsscript.json   # GAS プロジェクト設定
├── flutter_app/          # Flutter フロントエンド
│   ├── lib/              # アプリ本体
│   ├── test/             # テスト（unit / widget / golden）
│   ├── integration_test/ # 統合テスト
│   ├── TESTING.md        # テスト実行ガイド
│   └── pubspec.yaml
└── .github/
    └── workflows/
        ├── test.yml          # Flutter テスト + GAS 判定の検証（PR / main・develop への push）
        ├── android-build.yml # Android release ビルド（PR / main・develop への push）
        ├── ios-build.yml     # iOS release ビルド（PR / main・develop への push）
        └── release.yml       # リリースビルド・TestFlight / Play 内部テスト・
                              # GitHub Release 作成（タグ push で起動）
```

## セットアップ

### GAS バックエンド

1. [Google Apps Script](https://script.google.com/) で新規プロジェクトを作成
2. `gas/Code.gs` の内容を貼り付け
3. 「サービス」→ **Drive API** を有効化（高度な Google サービス）
4. **ウェブアプリとしてデプロイ**（アクセス: 全員）
5. デプロイ後に発行されるエンドポイント URL を控える

#### 更新時の再デプロイ

> [!IMPORTANT]
> `gas/Code.gs` は **CI のデプロイ対象外**です。PR をマージしても本番には反映されません。時刻表データやロジックを変更したら、必ず以下の手順で手動デプロイしてください。

1. Apps Script エディタを開き、`gas/Code.gs` の内容を貼り付けて保存
2. 「デプロイ」→「**デプロイを管理**」→ 既存デプロイの鉛筆アイコン
3. バージョンを「**新バージョン**」にして「デプロイ」

手順 2 で「新しいデプロイ」を作成しないでください。エンドポイント URL が変わり、配布済みのアプリが旧 URL を参照し続けます。

反映されたかどうかはエンドポイントを直接叩いて確認します。

```bash
curl -sL "<GAS_ENDPOINT_URL>" | head -c 200
```

`doGet` はキャッシュを持たないため、再デプロイすれば次のリクエストから新しい応答になります。

#### 時刻表データを変更したとき

`gas/Code.gs` の `ROUTES` を変更すると、応答のスナップショット検査が落ちます。

```bash
node scripts/check_gas_response.js
```

これは**意図した変更かどうかを人に確認させるための仕組み**です。旧アプリは
ストア更新をしない限り永久に残るため、応答が変わればリリース済みの全バージョンに
影響します。落ちたら差分を読み、意図どおりであることを確かめてから更新してください。

```bash
node scripts/check_gas_response.js --update
git diff scripts/fixtures/   # 変わった便が意図どおりか必ず目視する
```

> [!WARNING]
> CI を通すためだけに `--update` を実行しないでください。検査の意味が失われます。

#### GitHub Variables の設定

iOS ビルド時に `--dart-define` でエンドポイント URL を渡すため、リポジトリの Variables に登録します。

`Settings → Secrets and variables → Actions → Variables` に以下を追加:

| 変数名 | 値 |
|--------|-----|
| `DART_DEFINE_CONTENTS` | `{"GAS_ENDPOINT_URL": "<デプロイURL>"}` |

### Flutter アプリ

#### 前提条件

- Flutter SDK（stable チャンネル）
- Dart SDK（Flutter に同梱）

#### セットアップ手順

```bash
cd flutter_app

# 依存パッケージをインストール
flutter pub get

# コード生成（freezed / json_serializable）
dart run build_runner build --delete-conflicting-outputs
```

#### `.dart_defines` の設定（ローカル開発用）

ローカルでビルド・実行する場合は、リポジトリルートに `.dart_defines` を作成します（`.gitignore` 済み）:

```json
{
  "GAS_ENDPOINT_URL": "<GAS デプロイURL>"
}
```

#### 実行

```bash
flutter run --dart-define-from-file=../.dart_defines
```

## ビルド・テスト

### テスト

```bash
cd flutter_app
flutter test
```

詳細なテスト手順（Golden更新・統合テスト・fake_async など）は [`flutter_app/TESTING.md`](flutter_app/TESTING.md) を参照してください。

### リリースビルド（release.yml）

`v*` タグを push すると自動で起動します。

```bash
git tag v0.7.0
git push origin v0.7.0
```

| 成果物 | 内容 |
|--------|------|
| `kagi_bus-{version}-ios.ipa` | App Store Connect 提出用 IPA（署名済み）、TestFlight へ自動アップロード |
| `kagi_bus-{version}-android.apk` | Android APK（リリース署名済み） |
| `kagi_bus-{version}-android.aab` | Google Play 提出用 AAB（リリース署名済み） |

成果物は GitHub Release のアセットにも自動添付されます。

#### 必要な Secrets

| Secret 名 | 内容 |
|-----------|------|
| `IOS_CERTIFICATE` | Apple Distribution 証明書（Base64） |
| `IOS_CERTIFICATE_PASSWORD` | 証明書のパスワード |
| `IOS_PROVISIONING_PROFILE` | Provisioning Profile（Base64） |
| `APP_STORE_CONNECT_API_ISSUER_ID` | App Store Connect API Issuer ID |
| `APP_STORE_CONNECT_API_KEY_ID` | App Store Connect API Key ID |
| `APP_STORE_CONNECT_API_PRIVATE_KEY` | App Store Connect API 秘密鍵 |
| `ADMOB_IOS_APP_ID` | AdMob iOS アプリ ID |
| `KEYSTORE_BASE64` | Android キーストアファイル（Base64） |
| `KEYSTORE_PASSWORD` | キーストアのパスワード |
| `KEY_ALIAS` | キーエイリアス |
| `KEY_PASSWORD` | キーのパスワード |

### iOS 手動ビルド（ios-build.yml）

GitHub Actions の **iOS Build** ワークフロー（`workflow_dispatch`）から実行します。

- `build_id`: ビルド識別子（任意の文字列）
- `configuration`: `Debug`（デフォルト）または `Release`
- `use_signing`: App Store Connect 提出用に署名する場合は `true`

## バージョン

| バージョン | 内容 |
|-----------|------|
| [v1.2.0](https://github.com/myu-mikazuki/Chitose-bus/releases/tag/v1.2.0) | 美々空港線の学休期ダイヤに対応、時刻表の有効期間表示を削除、GAS のスクリプトキャッシュを廃止 |
| [v1.1.0](https://github.com/myu-mikazuki/Chitose-bus/releases/tag/v1.1.0) | 当日以外の時刻表を表示できる機能を追加、直17系統の運行日誤りを修正 |
| [v1.0.0](https://github.com/myu-mikazuki/Chitose-bus/releases/tag/v1.0.0) | 正式リリース、AdMob 広告のテスト/本番切り替え対応 |
| [v0.8.3](https://github.com/myu-mikazuki/Chitose-bus/releases/tag/v0.8.3) | iOS ビルドの CocoaPods/SPM 混在エラーを修正 |
| [v0.8.1](https://github.com/myu-mikazuki/Chitose-bus/releases/tag/v0.8.1) | 千歳駅のりば表示・お気に入りタブの不具合を修正 |
| [v0.8.0](https://github.com/myu-mikazuki/Chitose-bus/releases/tag/v0.8.0) | オフライン対応、講時タグ表示機能を追加 |
| [v0.7.3](https://github.com/myu-mikazuki/Chitose-bus/releases/tag/v0.7.3) | Android リリース版の起動直後クラッシュを修正 |
| [v0.7.2](https://github.com/myu-mikazuki/Chitose-bus/releases/tag/v0.7.2) | GitHub ユーザー名変更に伴う修正 |
| [v0.7.1](https://github.com/myu-mikazuki/Chitose-bus/releases/tag/v0.7.1) | iPad 対応を無効化（iPhone 専用に変更） |
| [v0.7.0](https://github.com/myu-mikazuki/Chitose-bus/releases/tag/v0.7.0) | お気に入りタブ機能追加、AAB ビルド追加 |
| [v0.6.1](https://github.com/myu-mikazuki/Chitose-bus/releases/tag/v0.6.1) | iOS ビルド修正 |
| [v0.6.0](https://github.com/myu-mikazuki/Chitose-bus/releases/tag/v0.6.0) | ストア初回公開（AdMob 広告、お問い合わせ機能） |
| [v0.5.0](https://github.com/myu-mikazuki/Chitose-bus/releases/tag/v0.5.0) | バス出発前通知機能 |
