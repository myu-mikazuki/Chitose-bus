# iOS リリースビルド手順

GitHub Actions を使ったリリース IPA のビルド手順。

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
