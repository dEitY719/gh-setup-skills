---
name: add-ai-metrics
description: >-
  Retrofit the ai-metrics footer onto GitHub Issues/PRs that predate
  automatic capture. Use for /gh-setup:add-ai-metrics,
  "기존 이슈/PR 에 메트릭 소급 부착", "backfill ai-metrics". Backfill only —
  new cards get the footer automatically.
allowed-tools: Bash, Read, Grep
license: MIT
metadata:
  model_recommendation:
    tier: haiku
    reason: "metadata backfill via gh CLI"
    claude: prefer
    non_claude: advisory-only
---

# gh-setup:add-ai-metrics — Retrofit ai-metrics footer onto past Issues/PRs

Backfills the `tokens · human-h · ai-min` footer onto cards created before
issue dEitY719/dotfiles#317 / PR dEitY719/dotfiles#320 made capture automatic. Idempotent — a card already
carrying an `<!-- ai-metrics -->` block is skipped, and bytes outside that
block are never modified. Full flag / call-pattern table: `references/help.md`.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Step 1: Parse Args + Resolve Repo

Record `START_TS=$(date +%s)` immediately for the final summary line.

Parse args per the table in `references/help.md` — positional `issue#N` /
`pr#M` (case-insensitive), flags `--type`, `--date`, `--force`, `--remote`,
plus the pacing flags `--pace`, `--limit`, `--budget`, `--dry-run`.

`--date` accepts single day / whole month / half-open range (`..` / `~`)
per `parse_date_arg` in `references/date-parsing.md` (SSOT).
`--pace`/`--budget` accept durations (`30s`/`5m`/`1h30m`) via
`parse_duration` in `references/pace-control.md`; `--limit` a positive
integer; `--dry-run` a boolean.

Resolve `TARGET_REPO` + `TARGET_HOST` per
[`references/repo-resolution.md`](references/repo-resolution.md). Missing remote → list
`git remote -v` and stop (no silent fallback). `--date` + positional
cards is a hard error: print
`Error: --date and positional cards are mutually exclusive.` and stop.

## Step 2: Determine Mode + Build Target List

First match wins:

1. `--date` → **date-filter mode**: `parse_date_arg` →
   `build_search_clause` → `created:...` fragment, then `gh issue/pr list`
   (filtered by `--type`) `--search "<clause>" --state all --limit 200
   --json number,title`. The 200 cap stays — wider ranges split by user.
2. Positional cards → **explicit-list mode**: validate each `N` positive,
   dedupe, preserve order.
3. Otherwise → **conversation-infer mode**: scan recent turns for `#NNN`
   paired with `issue`/`PR`/`pr` cues (bare numbers ignored); none →
   `Error: no issue/PR references in conversation; pass them explicitly.`

If `|targets| > 100`, prompt `Continue with N cards? [y/N]:` (default no).
`--limit` does not suppress it — it guards against huge target lists.

## Step 3: Per-Card Loop

`--dry-run` → take the dry-run branch in `references/pace-control.md`
(per-card view fetch, `· will-write`/`· will-skip`/`· will-force-replace`
rows, dry-run summary, **never `gh edit`**), then stop.

Otherwise iterate per `references/footer-detection.md` (SSOT — not
restated here): top-of-iteration stop check (`--budget`/`--limit` via
`check_budget`, see `references/pace-control.md` → "Stop-reason
composition"), fetch, detect `<!-- ai-metrics -->`, branch
no-footer→append / footer→skip / footer+`--force`→in-place replace,
`gh edit` + `sleep_pace` on modify only, one-line status, continue on
failure. Metric values follow `references/post-hoc-metrics.md`.

## Step 4: Final Report

Print the summary line + context-only ai-metrics line per the "Final
report output format" section in `references/footer-detection.md`, after
computing `ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))`. On early exit
via `--limit`/`--budget`, append a `Stopped early: <stop_reason>; <X>
cards remaining. Re-run to resume (idempotent).` line. For `--dry-run`,
the report is the dry-run summary block from `references/pace-control.md`
instead — no per-card metrics, no counters.

## Constraints

Operating invariants (always `--repo`, body byte-identical outside the footer,
`--force` recompute-not-overwrite, continue-on-error, pacing, `--limit`/
`--budget` OR-semantics) live in [`references/constraints.md`](references/constraints.md).

## Related Skills

`gh-issue:create` / `gh-pr:create` write the same footer at creation time — this skill only fills the gap for cards that predate them.
