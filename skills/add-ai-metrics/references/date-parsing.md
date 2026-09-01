# Date Argument Parsing — `--date` forms

Parsing helpers for the `--date` flag of `gh-setup:add-ai-metrics`. Pulled out of
SKILL.md so the per-form regex/expansion logic is bats-testable and the
SKILL.md prose stays workflow-only.

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

```bash
# Echoes one of:
#   single <YYYY-MM-DD>
#   month  <YYYY-MM-DD> <YYYY-MM-DD>     (start, end-of-month)
#   range  <YYYY-MM-DD> <YYYY-MM-DD>     (start, end-1day — already half-open
#                                          adjusted, ready for GitHub query)
# Exits non-zero on format error.
parse_date_arg() {
  local raw="$1"
  # Normalize ~ to .. so range detection is single-pattern.
  local arg="${raw//\~/..}"

  # Range first — must check before single forms because '..' is a literal
  # substring not produced by any other valid form.
  if [[ "$arg" == *..* ]]; then
    local start end
    start="${arg%%..*}"
    end="${arg##*..}"
    [ -n "$start" ] && [ -n "$end" ] || return 1
    start=$(_expand_day "$start") || return 1
    end=$(_expand_day "$end") || return 1
    # Half-open: subtract 1 day from end so GitHub's inclusive `created:A..B`
    # query honors [start, end) semantics.
    end=$(_minus_one_day "$end") || return 1
    printf 'range %s %s\n' "$start" "$end"
    return 0
  fi

  case "${#arg}" in
    5)  # YY-MM
      [[ "$arg" =~ ^[0-9]{2}-[0-9]{2}$ ]] || return 1
      local yy="${arg%-*}" mm="${arg#*-}"
      _emit_month "20$yy" "$mm"
      ;;
    7)  # YYYY-MM
      [[ "$arg" =~ ^[0-9]{4}-[0-9]{2}$ ]] || return 1
      local yyyy="${arg%-*}" mm="${arg#*-}"
      _emit_month "$yyyy" "$mm"
      ;;
    8)  # YY-MM-DD
      [[ "$arg" =~ ^[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]] || return 1
      printf 'single 20%s\n' "$arg"
      ;;
    10) # YYYY-MM-DD
      [[ "$arg" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
      printf 'single %s\n' "$arg"
      ;;
    *)  return 1 ;;
  esac
}

_emit_month() {
  local yyyy="$1" mm="$2"
  local last
  last=$(last_day_of_month "$yyyy" "$mm") || return 1
  printf 'month %s-%s-01 %s-%s-%s\n' "$yyyy" "$mm" "$yyyy" "$mm" "$last"
}
```

## `last_day_of_month` — leap-year safe, no `cal` dependency

Three-tier fallback: GNU `date` → BSD `date` → Python 3. Echoes a 2-digit
day (`28`, `29`, `30`, `31`).

```bash
last_day_of_month() {
  local yyyy="$1" mm="$2" out=""
  # GNU date (Linux, WSL, most CI)
  out=$(date -d "${yyyy}-${mm}-01 +1 month -1 day" +%d 2>/dev/null) \
    && [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
  # BSD date (macOS)
  out=$(date -j -f "%Y-%m-%d" -v+1m -v-1d "${yyyy}-${mm}-01" +%d 2>/dev/null) \
    && [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
  # Python 3 fallback (final resort)
  out=$(python3 -c "import calendar; print('%02d' % calendar.monthrange($yyyy, int('$mm'))[1])" 2>/dev/null) \
    && [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
  return 1
}
```

## `_minus_one_day` — for half-open range conversion

Same fallback chain as `last_day_of_month`. Echoes `YYYY-MM-DD`.

```bash
_minus_one_day() {
  local d="$1" out=""
  out=$(date -d "$d -1 day" +%Y-%m-%d 2>/dev/null) \
    && [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
  out=$(date -j -f "%Y-%m-%d" -v-1d "$d" +%Y-%m-%d 2>/dev/null) \
    && [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
  out=$(python3 -c "import datetime; print((datetime.date.fromisoformat('$d') - datetime.timedelta(days=1)).isoformat())" 2>/dev/null) \
    && [ -n "$out" ] && { printf '%s\n' "$out"; return 0; }
  return 1
}
```

## `_expand_day` — normalize one endpoint of a range

Accepts 8-char `YY-MM-DD` (expanded) or 10-char `YYYY-MM-DD` (passthrough).
Mismatched length → fail. Range halves of *different* lengths are accepted
(`26-04-03..2026-04-11` works) — each half is normalized independently.

```bash
_expand_day() {
  local d="$1"
  case "${#d}" in
    8)  [[ "$d" =~ ^[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]] || return 1
        printf '20%s\n' "$d" ;;
    10) [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
        printf '%s\n' "$d" ;;
    *)  return 1 ;;
  esac
}
```

## `build_search_clause` — assemble the GitHub query fragment

Takes the three-token output of `parse_date_arg` and emits the
`created:...` clause for `gh issue list --search` / `gh pr list --search`.

```bash
# Usage: build_search_clause <kind> <a> [<b>]
#   kind=single → "created:<a>"
#   kind=month  → "created:<a>..<b>"
#   kind=range  → "created:<a>..<b>"   (b is already half-open adjusted)
build_search_clause() {
  local kind="$1" a="$2" b="$3"
  case "$kind" in
    single) printf 'created:%s\n' "$a" ;;
    month|range) printf 'created:%s..%s\n' "$a" "$b" ;;
    *) return 1 ;;
  esac
}
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
