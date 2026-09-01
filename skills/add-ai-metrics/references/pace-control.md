# Pace / Limit / Budget — overnight backfill controls

Shell helpers for the `--pace`, `--limit`, `--budget`, and `--dry-run` flags
of `gh-setup:add-ai-metrics`. Pulled out of SKILL.md so the unit logic is
bats-testable and the SKILL.md prose stays workflow-only.

## `parse_duration` — `30s` / `5m` / `1h` / `1h30m` → seconds

```bash
# Echoes seconds (integer). Exits non-zero on bad input.
# Accepts the same shapes as `/loop` (GNU sleep compatible).
parse_duration() {
  local raw="$1"
  local total=0 num unit
  local rest="$raw"
  [ -n "$rest" ] || return 1
  while [ -n "$rest" ]; do
    [[ "$rest" =~ ^([0-9]+)([smh])(.*)$ ]] || return 1
    num="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2]}"
    rest="${BASH_REMATCH[3]}"
    case "$unit" in
      s) total=$((total + num)) ;;
      m) total=$((total + num * 60)) ;;
      h) total=$((total + num * 3600)) ;;
    esac
  done
  printf '%s\n' "$total"
}
```

Examples: `30s` → 30, `5m` → 300, `1h` → 3600, `1h30m` → 5400.
Rejects: empty, `3` (no unit), `5d` (unsupported), `1.5h` (no fractions),
`1h30` (trailing bare number).

## `format_duration` — seconds → human string for ETA output

```bash
# Echoes a compact human form: 90 → "1m30s", 3600 → "1h", 5400 → "1h30m".
format_duration() {
  local s="$1" h m
  h=$(( s / 3600 )); s=$(( s % 3600 ))
  m=$(( s / 60 ));   s=$(( s % 60 ))
  local out=""
  [ "$h" -gt 0 ] && out="${out}${h}h"
  [ "$m" -gt 0 ] && out="${out}${m}m"
  [ "$s" -gt 0 ] && out="${out}${s}s"
  [ -z "$out" ] && out="0s"
  printf '%s\n' "$out"
}
```

## `sleep_pace` — no-op when 0

```bash
# Sleep $1 seconds. 0 (or unset) → return immediately, no `sleep` invocation.
sleep_pace() {
  local secs="${1:-0}"
  [ "$secs" -gt 0 ] || return 0
  sleep "$secs"
}
```

## `check_budget` — should we stop before the next card?

```bash
# Returns 0 (true) when the budget is exhausted and the loop should stop.
# Returns 1 (false) when there is room to process at least one more card.
# Empty / 0 budget → never stops (1).
#
# Usage at top of each loop iteration:
#   check_budget "$elapsed" "$budget_secs" && break
check_budget() {
  local elapsed="$1" budget="${2:-0}"
  [ "$budget" -gt 0 ] || return 1
  [ "$elapsed" -ge "$budget" ]
}
```

We compare `elapsed >= budget` (not `>`), so a budget of `4h30m` (16200s)
and an elapsed of exactly 16200s stops. Off-by-one in the conservative
direction — we'd rather stop one card early than burn into the limit.

## `compute_eta` — for `--dry-run` output

```bash
# Echoes a human ETA string for N writes paced at S seconds.
# Skip-only runs (writes=0) → "0s (no writes)".
compute_eta() {
  local writes="$1" pace_secs="${2:-0}"
  if [ "$writes" -le 0 ]; then
    printf '0s (no writes)\n'
    return 0
  fi
  if [ "$pace_secs" -le 0 ]; then
    printf '<1m (no pace)\n'
    return 0
  fi
  # (writes - 1) gaps × pace, since "after" sleep skips the trailing wait.
  local total=$(( (writes - 1) * pace_secs ))
  [ "$total" -lt 0 ] && total=0
  format_duration "$total"
}
```

The `(writes - 1)` accounts for the SKILL.md "sleep AFTER each card,
except last" rule — N writes have N-1 gaps.

## Stop-reason composition (`--limit` + `--budget`)

When both are set, the loop stops on whichever fires first. The stop
message identifies which one:

```bash
# Inside the per-card loop, BEFORE processing the next card.
# elapsed_secs is in SECONDS — recomputed each iteration. Do not
# substitute the minutes-rounded ELAPSED used by Step 4's display line.
elapsed_secs=$(( $(date +%s) - START_TS ))
if check_budget "$elapsed_secs" "$budget_secs"; then
  stop_reason="--budget ($(format_duration "$budget_secs"))"
  break
fi
if [ -n "$LIMIT" ] && [ "$modified_count" -ge "$LIMIT" ]; then
  stop_reason="--limit ($LIMIT cards modified)"
  break
fi
```

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
