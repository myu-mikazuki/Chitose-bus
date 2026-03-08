# dart-defines の設定

アプリの動作に必要なコンパイル時定数の設定方法。

## `.dart_defines` ファイル

リポジトリルート直下に `.dart_defines` を作成する（`.gitignore` 済み）。

```json
{
  "GAS_ENDPOINT_URL": "https://script.google.com/macros/s/.../exec"
}
```

| キー | 説明 |
|------|------|
| `GAS_ENDPOINT_URL` | GAS WebアプリのデプロイURL。未設定の場合はスケジュール取得が失敗する |

## GAS エンドポイント URL の取得

1. Google Apps Script プロジェクトを開く（`gas/Code.gs`）
2. 「デプロイ」→「デプロイを管理」→ デプロイ済み Web アプリの URL をコピー
3. `.dart_defines` の `GAS_ENDPOINT_URL` に設定

## GitHub Actions でのビルド

GitHub Actions では Secrets として登録することで自動的に注入される。

リポジトリの **Settings → Secrets and variables → Actions** に以下を登録：

| Secret 名 | 値 |
|-----------|----|
| `GAS_ENDPOINT_URL` | GAS WebアプリのデプロイURL |
