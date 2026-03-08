# iOS デバッグ手順

WSL + MobAI ios-builder を使ったデバッグビルドの実行手順。

## 前提

- [MobAI/ios-builder](https://github.com/MobAI-App/ios-builder) を WSL にインストール済み
- MobAI が Windows 側（YUZU-SURFACE）でセットアップ済み
- sideloadly がインストール済み
- iPhone が開発者モードで有効
- `.dart_defines` がリポジトリルート直下に作成済み（→ [dart-defines.md](dart-defines.md)）

---

## 手順

### 1. デバッグ IPA をビルド

```bash
cd ~/repos/chitose_bus
builder ios build \
  --config Debug \
  --project flutter_app/ios
```

ビルドが完了すると `flutter_app/dist/` に IPA が生成される。

### 2. iPhone にインストール（sideloadly）

1. sideloadly を起動
2. iPhone を USB 接続
3. 生成した IPA（`flutter_app/dist/*.ipa`）をドラッグ＆ドロップ
4. Apple ID を入力してインストール
5. インストール後に表示される **Bundle ID** をメモしておく

### 3. MobAI を起動

Windows 側で MobAI を起動し、iPhone が認識されていることを確認する。

### 4. デバッグセッションを開始

WSL で以下を実行：

```bash
cd ~/repos/chitose_bus
./scripts/dev_flutter.sh --skip-install --bundle-id <Bundle ID>
```

`<Bundle ID>` は手順 2 でメモした値（例: `jp.yuzucchi.chitoseBus`）。

接続が確立すると flutter の REPL が起動し、`r` でホットリロード、`R` でホットリスタートが使える。

---

## デバッグ機能（アプリ内）

デバッグビルドでのみ AppBar に時計アイコンが表示される。

- タップ → TimePicker で任意の時刻を設定
- 設定した時刻でバス表示・カウントダウンが動作する（実際の通知スケジュールには影響しない）
- 黄色アイコン = オーバーライド中。再タップ → 「リセット」で実時刻に戻す

---

## トラブルシューティング

| 症状 | 対処 |
|------|------|
| `Error: timeout waiting for debug service` | iPhone でアプリが起動しているか確認 |
| `app not found: <bundle-id>` | Bundle ID が sideloadly でインストールしたものと異なる |
| MobAI に iPhone が表示されない | USB 接続・開発者モード・MobAI の再起動を確認 |
