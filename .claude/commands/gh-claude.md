---
name: gh-claude
description: Use this skill (instead of the gh CLI directly) for ALL GitHub operations — creating/merging/reviewing PRs, managing issues (create, comment, label, close), checking CI/workflow runs, creating releases, viewing repo info. Invoke whenever any GitHub task is requested.
---

# gh-claude: GitHub Operations Skill

You are now in GitHub operation mode. Use the `gh-claude` CLI (a GitHub App-authenticated wrapper around `gh`) to perform the requested GitHub task.

## Common operations

### Pull Requests
```bash
gh-claude pr list                          # List open PRs
gh-claude pr view <number>                 # View PR details
gh-claude pr create --title "..." --body "..."  # Create PR
gh-claude pr merge <number>                # Merge PR
gh-claude pr review <number> --approve     # Approve PR
gh-claude pr review <number> --request-changes --body "..."
gh-claude pr checks <number>               # Check CI status for PR
gh-claude pr diff <number>                 # View PR diff
gh-claude pr comment <number> --body "..."
```

### Issues
```bash
gh-claude issue list                       # List open issues
gh-claude issue view <number>              # View issue
gh-claude issue create --title "..." --body "..."
gh-claude issue close <number>
gh-claude issue comment <number> --body "..."
gh-claude issue assign <number> --assignee @me
gh-claude issue label <number> --add "bug"
```

### CI / Workflows
```bash
gh-claude run list                         # List recent workflow runs
gh-claude run view <run-id>                # View run details
gh-claude run watch <run-id>               # Watch run in progress
gh-claude workflow list                    # List workflows
gh-claude workflow run <workflow>          # Trigger a workflow
```

### Releases
```bash
gh-claude release list
gh-claude release view <tag>
gh-claude release create <tag> --title "..." --notes "..."
```

### Repo info
```bash
gh-claude repo view
gh-claude api repos/<owner>/<repo>         # Raw API access
```

## 重要: 必ず `--json` を付ける

このリポジトリでは、`--json` を付けない `view` / `edit` 系が **Projects (classic) の廃止に伴う GraphQL エラーで失敗する**。

```
GraphQL: Projects (classic) is being deprecated in favor of the new Projects
experience... (repository.issue.projectCards)
```

`gh` が既定で `projectCards` を要求するために起きる。`--json` で必要なフィールドだけを
指定すればこのクエリは発行されず、正常に動く。

```bash
# NG（エラーになる）
gh-claude issue view 132
gh-claude pr view 161

# OK（必要なフィールドを明示する）
gh-claude issue view 132 --json number,title,body,state,labels
gh-claude pr view 161 --json number,state,body,mergeable,baseRefName,headRefName
```

### 書き込み系は REST API に逃がす

`--json` が使えない書き込み系（`pr edit` など）は同じエラーで落ちる。厄介なのは
**エラーを出しつつ変更が適用されない**点で、成功したように見えることがある。

```bash
# NG（エラーで本文が更新されない）
gh-claude pr edit 161 --body "..."

# OK（REST API を直接叩く）
gh-claude api -X PATCH repos/<owner>/<repo>/pulls/161 -F body=@body.md
gh-claude api -X PATCH repos/<owner>/<repo>/issues/132 -F body=@body.md
```

`--body` に長文を渡すときは、シェルのエスケープ事故を避けるためファイル経由（`-F body=@file`）にする。

### 書き込み後は必ず確認する

上記の理由から、`create` / `edit` / `comment` の後は `--json` で読み直して反映を確認すること。

```bash
gh-claude pr view 161 --json body --jq '.body' | head -5
```

なお `pr create` / `issue create` / `issue comment` / `issue close` は
このエラーを踏まない（実績あり）。

## Instructions

1. Determine exactly what GitHub operation the user wants.
2. Run the appropriate `gh-claude` command(s).
3. Present results clearly — for lists use a concise summary, for PR/issue details show key fields.
4. If a destructive action (merge, close, delete) is needed, confirm with the user before executing.
