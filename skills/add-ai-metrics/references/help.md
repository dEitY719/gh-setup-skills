# gh-setup:add-ai-metrics — Help

## Usage

```
/gh-setup:add-ai-metrics [<targets>] [--type issue|PR] [--date <date>]
                   [--pace <dur>] [--limit <N>] [--budget <dur>] [--dry-run]
                   [--force] [--remote <name>]
```

`<targets>` are space-separated `issue#N` / `pr#M` tokens (case-insensitive).
`<date>` is one of: `YY-MM`, `YYYY-MM`, `YY-MM-DD`, `YYYY-MM-DD`,
`<start>..<end>`, or `<start>~<end>`. `<dur>` is a GNU-`sleep` style
duration: `30s`, `5m`, `1h`, `1h30m`.

## Arguments

| # | Form | Default | Description |
|---|------|---------|-------------|
| positional | `issue#N` / `pr#M` | — | Cards to retrofit (case-insensitive prefix). Multiple allowed. |
| flag | `--type {issue\|PR}` | both | Limits date-filter mode to a single artifact kind. |
| flag | `--date <date>` | — | Date-filter mode trigger. Accepts single day (8 / 10 chars), whole month (`YY-MM` / `YYYY-MM`), or half-open range (`A..B` or `A~B`). See "Date forms" below. |
| flag | `--pace <dur>` | `0` (no pace) | Sleep `<dur>` after each successful modify. Skipped on the last card and on every skip-path card. |
| flag | `--limit <N>` | unset | Stop after `N` cards have been modified (skips do not count). |
| flag | `--budget <dur>` | unset | Stop before exceeding `<dur>` of wall-clock. Composes with `--limit` via OR — whichever fires first wins. |
| flag | `--dry-run` | off | Classify the target list without writing anything. View calls still happen (needed for state classification). |
| flag | `--force` | off | Recompute metrics and replace an existing footer (default skips). |
| flag | `--remote <name>` | `origin` | Override the target remote. |
| flag | `-h` / `--help` / `help` | — | Print this help and stop. |

## Date forms (used with `--date`)

| Length / shape       | Example                | Meaning                                 |
|----------------------|------------------------|-----------------------------------------|
| 5 chars              | `26-04`                | Whole month — 2026-04-01 through 2026-04-30 |
| 7 chars              | `2026-04`              | Same — 4-digit year explicit            |
| 8 chars              | `26-04-30`             | Single day — `20YY` expansion           |
| 10 chars             | `2026-04-30`           | Single day — used as-is                 |
| range with `..`      | `26-04-03..26-04-11`   | Half-open `[start, end)` — end excluded |
| range with `~`       | `26-04-03~26-04-11`    | Same as `..` (`~` is normalized)        |

`A..B` uses **half-open `[start, end)`** semantics — END is excluded,
matching Python slice and git revision-range conventions. Internally it
is converted to GitHub's inclusive `created:A..B-1day` query.

Whole-month form is **inclusive both ends** because the unit IS the month —
there is no "exclude the last day" interpretation that makes sense.

## Modes (mutually exclusive — first match wins)

1. **conversation-infer** (no args)
   Scans recent chat turns for `#NNN` paired with `issue` / `PR` / `pr`
   cues. Bare numbers without `#` are ignored (false-positive guard).
   No candidates → hard error.

2. **explicit-list** (positional cards)
   Parse `issue#N pr#M ...`. Order preserved, dupes deduplicated.

3. **date-filter** (`--date`, optional `--type`)
   Enumerates via
   `gh {issue,pr} list --search "<clause>" --state all --limit 200`.
   Clause shape per `parse_date_arg` in `references/date-parsing.md`.
   `> 100` hits → confirmation prompt (`y/N`, default no), even when
   `--limit` is set.

`--date` and positional cards together → hard error (mutex).

## Examples

Concrete invocation patterns — single-shot, whole-month, range, and
overnight nightly backfill — live in `references/examples.md` to keep
this help under the progressive-disclosure threshold. Quick taste:

```
/gh-setup:add-ai-metrics issue#317 pr#320                              # explicit
/gh-setup:add-ai-metrics --type PR --date 26-04                        # whole month
/gh-setup:add-ai-metrics --type PR --date 26-04-03..26-04-11           # range
/gh-setup:add-ai-metrics --type PR --date 26-04 --pace 3m --budget 4h30m   # overnight
/gh-setup:add-ai-metrics --type PR --date 26-04 --pace 3m --budget 4h30m --dry-run   # preview
```

## Behavior

- **Idempotent by default** — cards already carrying `<!-- ai-metrics -->`
  (or `<!-- ai-metrics:* -->`) skip without an `gh edit` API call AND
  without sleeping (skip-path is fully API-silent).
- **`--force` recomputes** — does NOT just overwrite the literal block;
  re-fetches body, recomputes fresh `TOKENS` / `HUMAN_H` / `ELAPSED`,
  then replaces the existing block in place (no duplicate append).
- **Continue-on-error** — one card failing never blocks the rest. Final
  summary lists `added / replaced / skipped / failed` counts.
- **Body-preserving** — appends after a `---` separator on first run;
  in `--force` replace, regex matches the block markers exactly, leaving
  surrounding bytes untouched.
- **API quota friendly** — skip path performs zero `gh edit` calls.

## Notes

- **Skip-existing = natural resume.** When `--limit` or `--budget`
  stops the loop early, just re-run the same command — already-tagged
  cards skip in seconds (no API call), and the loop picks up from the
  first un-tagged card. No `--resume` flag needed.
- **`--limit` + `--budget` = OR.** Whichever stops the loop first wins;
  the final summary names which one fired.
- **`--dry-run` is not zero-quota.** `gh view` is still called per card
  (state classification needs the body). It's `gh edit` that is skipped.

## Footer format (matches PR #320 / `gh-issue-create`)

```
---
<!-- ai-metrics -->
📊 ~{TOKENS} tokens · 👤 ~{HUMAN_H} h · 🤖 ~{ELAPSED} min
<!-- /ai-metrics -->
```

The detection regex tolerates the optional `:<skill>` suffix
(`<!-- ai-metrics:gh-issue-create -->` etc.) for forward-compat with
`metrics-helper.md`'s newer scheme.

## Post-hoc metric estimation

When backfilling, the original Claude session is gone, so values are
estimated. Detail in `post-hoc-metrics.md`; summary:

| Metric | Estimation rule |
|--------|-----------------|
| `TOKENS` | `(title + body chars) ÷ 4`, rounded to nearest 500, min 1000 |
| `HUMAN_H` | conventional-commit prefix in title → `gh-issue-create/references/metrics-baseline.md`; fallback `misc` (2 h) |
| `ELAPSED` | `max(1, HUMAN_H × 0.05)` — assumes AI took ~5% of the human estimate |

These values are deterministic given the same body, so re-running the
skill with `--force` produces stable output (no flapping).

## What this skill will NOT do

- Re-run the original AI conversation to recover real token counts.
- Modify card body outside the footer block.
- Auto-create labels, assignees, or milestones.
- Silently fall back to `origin` when `--remote <name>` is missing.
- Process more than 100 cards without explicit `y` confirmation.
- Mutate cards on the skip path (no body diff, no API call, no sleep).
- Run cards in parallel (`--pace` is intentionally serial).
