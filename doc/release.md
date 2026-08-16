# リリース手順

## タグ push による自動リリース

`v*` タグを push すると `.github/workflows/release.yml` が起動し、以下が自動実行される。

1. iOS の署名付き IPA をビルドし、**TestFlight にアップロード**
2. Android の APK / AAB をビルドし、**Google Play の内部テストにアップロード**
3. **GitHub Release を作成**し、成果物を添付

### ストアの「新機能」

Google Play の「新機能」は **`distribution/whatsnew/whatsnew-<言語>`** の内容がそのまま使われる（例: `whatsnew-ja-JP`）。リリースブランチの作業で更新する。

**Google Play の上限は 500 文字。**

iOS の「このバージョンの新機能」は App Store Connect で手入力する（自動化していない）。

### リリースノート

リリースノートは **`doc/release-notes/<タグ>.md`** に置く（例: `doc/release-notes/v1.2.0.md`）。
リリースブランチの作業時に用意しておくと、タグ push 時にそのまま公開される。

ファイルが無い場合もリリース自体は失敗せず、GitHub の自動生成ノート（マージされた
PR の一覧）のみで公開される。その場合はワークフローに warning が出る。

本文の後ろには常に自動生成ノートが追記される。

### 手順

```bash
# develop → release/vX.Y.Z を作成し、以下を用意する
#   - flutter_app/pubspec.yaml の version
#   - README.md のバージョン履歴
#   - doc/release-notes/vX.Y.Z.md（GitHub Release の本文）
#   - distribution/whatsnew/whatsnew-ja-JP（Google Play の「新機能」）
# → main へマージコミットで PR・マージした後
git checkout main && git pull
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
```

### 手動でストアに提出する部分

配布経路まで自動だが、**製品版への公開は手動**。

- iOS: App Store Connect で TestFlight のビルドを選択して審査提出
- Android: **内部テストまで自動**。Play Console から製品版へ手動で昇格

Android を `tracks: internal` に留めているのは、誤って本番公開されるのを防ぐため。運用が安定したら `release.yml` の `tracks` を上げるか検討する。

`PLAY_SERVICE_ACCOUNT_JSON` が未設定の場合、アップロードはスキップされ warning が出る（ビルド自体は成功する）。

### Google Play アップロードの前提

サービスアカウントを置いている GCP プロジェクトで、**Google Play Android Developer API**
を有効にしておく必要がある。無効のままだと最初のアップロードが次のエラーで失敗する。

```
Google Play Android Developer API has not been used in project <番号>
before or it is disabled.
```

一度有効にすれば以降は不要。環境を作り直したときだけ気にすればよい。

---

# iOS リリースビルド手順（手動ビルド）

動作確認用に IPA だけ作りたい場合の手順。

## 手順

### 1. GitHub Actions を開く

リポジトリの **Actions** タブを開く。

### 2. ワークフローを選択

左サイドバーから **iOS Build** を選択。

### 3. Run workflow

右上の **Run workflow** ボタンを押し、以下のパラメータを入力する。

| パラメータ | 値 | 説明 |
|------------|----|------|
| Branch | ビルドしたいブランチ | 例: `main` |
| Unique build identifier | 任意の文字列 | ビルドを識別する名前（例: `v1.0.0`） |
| Path to iOS project | `flutter_app/ios` | Flutter アプリの ios ディレクトリへのパス |
| Build configuration | `Release` | リリースビルドの場合は `Release`（デバッグは `Debug`） |
| Flutter version | 空欄 | 空欄で最新安定版を使用 |

**Run workflow** を押して実行。

### 4. IPA をダウンロード

ビルドが完了したら、実行したワークフローを開いて **Artifacts** セクションから `ipa` をダウンロードする。

### 5. iPhone にインストール（sideloadly）

1. sideloadly を起動
2. iPhone を USB 接続
3. ダウンロードした IPA をドラッグ＆ドロップ
4. Apple ID を入力してインストール

---

## 注意

- `GAS_ENDPOINT_URL` は GitHub Secrets に `GAS_ENDPOINT_URL` として登録されている必要がある
- コード署名（`Enable code signing`）は通常 `false` のまま。sideloadly が署名する
