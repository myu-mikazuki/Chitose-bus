# Kagi-Bus 開発ガイド

## ブランチ戦略

Git Flow をベースとした戦略を採用しています。

### ブランチ構成

```
main（本番）
├── develop（統合ブランチ）
│   ├── feature/issue-XX         → develop (PR)
│   ├── feature/issue-XX-pr-N    → develop (PR)
│   └── fix/issue-XX             → develop (PR)
├── release/vX.X.X（develop → main の中継）
│   └── → main (PR) + タグ
└── hotfix/issue-XX              → main (PR) + develop にもマージ
```

### ブランチ種別

| ブランチ | 派生元 | マージ先 | 用途 |
|---------|--------|----------|------|
| `main` | - | - | 本番リリース済みコード。直接 push 禁止。 |
| `develop` | main | - | 統合ブランチ。常に次のリリース候補を含む。 |
| `feature/issue-XX` | develop | develop（PR） | 機能追加 |
| `feature/issue-XX-pr-N` | develop | develop（PR） | 大規模機能の段階的PR（N=a,b,c...） |
| `fix/issue-XX` | develop | develop（PR） | バグ修正 |
| `hotfix/issue-XX` | main | main（PR）＋ develop | 本番緊急修正 |
| `release/vX.X.X` | develop | main（PR）＋ develop | リリース準備・バージョンバンプ |

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
develop → feature/issue-XX-pr-a → PR → develop
develop → feature/issue-XX-pr-b → PR → develop
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

### ブランチ後処理

- マージ後はリモートブランチを削除する（GitHub の "Delete branch"）
- ローカルの不要ブランチも `git branch -d` で削除する
