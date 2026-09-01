---
name: kanban-bootstrap
description: >-
  Bootstrap a GitHub Projects v2 kanban board for a repo in one shot. Use
  for /gh-setup:kanban-bootstrap, "kanban 보드 셋업",
  "프로젝트 보드 자동화 셋업", "set up the kanban board". Board setup — pure
  label sync is gh-setup:label-bootstrap.
allowed-tools: Bash, Read, Grep
metadata:
  model_recommendation:
    tier: haiku
    reason: "structured Projects v2 board bootstrap; wraps deterministic lib/setup.sh, bounded report output, low reasoning"
    claude: prefer
    non_claude: advisory-only
---

# gh-setup:kanban-bootstrap — Kanban Board Setup

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output its content verbatim, then stop.
No API calls.

## Step 1: Resolve Skill Dir

Record `START_TS=$(date +%s)` immediately. Locate `SKILL_DIR` (this file's directory): the script lives at
`${SKILL_DIR}/lib/setup.sh`.

## Step 2: Prereq Check

Follow `references/prereq.md` for tool / host / token-scope checks — it also resolves `$HOST` from `origin`'s
URL. On any miss the helper prints the install or `gh auth refresh -h <host> -s project` hint and aborts (rc=1).

## Step 3: Target Repo

Always `origin` (never prompt for remote selection). Detect `OWNER/REPO` via
`GH_HOST="$HOST" gh repo view --json nameWithOwner`; explicit `--owner`/`--repo` override. `$HOST` is Step 2's
`_kanban_host` value — every `gh` call carries it (`GH_HOST="$HOST"`, or `--hostname "$HOST"` for `gh api`),
since `--repo` alone names no server (#1403 / #1407).

## Step 4: Options

If `--hide-columns` was not passed and this looks like a personal repo,
ask the user once (1-line question) — never auto-infer from collaborator
count (NF-3 / privacy). Parse `--no-bootstrap-labels` (skip Step 5).
`--force-label-sync` is a back-compat **no-op**, accepted silently (F-3 of
issue #1226 — flags and their defaults: `references/help.md`).

## Step 5: Label Bootstrap

Delegate to the sibling `gh-setup:label-bootstrap` skill (SSOT:
`../label-bootstrap/references/gh-labels.md`) — it force-syncs the 10
SSOT labels' color/description and renames the 3 alias labels:

```
bash "${SKILL_DIR}/../label-bootstrap/lib/label-bootstrap.sh" \
    --repo "$OWNER/$REPO"
```

Pass `--dry-run` through on the dry-run dispatch (Step 6).
`--no-bootstrap-labels` skips this step with a one-line notice. Per-label
permission errors warn on stderr and continue (never blocks board setup).

## Step 6: Dry-run Dispatch

```
bash "${SKILL_DIR}/lib/setup.sh" --dry-run <user-flags>
```

On non-zero exit → abort (do not proceed to Step 7). Quote the script's
stderr first line.

## Step 7: Real Run

```
bash "${SKILL_DIR}/lib/setup.sh" <user-flags>
```

Parse stdout for `Project board setup finished` (success) or
`A project titled '<TITLE>' already exists` (idempotent re-run). Extract
the Project URL and number.

## Step 8: UI Checklist + Report

The script's `print_final_report` already emits host-aware URLs (post-#699 fix) and the workflow #3 `DISABLE`
instruction — pass it through, then append the smoke-test block and compact closing report per
`references/report-template.md`.

## Constraints

- Never mutate the script's behavior — wrap, don't rewrite.
- Never auto-execute smoke test without explicit `--with-smoke-test`.
- Never echo token / collaborator / project ID to stdout (NF-3).
- Never silently fall back to a different remote — `origin` only.
- `lib/setup.sh` is the sole entry point — do not reintroduce the old `scripts/` location (removed in #699).

## Related Skills

`gh-setup:label-bootstrap` (label SSOT sync only — delegated in Step 5) · `gh-setup:docs-bootstrap` (docs/ tree) — same new-repo setup slot.
