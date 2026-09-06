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
TARGETS=()
AMBIGUOUS=()

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
            _valid_calendar_date "20$arg" || return 1
            printf 'single 20%s\n' "$arg"
            ;;
        10) # YYYY-MM-DD
            [[ "$arg" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
            _valid_calendar_date "$arg" || return 1
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
    local d="$1" expanded
    case "${#d}" in
        8)  [[ "$d" =~ ^[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]] || return 1
            expanded="20$d" ;;
        10) [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
            expanded="$d" ;;
        *)  return 1 ;;
    esac
    _valid_calendar_date "$expanded" || return 1
    printf '%s\n' "$expanded"
}

# True (0) only when $1 (YYYY-MM-DD) is a real calendar date, not just
# regex-shaped -- rejects e.g. 2024-02-30 (April has 30 days, February
# never does). Regex alone lets that straight through to either a
# confusing zero-results `created:` search clause, or into
# _minus_one_day's date arithmetic, whose behavior on an invalid date is
# not guaranteed the same across the GNU/BSD/python3 fallback chain --
# some accept and silently roll it into the next month instead of
# erroring. The round-trip compare below (`$out` = `$d`) is what catches
# that silent-rollover case even on a tier that "succeeds": if the tier
# normalized the date instead of rejecting it, the output no longer
# matches the input and this falls through to the next, stricter tier.
_valid_calendar_date() {
    local d="$1" out
    if out=$(date -d "$d" +%F 2>/dev/null) && [ "$out" = "$d" ]; then
        return 0
    fi
    if out=$(date -j -f "%Y-%m-%d" "$d" +%F 2>/dev/null) && [ "$out" = "$d" ]; then
        return 0
    fi
    python3 -c "import datetime,sys; datetime.date.fromisoformat(sys.argv[1])" "$d" >/dev/null 2>&1
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
    chars=$(printf '%s%s' "$title" "$stripped" | wc -m)
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
        # --repo names the target explicitly and may point at a repo on a
        # different host than this checkout's own $REMOTE entirely -- the
        # local remote's URL is not evidence of anything here. (The earlier
        # version borrowed the host from $REMOTE regardless of --repo, which
        # silently targeted the wrong GitHub server whenever the two named
        # different hosts -- exactly the #1403 failure mode.) Honor an
        # already-exported GH_HOST; otherwise fall back to the setup-mode
        # mapping, then github.com -- never to the local remote's host.
        TARGET_REPO="$REPO"
        TARGET_HOST=""
        if [ -n "${GH_HOST:-}" ]; then
            TARGET_HOST="$GH_HOST"
        else
            ssot="${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common/functions/gh_host.sh"
            if [ -r "$ssot" ]; then
                # shellcheck source=/dev/null
                . "$ssot"
                TARGET_HOST=$(_gh_resolve_host 2>/dev/null || true)
            fi
        fi
        [ -n "$TARGET_HOST" ] || TARGET_HOST="github.com"
    else
        git rev-parse --show-toplevel >/dev/null 2>&1 || die "not inside a git repository."
        url=$(git remote get-url "$REMOTE" 2>/dev/null) \
            || die "remote '$REMOTE' not found. Available remotes:
$(git remote -v)"

        TARGET_HOST=""
        ssot="${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common/functions/gh_host.sh"
        if [ -r "$ssot" ]; then
            # gh_host.sh is the SSOT for host/URL mapping when dotfiles is present.
            # shellcheck source=/dev/null
            . "$ssot"
            TARGET_REPO=$(_gh_parse_owner_repo_url "$url" 2>/dev/null || true)
            TARGET_HOST=$(_gh_host_from_url "$url" 2>/dev/null || _gh_resolve_host 2>/dev/null || true)
        else
            # Standalone install -- strip scheme, credentials and the .git
            # suffix, then split on the first ':' or '/'.
            u=${url%.git}; u=${u#*://}; u=${u#*@}
            TARGET_HOST=${u%%[:/]*}
            TARGET_REPO=${u#*[:/]}
        fi
        [ -n "$TARGET_HOST" ] || TARGET_HOST="github.com"
    fi

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
                raw="${2:-}"
                PACE_SECS=$(parse_duration "$raw") \
                    || die "--pace: bad duration '$raw' (use 30s / 5m / 1h30m)."
                shift 2 ;;
            --budget)
                raw="${2:-}"
                BUDGET_SECS=$(parse_duration "$raw") \
                    || die "--budget: bad duration '$raw' (use 30s / 5m / 1h30m)."
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
                    # A bare `#N` / `N` names no kind. `gh issue view/edit`
                    # silently succeeds on a PR number too (PRs are issues
                    # under the REST API), so guessing "issue" here would
                    # write the footer onto the wrong card with no error --
                    # exactly the silent mis-target #1403 exists to prevent.
                    # Queue it and resolve against --type once the whole
                    # command line has been parsed (--type may appear after
                    # this token).
                    \#*)     n="${raw#\#}";     AMBIGUOUS+=("$n") ;;
                    *)       AMBIGUOUS+=("$raw") ;;
                esac
                shift ;;
        esac
    done

    if [ "${#AMBIGUOUS[@]}" -gt 0 ]; then
        if [ -n "$TYPE" ]; then
            for n in "${AMBIGUOUS[@]}"; do
                _add_target "$TYPE" "$n"
            done
        else
            die "ambiguous card number(s) '${AMBIGUOUS[*]}' -- prefix with issue#/pr# or pass --type."
        fi
    fi

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
    local parsed kind a b clause line listing
    parsed=$(parse_date_arg "$DATE_ARG") \
        || die "--date: unrecognized form '$DATE_ARG' (YY-MM, YYYY-MM-DD, A..B)."
    read -r kind a b <<<"$parsed"
    clause=$(build_search_clause "$kind" "$a" "$b")

    local kinds=(issue pr)
    [ -z "$TYPE" ] || kinds=("$TYPE")
    for kind in "${kinds[@]}"; do
        # A plain `... < <(gh ... || true)` process substitution would hide
        # gh's exit status from the caller entirely: a failed API call (bad
        # auth, network, malformed search clause) silently produces zero
        # lines, and the eventual "no target cards" error reads as "your
        # date genuinely matched nothing" instead of "the lookup broke".
        # Capturing into a plain variable keeps the exit status live.
        #
        # Fatal, not a per-kind warn-and-continue: unlike a single card's
        # write failing mid-loop (which the rest of this script tolerates by
        # design), a failed discovery call here would silently under-cover
        # one whole kind -- e.g. every matching Issue, with only PRs actually
        # backfilled -- and nothing about a clean-looking summary line would
        # tell the caller that half the intended scope was never even
        # enumerated. Stop and let the user fix the underlying failure
        # (auth, network, a malformed --date) and re-run.
        listing=$(gh "$kind" list --repo "$TARGET_REPO" --search "$clause" \
            --state all --limit 200 --json number --jq '.[].number' 2>&1) \
            || die "gh $kind list failed for --date $DATE_ARG: $(printf '%s' "$listing" | head -1)"
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            TARGETS+=("$kind:$line")
        done <<<"$listing"
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
    local body="$1" prefix
    M_TOKENS=$(estimate_tokens "$CARD_TITLE" "$body")
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

        # Stop check at the TOP of the iteration, in seconds (not the
        # minutes-rounded figure the final report prints), and BEFORE the
        # deferred pace sleep below: checking after it would let a card that
        # is about to be skipped anyway overshoot --budget by a full --pace
        # interval just to discover the budget was already spent.
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

        # A pace sleep is credited to the modify that earned it but deferred
        # to here -- so it still lands "after that modify" for any card but
        # the last, and simply never fires when the modify was the last
        # target in the run (the budget/limit check above already broke out,
        # or the loop is simply over). This also means a skip-only tail
        # after the final modify costs one sleep, not one per skip.
        if [ "$pending_sleep" = true ]; then
            sleep_pace "$PACE_SECS"
            pending_sleep=false
            # The sleep itself can push elapsed past --budget. Re-check
            # right away rather than only at the top of the NEXT iteration:
            # without this, one more full modify (fetch + gh edit) would
            # slip through on top of the sleep's own overshoot before the
            # budget is ever re-read. This bounds the overshoot to at most
            # one --pace interval -- the sleep in flight is not interrupted
            # mid-way, only the work that would follow it. No `--dry-run`
            # guard needed here: every dry-run branch above `continue`s
            # before pending_sleep is ever set to true, so this can't run
            # in dry-run mode in the first place.
            if check_budget "$(( $(date +%s) - START_TS ))" "$BUDGET_SECS"; then
                stop_reason="--budget ($(format_duration "$BUDGET_SECS"))"
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
            compute_metrics "$(strip_footer "$CARD_BODY")"
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
        compute_metrics "$CARD_BODY"
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
            "$([ "$PACE_SECS" -gt 0 ] && format_duration "$PACE_SECS" || echo unset)" \
            "$([ "$BUDGET_SECS" -gt 0 ] && format_duration "$BUDGET_SECS" || echo unset)" \
            "${LIMIT:-unset}"
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
    _ok 'parse_date_arg feb30 single (regression: regex-shaped is not calendar-valid)' \
        "$(parse_date_arg 2024-02-30 || echo rejected)" 'rejected'
    _ok 'parse_date_arg feb30 range-start' \
        "$(parse_date_arg 2024-02-30..2024-03-05 || echo rejected)" 'rejected'
    _ok 'parse_date_arg feb30 range-end' \
        "$(parse_date_arg 2024-02-25..2024-02-30 || echo rejected)" 'rejected'
    _ok 'parse_date_arg apr31 (30-day month)' \
        "$(parse_date_arg 2024-04-31 || echo rejected)" 'rejected'
    _ok 'parse_date_arg feb29 leap year (real date, must pass)' \
        "$(parse_date_arg 2024-02-29)" 'single 2024-02-29'
    _ok 'parse_date_arg feb29 non-leap year (regression)' \
        "$(parse_date_arg 2026-02-29 || echo rejected)" 'rejected'

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

    # --- integration regressions -------------------------------------------
    # Everything above is a pure-function check that never calls `gh`,
    # `sleep`, or the clock. That gap is exactly how the fetch_card subshell
    # bug, the trailing/overshooting --pace sleep, and the silent date-filter
    # list failure all shipped undetected -- each one only exists in the
    # control flow of run() / build_targets_from_date(), never in a function
    # small enough for the assertions above to reach. Shadowing `gh`,
    # `sleep`, and `date` as plain bash functions (name lookup finds a
    # function before PATH) exercises that control flow with zero network
    # access and zero real waiting: `date` reads a fake monotonic counter
    # that only `sleep` advances, so "wall-clock" time is deterministic and
    # instant.
    gh() {
        local sub="$2" n
        case "$sub" in
            view) n="$3"; printf 'fix: title #%s\x1fSome body #%s\x1e' "$n" "$n" ;;
            edit) : ;;
            list) [ "${_FAKE_GH_LIST_FAILS:-0}" = 0 ] || { printf 'GraphQL: fake failure\n' >&2; return 1; } ;;
            *) return 1 ;;
        esac
    }
    _fake_clock=0
    date() { [ "${1:-}" = "+%s" ] && printf '%s\n' "$_fake_clock" || command date "$@"; }
    _fake_sleep_calls=0
    sleep() { _fake_sleep_calls=$((_fake_sleep_calls + 1)); _fake_clock=$((_fake_clock + ${1:-0})); }

    TARGET_REPO="fake/repo"
    CARD_TITLE=""; CARD_BODY=""
    fetch_card issue 42
    _ok 'fetch_card propagates CARD_TITLE (regression: was called via $(...), a subshell)' \
        "$CARD_TITLE" 'fix: title #42'
    _ok 'fetch_card propagates CARD_BODY (regression: was called via $(...), a subshell)' \
        "$CARD_BODY" 'Some body #42'

    # run() is called via `run > "$_run_tmp"`, never `out=$(run)`: the same
    # command-substitution subshell that ate fetch_card's globals would also
    # run() this eat _fake_sleep_calls / _fake_clock, since sleep() mutates
    # them as a side effect the assertions below depend on.
    _run_tmp=$(mktemp)

    TARGETS=(issue:1 issue:2 issue:3)
    TYPE=""; FORCE=false; DRY_RUN=false; LIMIT=""; BUDGET_SECS=0; PACE_SECS=5
    START_TS=0; _fake_clock=0
    run > "$_run_tmp"
    _ok 'run() paces exactly N-1 sleeps for N writes (never after the last card)' \
        "$_fake_sleep_calls" '2'
    _ok 'run() wrote all 3 cards end to end (fetch_card + pacing together)' \
        "$(grep -c '^\[OK\] added #[123] fix: title #[123]$' "$_run_tmp")" '3'

    TARGETS=(issue:1 issue:2 issue:3 issue:4)
    BUDGET_SECS=1; PACE_SECS=2; LIMIT=""; START_TS=0; _fake_clock=0
    run > "$_run_tmp"
    _ok 'run() re-checks --budget right after the deferred sleep (regression: one extra modify used to slip through)' \
        "$(grep -c '^\[OK\]' "$_run_tmp")" '1'

    TARGETS=(issue:1 issue:2)
    BUDGET_SECS=0; PACE_SECS=0; LIMIT=1; START_TS=0; _fake_clock=0
    run > "$_run_tmp"
    _ok 'run() --limit stops after N modified cards, not N+1' \
        "$(grep -c '^\[OK\]' "$_run_tmp")" '1'
    rm -f "$_run_tmp"

    if ( _FAKE_GH_LIST_FAILS=1 DATE_ARG=26-04 TYPE=issue TARGET_REPO=fake/repo \
             build_targets_from_date ) >/dev/null 2>&1; then
        rc=0
    else
        rc=$?
    fi
    _ok 'build_targets_from_date dies loudly on a failed gh list (regression: was a silent zero-match)' \
        "$rc" '1'

    unset -f gh sleep date

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
