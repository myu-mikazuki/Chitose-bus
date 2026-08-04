# リリース手順

## タグ push による自動リリース

`v*` タグを push すると `.github/workflows/release.yml` が起動し、以下が自動実行される。

1. iOS の署名付き IPA をビルドし、**TestFlight にアップロード**
2. Android の APK / AAB をビルド
3. **GitHub Release を作成**し、成果物を添付

### リリースノート

リリースノートは **`doc/release-notes/<タグ>.md`** に置く（例: `doc/release-notes/v1.2.0.md`）。
リリースブランチの作業時に用意しておくと、タグ push 時にそのまま公開される。

ファイルが無い場合もリリース自体は失敗せず、GitHub の自動生成ノート（マージされた
PR の一覧）のみで公開される。その場合はワークフローに warning が出る。

本文の後ろには常に自動生成ノートが追記される。

### 手順

```bash
# develop → release/vX.Y.Z を作成し、バージョンバンプとリリースノートを用意
#   - flutter_app/pubspec.yaml の version
#   - README.md のバージョン履歴
#   - doc/release-notes/vX.Y.Z.md
# → main へマージコミットで PR・マージした後
git checkout main && git pull
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
```

### 手動でストアに提出する部分

TestFlight までは自動だが、**App Store / Google Play への提出は手動**。

- iOS: App Store Connect で TestFlight のビルドを選択して審査提出
- Android: Play Console に `kagi_bus-<タグ>-android.aab` をアップロード

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
