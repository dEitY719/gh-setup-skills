# gh-setup:add-ai-metrics — Examples

Split out from `help.md` to keep the help under the progressive-disclosure
threshold (150 lines). Read this file when you want concrete invocation
patterns; `help.md` covers argument shapes and behavioral contracts.

## Single-shot

```
# Infer from the chat we just had
/gh-setup:add-ai-metrics

# Tag exactly two cards
/gh-setup:add-ai-metrics issue#317 pr#320

# Tag every card created on one day
/gh-setup:add-ai-metrics --type issue --date 2026-04-30

# Force-recompute one card's footer
/gh-setup:add-ai-metrics issue#100 --force

# Quick burst over a small explicit list — no pacing needed
/gh-setup:add-ai-metrics issue#101 issue#102 issue#103 issue#104 issue#105
```

## Whole-month backfill

```
/gh-setup:add-ai-metrics --type PR --date 26-04
/gh-setup:add-ai-metrics --type issue --date 2026-04
```

Both expand to `created:2026-04-01..2026-04-30` (last day computed via
`date -d` → BSD `date` → Python 3 fallback chain). February handles leap
years correctly: `--date 24-02` → `created:2024-02-01..2024-02-29`,
`--date 26-02` → `created:2026-02-01..2026-02-28`.

## Range backfill — half-open `[start, end)`

```
# 4/3 through 4/10 inclusive — 4/11 excluded
/gh-setup:add-ai-metrics --type PR --date 26-04-03..26-04-11
/gh-setup:add-ai-metrics --type PR --date 26-04-03~26-04-11
```

`~` is normalized to `..` so muscle memory from "approximately X to Y"
also works. Internally both expand to `created:2026-04-03..2026-04-10`.
Half-open semantics match Python slice / git revision range — END is
excluded so adjacent ranges concatenate without overlap:
`A..B` then `B..C` covers `[A, C)` exactly once.

## Nightly bulk backfill — 5h-limit safe

```
# 1. Just before leaving — preview the run
/gh-setup:add-ai-metrics --type PR --date 26-04 --pace 3m --budget 4h30m --dry-run
# → "DRY RUN: 200 cards (180 will-write, 20 will-skip)"
# → "         pace=3m budget=4h30m limit=unset"
# → "         estimated wall-clock: 9h"

# 2. Confidence check passed — start the real run
/gh-setup:add-ai-metrics --type PR --date 26-04 --pace 3m --budget 4h30m
# → [OK] added #501 ...   (sleep 3m)
# → [OK] added #502 ...   (sleep 3m)
# → ...
# → Stopped early: --budget (4h30m); 110 cards remaining. Re-run the
#   same command to resume (skip-existing makes this idempotent).

# 3. Next morning, re-run the same command
#    First 90 cards already carry footers → skipped instantly (no API call,
#    no sleep). Loop reaches card 91 and continues.
/gh-setup:add-ai-metrics --type PR --date 26-04 --pace 3m --budget 4h30m
```

## Composing `--limit` and `--budget`

```
# Process at most 50 cards OR 4 hours, whichever comes first.
/gh-setup:add-ai-metrics --type PR --date 26-04 --pace 3m --limit 50 --budget 4h
```

Both bounds are checked at the **top of every iteration**. Exit message
identifies which one fired. `--limit` only counts cards that took the
modify path — skipped cards do not advance the counter, so re-running
the same command across a partially-processed list still yields exactly
`--limit` modifications per night.

## When to NOT use `--pace`

- Small explicit lists (≤ 10 cards). The 5h limit doesn't bite at this
  scale; pacing just slows you down.
- Single-card retries. `--force` on one card needs no pacing.
- CI / scripted backfills where wall-clock matters more than usage budget.

The default `--pace 0` (no pacing) is correct for these.
