---
name: squash-merge
description: PR番号を受け取って squash merge を実行する。Co-Authored-By を末尾に1つだけ含むクリーンなコミットメッセージを生成してマージする。「squash merge PR X」「PR X を squash merge」のように呼ばれたときに使用する。
---

# squash-merge: Squash Merge スキル

指定された PR を squash merge し、クリーンなコミットメッセージで develop にマージする。

## 引数

- `$ARGUMENTS`: PR 番号（例: `61`）

## 手順

1. **PR 情報取得**: `gh pr view $ARGUMENTS --json title,body,baseRefName,headRefName,commits` で情報を取得する

2. **コミットメッセージを作成する**:
   - **subject**: PR タイトルをそのまま使う（GitHub が末尾に `(#PR番号)` を付けるので付けない）
   - **body**: PR の「概要」セクション（箇条書き部分）を元に簡潔にまとめる。末尾に `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>` を**1つだけ**付ける

3. **squash merge を実行する**:

```bash
gh pr merge $ARGUMENTS --squash --delete-branch \
  --subject "SUBJECT" \
  --body "BODY"
```

## body のフォーマット

```
- 変更点1
- 変更点2

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

## 注意事項

- **`Co-Authored-By` は body の末尾に1つだけ**入れる — 個別コミットの Co-Authored-By が squash 後に大量に現れるのを防ぐため
- `--delete-branch` を必ず付けてリモートブランチを削除する
- `gh-claude` スキルは使用しない。`gh` コマンドを直接 `Bash` ツールで実行すること
- subject に PR 番号を手動で付けない（GitHub が自動付与する）
