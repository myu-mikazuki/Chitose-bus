# Kagi-Bus 開発ガイド

## ブランチ戦略

Git Flow をベースとした戦略を採用しています。

### ブランチ構成

```
main（本番）
├── develop（統合ブランチ）
│   ├── feature/issue-XX              → develop (squash merge PR)
│   │   └── feature/issue-XX-pr-N    → feature/issue-XX (squash merge PR)
│   └── fix/issue-XX                 → develop (squash merge PR)
├── release/vX.X.X（develop → main の中継）
│   └── → main (マージコミット PR) + タグ
└── hotfix/issue-XX              → main (マージコミット PR) + develop にもマージ
```

### ブランチ種別

| ブランチ | 派生元 | マージ先 | マージ方法 | 用途 |
|---------|--------|----------|-----------|------|
| `main` | - | - | - | 本番リリース済みコード。直接 push 禁止。 |
| `develop` | main | main（PR） | マージコミット | 統合ブランチ。常に次のリリース候補を含む。main への直接 PR は CI・ドキュメントのみの変更に限る（後述）。 |
| `feature/issue-XX` | develop | develop（PR） | squash merge | 機能追加 |
| `feature/issue-XX-pr-N` | `feature/issue-XX` | `feature/issue-XX`（PR） | squash merge | 大規模機能の段階的PR（N=a,b,c...） |
| `fix/issue-XX` | develop | develop（PR） | squash merge | バグ修正 |
| `hotfix/issue-XX` | main | main（PR）＋ develop | squash merge | 本番緊急修正 |
| `release/vX.X.X` | develop | main（PR）＋ develop | マージコミット | リリース準備・バージョンバンプ |

### 命名規則

- 機能: `feature/issue-{number}` 例: `feature/issue-39`
- 大規模機能: `feature/issue-{number}-pr-{letter}` 例: `feature/issue-42-pr-a`
- バグ修正: `fix/issue-{number}` 例: `fix/issue-51`
- 緊急修正: `hotfix/issue-{number}` 例: `hotfix/issue-55`
- リリース: `release/v{major}.{minor}.{patch}` 例: `release/v1.0.0`

### マージフロー

**通常機能・バグ修正**
```
develop → feature/issue-XX → PR → develop
```

**大規模機能（複数PR）**
```
develop → feature/issue-XX
feature/issue-XX → feature/issue-XX-pr-a → squash merge PR → feature/issue-XX
feature/issue-XX → feature/issue-XX-pr-b → squash merge PR → feature/issue-XX
feature/issue-XX → squash merge PR → develop
```

**リリース**
```
develop → release/vX.X.X → PR → main → vX.X.X タグ
                                       ↓ develop にもマージバック
```

**緊急修正**
```
main → hotfix/issue-XX → PR → main → タグ（必要なら）
                              ↓ develop にもマージバック
```

**CI・ドキュメントのみの変更を main に反映**
```
develop → PR（マージコミット）→ main
```

CI ワークフローやドキュメントだけを更新した場合、リリースを待たずに main へ
取り込んでよい。hotfix はmainから切るため、main の CI を最新に保つ意味がある。

- **アプリのコード（`flutter_app/lib`・`flutter_app/test`）に変更が無いことが条件**。
  1行でも含むならリリースとして扱い、`release/vX.X.X` を切る
- バージョンバンプもタグも行わない（アプリのバイナリが変わらないため）
- **squash は使わない**。develop を squash すると develop 側のコミットが永久に
  「未マージ」扱いになり、以降の差分計算が壊れる
- マージ後は main と develop の内容が一致するため、マージバックは不要

### ブランチ後処理

- マージ後はリモートブランチを削除する（GitHub の "Delete branch"）
- ローカルの不要ブランチも `git branch -d` で削除する

## life リポジトリの wiki

`~/repos/life/wiki/` は各プロジェクトから抽象化した汎用知見（設計パターン・失敗例・ドメイン知識）の置き場。

### 参照

- 設計・技術選定・ハマりどころの相談のときは、先に `~/repos/life/wiki/README.md` の索引を読み、関連ファイルを読む
- セッション開始時に毎回読む必要はない

### 更新

- 作業で得た知見が、個別の値を取り除いて一般化でき、かつ wiki に無いときだけ更新する。更新は life リポジトリ側で行う
  - 既存項目に近い: 補強・訂正する（新規ファイルを重複して作らない）
  - 一般化でき、wiki に無い: 新規ファイルを作る
  - 一回性が疑わしい: wiki には書かない
- 個別の値（バス停名・店舗ID・AdMob ID・エンドポイントURL 等）は載せない
- 確認は取らずに更新してよい。life の規約どおり、life の main に commit して push まで行う
- ファイル名・見出しは一般化した概念名にし、冒頭に `**出典**:` 行を置く（詳細は wiki の README）
