# Pace / Limit / Budget — overnight backfill controls

Contract for the `--pace`, `--limit`, `--budget`, and `--dry-run` flags of
`gh-setup:add-ai-metrics`. The functions live in [`lib/ai-metrics.sh`](../lib/ai-metrics.sh);
this file says what each one guarantees.

## `parse_duration` — `30s` / `5m` / `1h` / `1h30m` → seconds

Implemented as `parse_duration` in [`lib/ai-metrics.sh`](../lib/ai-metrics.sh).

Echoes seconds. Non-zero exit on bad input.

Examples: `30s` → 30, `5m` → 300, `1h` → 3600, `1h30m` → 5400.
Rejects: empty, `3` (no unit), `5d` (unsupported), `1.5h` (no fractions),
`1h30` (trailing bare number).

## `format_duration` — seconds → human string for ETA output

Implemented as `format_duration` in [`lib/ai-metrics.sh`](../lib/ai-metrics.sh).

## `sleep_pace` — no-op when 0

Implemented as `sleep_pace` in [`lib/ai-metrics.sh`](../lib/ai-metrics.sh).

Sleeps `$1` seconds; 0 or unset returns immediately, with no `sleep` invocation at all.

## `check_budget` — should we stop before the next card?

Implemented as `check_budget` in [`lib/ai-metrics.sh`](../lib/ai-metrics.sh).

Returns 0 (true) when the budget is exhausted and the loop should stop, 1
(false) when there is room for at least one more card. An empty or 0 budget
never stops.

We compare `elapsed >= budget` (not `>`), so a budget of `4h30m` (16200s)
and an elapsed of exactly 16200s stops. Off-by-one in the conservative
direction — we'd rather stop one card early than burn into the limit.

## `compute_eta` — for `--dry-run` output

Implemented as `compute_eta` in [`lib/ai-metrics.sh`](../lib/ai-metrics.sh).

Echoes a human ETA for N writes paced at S seconds. Skip-only runs (writes=0) give `0s (no writes)`.

The `(writes - 1)` accounts for the SKILL.md "sleep AFTER each card,
except last" rule — N writes have N-1 gaps.

## Stop-reason composition (`--limit` + `--budget`)

When both are set, the loop stops on whichever fires first. The stop check
runs at the TOP of each iteration, before the next card is fetched, and the
stop message identifies which flag fired:

The check is in `run()` in [`lib/ai-metrics.sh`](../lib/ai-metrics.sh). `elapsed_secs`
there is in SECONDS, recomputed each iteration — not the minutes-rounded
figure the final report prints.

`modified_count` only counts cards that took the write/replace path —
skipped cards (footer present, no `--force`) do not advance the limit
counter. This makes "process 50 NEW backfills tonight" a deterministic
unit, even when re-running over a partially-processed list.

## `--dry-run` branch — what it prints, what it skips

Dry-run does NOT call `gh edit`. It still calls `gh view` (the `view` is
how state classification — `will-write` vs `will-skip` vs
`will-force-replace` — is decided; without it the ETA would be a guess).
Per-card output uses a distinct glyph so dry-run rows are visually
separable from real-run rows:

| Branch                       | Real-run line          | Dry-run line                  |
|------------------------------|------------------------|-------------------------------|
| no footer                    | `[OK] added #N <title>`   | `· will-write #N <title>`     |
| footer + `--force`           | `[REPLACED] replaced #N <title>` | `· will-force-replace #N <title>` |
| footer + no `--force`        | `[SKIP] skipped #N <title>` | `· will-skip #N <title>`      |
| view failed                  | `[FAIL] failed #N <reason>` | `· would-fail #N <reason>`    |

Final dry-run summary line:

```
DRY RUN: T cards (W will-write, F will-force-replace, S will-skip)
         pace=PACE budget=BUDGET limit=LIMIT
         estimated wall-clock: ETA
```

`PACE`, `BUDGET`, `LIMIT` — display `unset` when the flag was not passed.

## Resume semantics — natural via skip-existing

The original skip-existing behavior already provides a free resume:

1. Run #1 stops at card N due to `--budget` (M cards modified, X cards
   ahead untouched).
2. Re-running the same command: cards 1..N already carry footers → all
   skipped (no API call) → loop reaches card N+1 in seconds.
3. Continues from N+1 with the rest of the budget.

No `--resume` flag, no state file, no checkpoint format. The card body
itself IS the persisted state.

## Test rubric

A pacing run is correct iff:

1. `parse_duration` accepts `30s`, `5m`, `1h`, `1h30m`, `1m30s` and
   rejects `3`, `5d`, `1.5h`, empty.
2. `sleep_pace 0` returns in <50ms (no actual `sleep` invocation).
3. `check_budget 16199 16200` → false (1); `check_budget 16200 16200` → true (0).
4. `compute_eta 1 180` → `0s` (one write, no gap); `compute_eta 12 180` → `33m`.
5. `--dry-run` makes zero `gh edit` calls (verified via fake-shim log).
6. `--limit 50` stops after 50 *modified* cards, ignoring skips in the count.
7. Re-running the same command on the same target list after a budget
   stop produces zero edit calls until reaching the first un-footered card.
