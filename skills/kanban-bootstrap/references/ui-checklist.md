# UI Checklist — F-6 (SSOT-aligned)

After `lib/setup.sh` finishes, the user must apply 10 built-in workflow
settings in the Project board UI. The script's `print_final_report`
emits this list with host-aware deep-links and the #289-aligned
workflow #3 instruction.

Reproduced here for reference (the canonical version lives inside
`lib/setup.sh` so the same output appears whether the skill or the
script is invoked directly).

## Workflow table

| # | Workflow | Action | Notes |
|---|----------|--------|-------|
| 1 | `Auto-add to project` | Repository=`<REPO>` + Filter=`is:issue,pr is:open` | New cards land on board |
| 2 | `Item added to project` | Status=`Backlog` | Initial column for all cards |
| 3 | `Pull request linked to issue` | **DISABLE** (#289) | Issues do NOT visit `In review` |
| 4 | `Code review approved` | Status=`Approved` | PR-only lane |
| 5 | `Code changes requested` | Status=`In progress` | PR review loop |
| 6 | `Pull request merged` | Status=`Done` | PR exit |
| 7 | `Item closed` | Status=`Done` | Issue + PR exit |
| 8 | `Auto-close issue` | Keep default | — |
| 9 | `Auto-add sub-issues to project` | Keep default | — |
| 10 | `Auto-archive items` | Enable + Filter=`is:issue,pr is:closed updated:<@today-2d` | Copy filter verbatim |

## Why workflow #3 is disabled (#289)

The issue lifecycle in this SSOT is **3 stages**:
`Backlog → In progress → Done`. Issues do NOT visit `In review` —
that column is exclusively for PRs (`Backlog → In review → Approved
→ Done`).

If workflow #3 stays enabled, GitHub auto-moves an Issue card to
`In review` the moment a PR links to it (via `Closes #N`), which
contradicts the 3-stage lifecycle. The skill / script tells the user
to **disable** this workflow.

`_gh_project_status_sync` in `shell-common/functions/gh_project_status.sh`
includes a correction guard (`--only-from "Backlog,Ready,In review"`)
that re-moves Issue cards from `In review` back to `In progress` even
if workflow #3 was left enabled, but the explicit disable removes the
ambiguity entirely.

## Solo repo hide-columns guidance

When `--hide-columns` is passed:
- Hide `Approved` (solo repos rarely receive external approvals).
- Hide `Ready` (reserved column unused in normal dotfiles flow).

## Verification (smoke test)

The script prints the host-corrected smoke test commands. They are
NOT executed unless `--with-smoke-test` was passed.

```sh
GH_HOST="$HOST" gh issue create --repo "$OWNER/$REPO" \
    --title "[Test] kanban smoke" --body "ignore"
# Card should appear in Backlog within seconds
```

`$HOST` is the one `references/prereq.md` already resolved from `origin`'s
URL (`_kanban_host`) — reuse it, do not introduce a second host variable.
`--repo "$OWNER/$REPO"` names the repo but carries no host, so without the
prefix this write would follow `gh repo set-default` and file the smoke-test
issue on whichever server that points at (#1403 / #1407).

See playbook §7 for the full 4-step smoke test (issue → PR → merge →
close).
