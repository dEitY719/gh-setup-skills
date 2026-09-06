# Date Argument Parsing — `--date` forms

Contract for the `--date` flag of `gh-setup:add-ai-metrics`. The functions live
in [`lib/ai-metrics.sh`](../lib/ai-metrics.sh); this file says what each one
guarantees, so SKILL.md stays workflow-only and the behaviour has one home.

## Supported forms

The `--date` value falls into exactly one of four shapes. First match wins —
they are detected by **length and content**, not by sniffing prefixes.

| Form           | Example                       | Meaning                                    |
|----------------|-------------------------------|--------------------------------------------|
| month          | `26-04`, `2026-04`            | Whole month — 1st through last day         |
| range (`..`)   | `26-04-03..26-04-11`          | Half-open `[start, end)` — end excluded    |
| range (`~`)    | `26-04-03~26-04-11`           | Same as `..`; `~` is normalized to `..`    |
| single day     | `26-04-30`, `2026-04-30`      | Exactly one day (existing behavior)        |

Anything else → format error and stop.

## Year normalization

Two-digit `YY` always expands to `20YY`. We do **not** support 19xx or 21xx
shorthand — backfill is for cards that exist now, all in the 20xx range.

## `parse_date_arg` — top-level dispatch

Implemented as `parse_date_arg` / `_emit_month` in [`lib/ai-metrics.sh`](../lib/ai-metrics.sh).

It echoes exactly one of:

```
single <YYYY-MM-DD>
month  <YYYY-MM-DD> <YYYY-MM-DD>    start, end-of-month (inclusive)
range  <YYYY-MM-DD> <YYYY-MM-DD>    start, end-1day (already half-open adjusted)
```

Non-zero exit on a format error — the caller stops rather than guessing.

## `last_day_of_month` — leap-year safe, no `cal` dependency

Three-tier fallback: GNU `date` → BSD `date` → Python 3. Echoes a 2-digit
day (`28`, `29`, `30`, `31`).

Implemented as `last_day_of_month` in [`lib/ai-metrics.sh`](../lib/ai-metrics.sh).

## `_minus_one_day` — for half-open range conversion

Same fallback chain as `last_day_of_month`. Echoes `YYYY-MM-DD`.

Implemented as `_minus_one_day` in [`lib/ai-metrics.sh`](../lib/ai-metrics.sh).

## `_expand_day` — normalize one endpoint of a range

Accepts 8-char `YY-MM-DD` (expanded) or 10-char `YYYY-MM-DD` (passthrough).
Mismatched length → fail. Range halves of *different* lengths are accepted
(`26-04-03..2026-04-11` works) — each half is normalized independently.

Implemented as `_expand_day` in [`lib/ai-metrics.sh`](../lib/ai-metrics.sh).

## `build_search_clause` — assemble the GitHub query fragment

Takes the three-token output of `parse_date_arg` and emits the
`created:...` clause for `gh issue list --search` / `gh pr list --search`.

Implemented as `build_search_clause` in [`lib/ai-metrics.sh`](../lib/ai-metrics.sh).

```
build_search_clause <kind> <a> [<b>]
  single -> created:<a>
  month  -> created:<a>..<b>
  range  -> created:<a>..<b>    (b is already half-open adjusted)
```

## Examples — end-to-end

| Input                       | `parse_date_arg` output           | `build_search_clause`                  |
|-----------------------------|-----------------------------------|----------------------------------------|
| `26-04`                     | `month 2026-04-01 2026-04-30`     | `created:2026-04-01..2026-04-30`       |
| `2026-02`                   | `month 2026-02-01 2026-02-28`     | `created:2026-02-01..2026-02-28`       |
| `24-02` (leap)              | `month 2024-02-01 2024-02-29`     | `created:2024-02-01..2024-02-29`       |
| `26-04-03..26-04-11`        | `range 2026-04-03 2026-04-10`     | `created:2026-04-03..2026-04-10`       |
| `26-04-03~26-04-11`         | `range 2026-04-03 2026-04-10`     | `created:2026-04-03..2026-04-10`       |
| `26-04-30`                  | `single 2026-04-30`               | `created:2026-04-30`                   |
| `2026-04-30`                | `single 2026-04-30`               | `created:2026-04-30`                   |
| `26-4` (bad)                | exit 1                            | —                                      |
| `2026-04-03..` (bad)        | exit 1                            | —                                      |

## Why half-open `[start, end)` for ranges

Matches Python slice (`list[3:11]` excludes index 11), git revision range
(`commit1..commit2` excludes commit1's parent... well, mostly), and the
mental model "I want everything FROM Monday UP TO but not including next
Monday". Whole-month form is inclusive both ends because the unit IS the
month — there is no "exclude the last day" interpretation that makes sense.
