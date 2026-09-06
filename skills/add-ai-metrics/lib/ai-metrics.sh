#!/bin/bash

set -euo pipefail

# -----------------------------------------------------------------------------
# gh-setup:add-ai-metrics -- backfill the ai-metrics footer onto Issues/PRs.
#
# This file is the SSOT for every executable step of the skill. The reference
# files document what these functions guarantee; they no longer define them:
#   references/date-parsing.md      parse_date_arg .. build_search_clause
#   references/pace-control.md      parse_duration .. compute_eta
#   references/footer-detection.md  has_footer / append_footer / replace_footer
#   references/post-hoc-metrics.md  strip_footer / estimate_tokens / human_hours
#   references/repo-resolution.md   resolve_repo
#   references/constraints.md       the invariants all of the above uphold
#
# Idempotent: a card already carrying `<!-- ai-metrics -->` is skipped with zero
# `gh edit` calls and no sleep. Bytes outside the footer are never modified.
# Per-card failures print `[FAIL]` and continue; they never abort the loop.
# -----------------------------------------------------------------------------

SKILL_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BASELINE_FILE="$SKILL_DIR/references/metrics-baseline.md"

# Field separators for the single `gh view` call. US splits title from body;
# RS is a sentinel so $( ) cannot trim the body's trailing newlines.
US=$'\x1f'
RS=$'\x1e'

REPO=""
REMOTE="origin"
TYPE=""
DATE_ARG=""
FORCE=false
DRY_RUN=false
CONFIRM_LARGE=false
PACE_SECS=0
BUDGET_SECS=0
LIMIT=""
PACE_RAW="unset"
BUDGET_RAW="unset"
TARGETS=()

die() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

print_help() {
    cat <<'EOF'
gh-setup:add-ai-metrics -- backfill the ai-metrics footer onto Issues/PRs.

Usage:
  bash skills/add-ai-metrics/lib/ai-metrics.sh [targets] [options]

Targets:
  issue#N pr#M         Explicit cards (case-insensitive). Bare #N / N needs --type.
  --date <d>           Date filter instead of explicit cards: YY-MM, YYYY-MM,
                       YY-MM-DD, YYYY-MM-DD, or a half-open range A..B / A~B.
                       Mutually exclusive with positional cards.

Options:
  --repo <owner/repo>  Target repo (default: resolved from --remote).
  --remote <name>      Git remote to resolve repo + host from (default: origin).
  --type issue|PR      Restrict the card kind.
  --force              Recompute and replace an existing footer in place.
  --pace <dur>         Sleep after each modify (30s / 5m / 1h30m).
  --limit <n>          Stop after n MODIFIED cards (skips do not count).
  --budget <dur>       Stop once wall-clock elapsed reaches this duration.
  --dry-run            Classify and report; make zero `gh edit` calls.
  --confirm-large      Proceed past the 100-card threshold. Set it only after
                       the user actually answered y -- it is not a --yes.
  --self-test          Run the built-in assertions and exit. No API calls.
  -h, --help, help     Show this help.

Full spec: references/help.md
EOF
}

# --- date parsing (references/date-parsing.md) --------------------------------

# Echoes one of:
#   single <YYYY-MM-DD>
#   month  <YYYY-MM-DD> <YYYY-MM-DD>   (start, end-of-month; inclusive)
#   range  <YYYY-MM-DD> <YYYY-MM-DD>   (start, end-1day; half-open [start,end))
# Non-zero exit on format error.
parse_date_arg() {
    local raw="$1"
    # Normalize ~ to .. so range detection is single-pattern.
    local arg="${raw//\~/..}"

    # Range first -- '..' is a literal substring no other valid form produces.
    if [[ "$arg" == *..* ]]; then
        local start end
        start="${arg%%..*}"
        end="${arg##*..}"
        [ -n "$start" ] && [ -n "$end" ] || return 1
        start=$(_expand_day "$start") || return 1
        end=$(_expand_day "$end") || return 1
        # Half-open: subtract 1 day so GitHub's inclusive `created:A..B` query
        # honors [start, end) semantics.
        end=$(_minus_one_day "$end") || return 1
        printf 'range %s %s\n' "$start" "$end"
        return 0
    fi

    local yy mm yyyy
    case "${#arg}" in
        5) # YY-MM
            [[ "$arg" =~ ^[0-9]{2}-[0-9]{2}$ ]] || return 1
            yy="${arg%-*}"; mm="${arg#*-}"
            _emit_month "20$yy" "$mm"
            ;;
        7) # YYYY-MM
            [[ "$arg" =~ ^[0-9]{4}-[0-9]{2}$ ]] || return 1
            yyyy="${arg%-*}"; mm="${arg#*-}"
            _emit_month "$yyyy" "$mm"
            ;;
        8) # YY-MM-DD
            [[ "$arg" =~ ^[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]] || return 1
            printf 'single 20%s\n' "$arg"
            ;;
        10) # YYYY-MM-DD
            [[ "$arg" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
            printf 'single %s\n' "$arg"
            ;;
        *) return 1 ;;
    esac
}

_emit_month() {
    local yyyy="$1" mm="$2" last
    last=$(last_day_of_month "$yyyy" "$mm") || return 1
    printf 'month %s-%s-01 %s-%s-%s\n' "$yyyy" "$mm" "$yyyy" "$mm" "$last"
}

# Leap-year safe, no `cal` dependency. GNU date -> BSD date -> Python 3.
last_day_of_month() {
    local yyyy="$1" mm="$2" out=""
    if out=$(date -d "${yyyy}-${mm}-01 +1 month -1 day" +%d 2>/dev/null) && [ -n "$out" ]; then
        printf '%s\n' "$out"; return 0
    fi
    if out=$(date -j -f "%Y-%m-%d" -v+1m -v-1d "${yyyy}-${mm}-01" +%d 2>/dev/null) && [ -n "$out" ]; then
        printf '%s\n' "$out"; return 0
    fi
    if out=$(python3 -c "import calendar; print('%02d' % calendar.monthrange($yyyy, int('$mm'))[1])" 2>/dev/null) && [ -n "$out" ]; then
        printf '%s\n' "$out"; return 0
    fi
    return 1
}

# Same fallback chain as last_day_of_month. Echoes YYYY-MM-DD.
_minus_one_day() {
    local d="$1" out=""
    if out=$(date -d "$d -1 day" +%Y-%m-%d 2>/dev/null) && [ -n "$out" ]; then
        printf '%s\n' "$out"; return 0
    fi
    if out=$(date -j -f "%Y-%m-%d" -v-1d "$d" +%Y-%m-%d 2>/dev/null) && [ -n "$out" ]; then
        printf '%s\n' "$out"; return 0
    fi
    if out=$(python3 -c "import datetime; print((datetime.date.fromisoformat('$d') - datetime.timedelta(days=1)).isoformat())" 2>/dev/null) && [ -n "$out" ]; then
        printf '%s\n' "$out"; return 0
    fi
    return 1
}

# Accepts 8-char YY-MM-DD (expanded) or 10-char YYYY-MM-DD (passthrough).
# The two halves of a range are normalized independently.
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

# Usage: build_search_clause <kind> <a> [<b>]
build_search_clause() {
    local kind="$1" a="$2" b="${3:-}"
    case "$kind" in
        single) printf 'created:%s\n' "$a" ;;
        month|range) printf 'created:%s..%s\n' "$a" "$b" ;;
        *) return 1 ;;
    esac
}

# --- pace / limit / budget (references/pace-control.md) -----------------------

# Echoes seconds. Accepts the same shapes as `/loop` (GNU sleep compatible).
parse_duration() {
    local total=0 num unit
    local rest="$1"
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

# 90 -> "1m30s", 3600 -> "1h", 5400 -> "1h30m".
format_duration() {
    local s="$1" h m out=""
    h=$(( s / 3600 )); s=$(( s % 3600 ))
    m=$(( s / 60 ));   s=$(( s % 60 ))
    [ "$h" -gt 0 ] && out="${out}${h}h"
    [ "$m" -gt 0 ] && out="${out}${m}m"
    [ "$s" -gt 0 ] && out="${out}${s}s"
    [ -z "$out" ] && out="0s"
    printf '%s\n' "$out"
}

# Sleep $1 seconds. 0 (or unset) returns immediately -- no `sleep` invocation.
sleep_pace() {
    local secs="${1:-0}"
    [ "$secs" -gt 0 ] || return 0
    sleep "$secs"
}

# True (0) when the budget is exhausted and the loop should stop. Empty/0
# budget never stops. `>=` not `>`: stop one card early rather than overrun.
check_budget() {
    local elapsed="$1" budget="${2:-0}"
    [ "$budget" -gt 0 ] || return 1
    [ "$elapsed" -ge "$budget" ]
}

# Human ETA for N writes paced at S seconds. (writes - 1) gaps, because the
# pace sleep runs AFTER each card and is skipped after the last one.
compute_eta() {
    local writes="$1" pace_secs="${2:-0}" total
    if [ "$writes" -le 0 ]; then printf '0s (no writes)\n'; return 0; fi
    if [ "$pace_secs" -le 0 ]; then printf '<1m (no pace)\n'; return 0; fi
    total=$(( (writes - 1) * pace_secs ))
    [ "$total" -lt 0 ] && total=0
    format_duration "$total"
}

# --- footer detection / edit (references/footer-detection.md) -----------------

# True (0) only for an anchored `---` + OPEN/CLOSE marker pair. Inline mentions
# of the marker inside backticks do not match. Tolerates PR #320's `\n---\n`,
# the newer `\n\n---\n`, and the #367 <details> wrapper.
has_footer() {
    printf '%s' "$1" | perl -0777 -ne '
      exit (
        /\n+---\n(?:<details>\n<summary>[^\n]*<\/summary>\n\n)?<!-- ai-metrics(?::[A-Za-z0-9_-]+)? -->\n.*?\n<!-- \/ai-metrics(?::[A-Za-z0-9_-]+)? -->/s
        ? 0 : 1
      )'
}

append_footer() {
    local body="$1" tokens="$2" human="$3" elapsed="$4"
    printf '%s\n\n---\n<details>\n<summary>🤖 AI Metrics · 📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min</summary>\n\n<!-- ai-metrics -->\n📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min\n<!-- /ai-metrics -->\n\n</details>\n' \
        "$body" "$tokens" "$human" "$elapsed" "$tokens" "$human" "$elapsed"
}

# Always emits the new <details> form, upgrading an old bare footer in place.
# Returns the body unchanged when nothing matched -- the caller then degrades
# to append_footer, which is what makes --force work on an untagged card.
#
# Anchored on the same `\n+---\n` separator as has_footer, and for the same
# reason: unanchored, the pattern's first match is an INLINE mention of the
# marker in the body (a doc quoting the footer format), and everything from
# there to the real closing marker is replaced -- silent user-text loss on
# exactly the bodies has_footer was hardened against. The separator is
# captured and restored; $1 cannot collide with the env-carried $n.
replace_footer() {
    local body="$1" tokens="$2" human="$3" elapsed="$4" new_block
    new_block=$(printf '<details>\n<summary>🤖 AI Metrics · 📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min</summary>\n\n<!-- ai-metrics -->\n📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min\n<!-- /ai-metrics -->\n\n</details>' \
        "$tokens" "$human" "$elapsed" "$tokens" "$human" "$elapsed")
    printf '%s' "$body" \
        | NEW="$new_block" perl -0777 -pe '
            BEGIN { $n = $ENV{NEW} }
            s|(\n+---\n)(?:<details>\n<summary>[^\n]*</summary>\n\n)?<!-- ai-metrics(?::[A-Za-z0-9_-]+)? -->.*?<!-- /ai-metrics(?::[A-Za-z0-9_-]+)? -->(?:\n\n</details>)?|$1$n|s
          '
}

# --- post-hoc metrics (references/post-hoc-metrics.md) ------------------------

# Drop any existing footer so a --force re-run does not feed the previous
# footer's ~150 chars back into the token estimate. No-op when absent.
strip_footer() {
    printf '%s' "$1" | perl -0777 -pe 's|\n+---\n(?:<details>\n<summary>[^\n]*</summary>\n\n)?<!-- ai-metrics(?::[A-Za-z0-9_-]+)? -->.*?<!-- /ai-metrics(?::[A-Za-z0-9_-]+)? -->(?:\n\n</details>)?\n?||s'
}

# max(1000, round_to_500((len(title) + len(stripped)) / 4)); `wc -m` so
# multibyte Korean text counts as characters, not bytes.
estimate_tokens() {
    local title="$1" stripped="$2" chars tokens
    chars=$(printf '%s%s' "$title" "$stripped" | wc -m | awk '{print $1}')
    tokens=$(( (chars / 4 + 250) / 500 * 500 ))
    [ "$tokens" -lt 1000 ] && tokens=1000
    printf '%s\n' "$tokens"
}

title_prefix() {
    local prefix
    prefix=$(printf '%s' "$1" | sed -nE 's/^([a-z]+)(\([^)]*\))?:.*/\1/p')
    printf '%s\n' "${prefix:-misc}"
}

# Reads the Human Time Lookup Table out of references/metrics-baseline.md --
# that table stays the SSOT and this file holds no second copy. `feat` sizing
# needs conversation context that is gone post-hoc, so it always takes medium.
# Unknown or absent prefix falls back to misc (2 h).
human_hours() {
    local prefix="$1" want hours
    case "$prefix" in
        feat) want='`feat` (medium)' ;;
        *)    want="\`$prefix\`" ;;
    esac
    hours=$(awk -F'|' -v want="$want" '
        NF >= 4 {
            key = $2; val = $3
            gsub(/^[ \t]+|[ \t]+$/, "", key)
            gsub(/^[ \t]+|[ \t]+$/, "", val)
            if (key == want) { sub(/ *h.*/, "", val); print val; exit }
        }' "$BASELINE_FILE" 2>/dev/null || true)
    [ -n "$hours" ] || hours=2
    printf '%s\n' "$hours"
}

# ELAPSED = max(1, round(HUMAN_H * 60 * 0.05)) minutes.
estimate_elapsed() {
    awk -v h="$1" 'BEGIN { v = h * 60 * 0.05; printf "%d\n", (v < 1 ? 1 : v + 0.5) }'
}

# --- repo resolution (references/repo-resolution.md) --------------------------

# Sets TARGET_REPO / TARGET_HOST from ONE remote URL -- never from two sources.
# A missing remote is fatal: silently falling back to `origin` would rewrite
# card bodies in the wrong repo (dEitY719/dotfiles#1403).
resolve_repo() {
    local url="" ssot u
    if [ -n "$REPO" ]; then
        TARGET_REPO="$REPO"
        url=$(git remote get-url "$REMOTE" 2>/dev/null || true)
    else
        git rev-parse --show-toplevel >/dev/null 2>&1 || die "not inside a git repository."
        if ! url=$(git remote get-url "$REMOTE" 2>/dev/null); then
            printf "Error: remote '%s' not found. Available remotes:\n" "$REMOTE" >&2
            git remote -v >&2
            exit 1
        fi
    fi

    TARGET_HOST=""
    ssot="${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common/functions/gh_host.sh"
    if [ -n "$url" ] && [ -r "$ssot" ]; then
        # gh_host.sh is the SSOT for host/URL mapping when dotfiles is present.
        # shellcheck source=/dev/null
        . "$ssot"
        [ -n "$REPO" ] || TARGET_REPO=$(_gh_parse_owner_repo_url "$url" 2>/dev/null || true)
        TARGET_HOST=$(_gh_host_from_url "$url" 2>/dev/null || _gh_resolve_host 2>/dev/null || true)
    elif [ -n "$url" ]; then
        # Standalone install -- strip scheme, credentials and the .git suffix,
        # then split on the first ':' or '/'.
        u=${url%.git}; u=${u#*://}; u=${u#*@}
        TARGET_HOST=${u%%[:/]*}
        [ -n "$REPO" ] || TARGET_REPO=${u#*[:/]}
    fi
    [ -n "$TARGET_HOST" ] || TARGET_HOST="github.com"
    [ -n "${TARGET_REPO:-}" ] || die "could not resolve owner/repo from remote '$REMOTE'."
    # An empty GH_HOST is exactly the silent wrong-host state of #1403.
    export GH_HOST="$TARGET_HOST"
    export TARGET_REPO TARGET_HOST
}

# --- argument parsing ---------------------------------------------------------

parse_args() {
    local raw n
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help|help) print_help; exit 0 ;;
            --self-test) self_test; exit 0 ;;
            --repo) REPO="${2:-}"; [ -n "$REPO" ] || die "--repo needs a value."; shift 2 ;;
            --remote) REMOTE="${2:-}"; [ -n "$REMOTE" ] || die "--remote needs a value."; shift 2 ;;
            --type)
                raw=$(printf '%s' "${2:-}" | tr '[:upper:]' '[:lower:]')
                case "$raw" in
                    issue|issues) TYPE="issue" ;;
                    pr|prs) TYPE="pr" ;;
                    *) die "--type must be issue or PR." ;;
                esac
                shift 2 ;;
            --date) DATE_ARG="${2:-}"; [ -n "$DATE_ARG" ] || die "--date needs a value."; shift 2 ;;
            --force) FORCE=true; shift ;;
            --dry-run) DRY_RUN=true; shift ;;
            --confirm-large) CONFIRM_LARGE=true; shift ;;
            --pace)
                PACE_RAW="${2:-}"
                PACE_SECS=$(parse_duration "$PACE_RAW") \
                    || die "--pace: bad duration '$PACE_RAW' (use 30s / 5m / 1h30m)."
                shift 2 ;;
            --budget)
                BUDGET_RAW="${2:-}"
                BUDGET_SECS=$(parse_duration "$BUDGET_RAW") \
                    || die "--budget: bad duration '$BUDGET_RAW' (use 30s / 5m / 1h30m)."
                shift 2 ;;
            --limit)
                LIMIT="${2:-}"
                [[ "$LIMIT" =~ ^[1-9][0-9]*$ ]] || die "--limit must be a positive integer."
                shift 2 ;;
            -*) die "unknown option '$1'. Try --help." ;;
            *)
                raw=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
                case "$raw" in
                    issue#*) n="${raw#issue#}"; _add_target issue "$n" ;;
                    pr#*)    n="${raw#pr#}";    _add_target pr "$n" ;;
                    \#*)     n="${raw#\#}";     _add_target "${TYPE:-issue}" "$n" ;;
                    *)       _add_target "${TYPE:-issue}" "$raw" ;;
                esac
                shift ;;
        esac
    done

    [ -z "$DATE_ARG" ] || [ "${#TARGETS[@]}" -eq 0 ] \
        || die "--date and positional cards are mutually exclusive."
}

# Validate, dedupe, preserve order.
_add_target() {
    local kind="$1" n="$2" t
    [[ "$n" =~ ^[1-9][0-9]*$ ]] || die "not a card number: '$n'."
    for t in ${TARGETS[@]+"${TARGETS[@]}"}; do
        [ "$t" = "$kind:$n" ] && return 0
    done
    TARGETS+=("$kind:$n")
}

# --- target list --------------------------------------------------------------

# The 200 cap stays -- a wider range is split by the user, not paginated here.
build_targets_from_date() {
    local parsed kind a b clause line
    parsed=$(parse_date_arg "$DATE_ARG") \
        || die "--date: unrecognized form '$DATE_ARG' (YY-MM, YYYY-MM-DD, A..B)."
    read -r kind a b <<<"$parsed"
    clause=$(build_search_clause "$kind" "$a" "$b")

    local kinds=(issue pr)
    [ -z "$TYPE" ] || kinds=("$TYPE")
    for kind in "${kinds[@]}"; do
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            TARGETS+=("$kind:$line")
        done < <(gh "$kind" list --repo "$TARGET_REPO" --search "$clause" \
            --state all --limit 200 --json number --jq '.[].number' 2>/dev/null || true)
    done
}

# --- per-card work ------------------------------------------------------------

# One `gh view` per card, title and body in a single response. Sets the
# CARD_TITLE / CARD_BODY globals (and FETCH_ERR on failure) directly -- must
# be called plain (`fetch_card ...`), never inside `$(fetch_card ...)`. A
# command substitution forks a subshell, so those globals would be set there
# and vanish the instant the substitution completes, leaving the caller with
# an empty title/body for every card.
fetch_card() {
    local kind="$1" n="$2" raw
    if ! raw=$(gh "$kind" view "$n" --repo "$TARGET_REPO" --json title,body \
        --jq '.title + "\u001f" + .body + "\u001e"' 2>&1); then
        FETCH_ERR="$raw"
        return 1
    fi
    raw="${raw%"$RS"}"
    CARD_TITLE="${raw%%"$US"*}"
    CARD_BODY="${raw#*"$US"}"
}

compute_metrics() {
    local stripped prefix
    stripped=$(strip_footer "$CARD_BODY")
    M_TOKENS=$(estimate_tokens "$CARD_TITLE" "$stripped")
    prefix=$(title_prefix "$CARD_TITLE")
    M_HUMAN=$(human_hours "$prefix")
    M_ELAPSED=$(estimate_elapsed "$M_HUMAN")
}

# Always via mktemp -- `--body "$str"` mishandles backticks and large bodies.
write_body() {
    local kind="$1" n="$2" new_body="$3" tmp rc=0
    tmp=$(mktemp)
    printf '%s' "$new_body" >"$tmp"
    gh "$kind" edit "$n" --repo "$TARGET_REPO" --body-file "$tmp" >/dev/null 2>&1 || rc=$?
    rm -f "$tmp"
    return "$rc"
}

# --- main loop ----------------------------------------------------------------

run() {
    local total added=0 replaced=0 skipped=0 failed=0 modified=0
    local will_write=0 will_replace=0 will_skip=0
    local stop_reason="" elapsed_secs entry kind n new_body err answer done_n
    local pending_sleep=false

    total="${#TARGETS[@]}"
    [ "$total" -gt 0 ] || die "no target cards. Pass issue#N / pr#M or --date."

    if [ "$total" -gt 100 ] && [ "$CONFIRM_LARGE" != true ]; then
        if [ -t 0 ]; then
            printf 'Continue with %s cards? [y/N]: ' "$total"
            read -r answer || answer=""
            case "$answer" in y|Y) ;; *) die "aborted at the 100-card threshold." ;; esac
        else
            die "$total cards exceed the 100-card threshold. Ask the user, then re-run with --confirm-large."
        fi
    fi

    for entry in "${TARGETS[@]}"; do
        kind="${entry%%:*}"
        n="${entry#*:}"

        # A pace sleep is credited to the modify that earned it but deferred
        # to the top of the NEXT iteration -- so it still lands "after that
        # modify" for any card but the last, and simply never fires when the
        # modify was the last target in the run (no next iteration exists to
        # trigger it). This also means a skip-only tail after the final
        # modify costs one sleep, not one per skip.
        if [ "$pending_sleep" = true ]; then
            sleep_pace "$PACE_SECS"
            pending_sleep=false
        fi

        # Stop check at the TOP of the iteration, in seconds (not the
        # minutes-rounded figure the final report prints).
        if [ "$DRY_RUN" != true ]; then
            elapsed_secs=$(( $(date +%s) - START_TS ))
            if check_budget "$elapsed_secs" "$BUDGET_SECS"; then
                stop_reason="--budget ($(format_duration "$BUDGET_SECS"))"
                break
            fi
            if [ -n "$LIMIT" ] && [ "$modified" -ge "$LIMIT" ]; then
                stop_reason="--limit ($LIMIT cards modified)"
                break
            fi
        fi

        if ! fetch_card "$kind" "$n"; then
            err=$(printf '%s' "$FETCH_ERR" | head -1)
            if [ "$DRY_RUN" = true ]; then
                printf '· would-fail #%s %s\n' "$n" "$err"
            else
                printf '[FAIL] failed #%s %s\n' "$n" "$err"
                failed=$((failed + 1))
            fi
            continue
        fi

        if has_footer "$CARD_BODY"; then
            if [ "$FORCE" != true ]; then
                # Skip path: no gh edit, no body diff, no sleep.
                if [ "$DRY_RUN" = true ]; then
                    will_skip=$((will_skip + 1))
                    printf '· will-skip #%s %s\n' "$n" "$CARD_TITLE"
                else
                    skipped=$((skipped + 1))
                    printf '[SKIP] skipped #%s %s\n' "$n" "$CARD_TITLE"
                fi
                continue
            fi
            if [ "$DRY_RUN" = true ]; then
                will_replace=$((will_replace + 1))
                printf '· will-force-replace #%s %s\n' "$n" "$CARD_TITLE"
                continue
            fi
            compute_metrics
            new_body=$(replace_footer "$CARD_BODY" "$M_TOKENS" "$M_HUMAN" "$M_ELAPSED")
            if write_body "$kind" "$n" "$new_body"; then
                replaced=$((replaced + 1)); modified=$((modified + 1))
                printf '[REPLACED] replaced #%s %s\n' "$n" "$CARD_TITLE"
                pending_sleep=true
            else
                failed=$((failed + 1))
                printf '[FAIL] failed #%s gh %s edit returned non-zero\n' "$n" "$kind"
            fi
            continue
        fi

        if [ "$DRY_RUN" = true ]; then
            will_write=$((will_write + 1))
            printf '· will-write #%s %s\n' "$n" "$CARD_TITLE"
            continue
        fi
        compute_metrics
        # --force on a card with no footer degrades to a plain append.
        new_body=$(append_footer "$CARD_BODY" "$M_TOKENS" "$M_HUMAN" "$M_ELAPSED")
        if write_body "$kind" "$n" "$new_body"; then
            added=$((added + 1)); modified=$((modified + 1))
            printf '[OK] added #%s %s\n' "$n" "$CARD_TITLE"
            pending_sleep=true
        else
            failed=$((failed + 1))
            printf '[FAIL] failed #%s gh %s edit returned non-zero\n' "$n" "$kind"
        fi
    done

    if [ "$DRY_RUN" = true ]; then
        printf 'DRY RUN: %s cards (%s will-write, %s will-force-replace, %s will-skip)\n' \
            "$total" "$will_write" "$will_replace" "$will_skip"
        printf '         pace=%s budget=%s limit=%s\n' \
            "$PACE_RAW" "$BUDGET_RAW" "${LIMIT:-unset}"
        printf '         estimated wall-clock: %s\n' \
            "$(compute_eta $((will_write + will_replace)) "$PACE_SECS")"
        return 0
    fi

    done_n=$((added + replaced + skipped + failed))
    printf 'Summary: added=%s  replaced=%s  skipped=%s  failed=%s  (total %s)\n' \
        "$added" "$replaced" "$skipped" "$failed" "$total"
    if [ -n "$stop_reason" ]; then
        printf 'Stopped early: %s; %s cards remaining. Re-run to resume (idempotent).\n' \
            "$stop_reason" "$((total - done_n))"
    fi
    printf '[ai-metrics:gh-setup-add-ai-metrics] ~%s min · %s cards processed\n' \
        "$(( ($(date +%s) - START_TS) / 60 ))" "$done_n"
}

# --- self-test ----------------------------------------------------------------

_ok() {
    if [ "$2" = "$3" ]; then
        printf 'ok    %s\n' "$1"
    else
        printf 'FAIL  %s: expected [%s], got [%s]\n' "$1" "$3" "$2" >&2
        exit 1
    fi
}

# Pure-function assertions only. Makes zero API calls.
self_test() {
    _ok 'parse_date_arg month'   "$(parse_date_arg 26-04)"              'month 2026-04-01 2026-04-30'
    _ok 'parse_date_arg leap'    "$(parse_date_arg 24-02)"              'month 2024-02-01 2024-02-29'
    _ok 'parse_date_arg yyyy-mm' "$(parse_date_arg 2026-02)"            'month 2026-02-01 2026-02-28'
    _ok 'parse_date_arg range'   "$(parse_date_arg 26-04-03..26-04-11)" 'range 2026-04-03 2026-04-10'
    _ok 'parse_date_arg tilde'   "$(parse_date_arg 26-04-03~26-04-11)"  'range 2026-04-03 2026-04-10'
    _ok 'parse_date_arg mixed'   "$(parse_date_arg 26-04-03..2026-04-11)" 'range 2026-04-03 2026-04-10'
    _ok 'parse_date_arg single'  "$(parse_date_arg 26-04-30)"           'single 2026-04-30'
    _ok 'parse_date_arg bad'     "$(parse_date_arg 26-4 || echo rejected)"         'rejected'
    _ok 'parse_date_arg openend' "$(parse_date_arg 2026-04-03.. || echo rejected)" 'rejected'

    _ok 'build_search_clause day'   "$(build_search_clause single 2026-04-30)"           'created:2026-04-30'
    _ok 'build_search_clause month' "$(build_search_clause month 2026-04-01 2026-04-30)" 'created:2026-04-01..2026-04-30'

    _ok 'parse_duration 30s'   "$(parse_duration 30s)"   '30'
    _ok 'parse_duration 1h30m' "$(parse_duration 1h30m)" '5400'
    _ok 'parse_duration 1m30s' "$(parse_duration 1m30s)" '90'
    _ok 'parse_duration bare'  "$(parse_duration 3 || echo rejected)"    'rejected'
    _ok 'parse_duration days'  "$(parse_duration 5d || echo rejected)"   'rejected'
    _ok 'parse_duration frac'  "$(parse_duration 1.5h || echo rejected)" 'rejected'
    _ok 'parse_duration empty' "$(parse_duration '' || echo rejected)"   'rejected'

    _ok 'format_duration 90'   "$(format_duration 90)"   '1m30s'
    _ok 'format_duration 3600' "$(format_duration 3600)" '1h'
    _ok 'format_duration 0'    "$(format_duration 0)"    '0s'

    _ok 'check_budget under' "$(check_budget 16199 16200 && echo stop || echo go)" 'go'
    _ok 'check_budget at'    "$(check_budget 16200 16200 && echo stop || echo go)" 'stop'
    _ok 'check_budget unset' "$(check_budget 99999 0 && echo stop || echo go)"     'go'

    _ok 'compute_eta one'  "$(compute_eta 1 180)"  '0s'
    _ok 'compute_eta many' "$(compute_eta 12 180)" '33m'
    _ok 'compute_eta none' "$(compute_eta 0 180)"  '0s (no writes)'

    local body tagged legacy
    body=$(printf 'Title line\n\nText mentioning `<!-- ai-metrics -->` inline.\n')
    _ok 'has_footer inline-only'  "$(has_footer "$body" && echo yes || echo no)" 'no'

    tagged=$(append_footer "$body" 1500 2 6)
    _ok 'has_footer appended'     "$(has_footer "$tagged" && echo yes || echo no)" 'yes'
    _ok 'strip_footer round-trip' "$(strip_footer "$tagged")" "$body"

    legacy=$(printf '%s\n---\n<!-- ai-metrics -->\nold numbers\n<!-- /ai-metrics -->\n' "$body")
    _ok 'has_footer legacy bare'    "$(has_footer "$legacy" && echo yes || echo no)" 'yes'
    _ok 'strip_footer legacy'       "$(strip_footer "$legacy")" "$body"
    _ok 'replace_footer upgrades'   "$(replace_footer "$legacy" 1500 2 6 | grep -c '<details>')" '1'
    _ok 'replace_footer idempotent' "$(replace_footer "$tagged" 1500 2 6)" "$tagged"
    _ok 'replace_footer no-match'   "$(replace_footer "$body" 1500 2 6)" "$body"

    _ok 'title_prefix scoped'   "$(title_prefix 'fix(core): thing')" 'fix'
    _ok 'title_prefix none'     "$(title_prefix 'Just a title')"     'misc'
    _ok 'human_hours docs'      "$(human_hours docs)"  '1'
    _ok 'human_hours chore'     "$(human_hours chore)" '0.5'
    _ok 'human_hours feat'      "$(human_hours feat)"  '8'
    _ok 'human_hours unknown'   "$(human_hours zzz)"   '2'
    _ok 'estimate_elapsed 8h'   "$(estimate_elapsed 8)"   '24'
    _ok 'estimate_elapsed half' "$(estimate_elapsed 0.5)" '2'
    _ok 'estimate_tokens floor' "$(estimate_tokens 'hi' 'there')" '1000'

    printf 'all self-tests passed\n'
}

main() {
    START_TS=$(date +%s)
    parse_args "$@"
    resolve_repo
    [ -z "$DATE_ARG" ] || build_targets_from_date
    run
}

main "$@"
