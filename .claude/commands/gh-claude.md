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

## Instructions

1. Determine exactly what GitHub operation the user wants.
2. Run the appropriate `gh-claude` command(s).
3. Present results clearly — for lists use a concise summary, for PR/issue details show key fields.
4. If a destructive action (merge, close, delete) is needed, confirm with the user before executing.
