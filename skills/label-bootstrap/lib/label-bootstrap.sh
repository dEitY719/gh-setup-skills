#!/bin/bash

set -euo pipefail

# -----------------------------------------------------------------------------
# gh-setup:label-bootstrap — sync a target repo's GitHub labels to the dotfiles SSOT.
#
# SSOT feed: references/gh-labels.md, co-located with this script (plain-feed
# blocks). This script parses that file directly — it holds no second
# hardcoded copy of the label set.
#
# Behavior (see references/gh-labels.md for the authoritative spec):
#   1. Alias renames first  — PATCH old -> new_name (preserves issue/PR links).
#   2. SSOT 10 + pipeline    — PATCH if exists (force color/description sync),
#      apply                   POST if missing. The `pipeline|`-prefixed feed
#                              (dEitY719/dotfiles#1564) joins this loop with its prefix stripped.
#   3. Prune (only --prune)  — DELETE labels outside SSOT ∪ pipeline ∪
#                              alias-targets ∪ allowlist, computed AFTER
#                              renames.
#
# --dry-run makes ZERO mutating gh api calls (no POST/PATCH/DELETE).
# --prune defaults OFF; without it no label is ever deleted.
# Per-label API failures warn on stderr and continue (never abort the run).
# -----------------------------------------------------------------------------

REPO=""
DRY_RUN=false
PRUNE=false

# Prune allowlist: GitHub default labels always preserved (SSOT).
# Newline-separated — entries like "good first issue" contain spaces.
ALLOWLIST=$'enhancement\nduplicate\ngood first issue\nhelp wanted\ninvalid\nquestion\nwontfix'

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

warn() { printf 'warning: %s\n' "$1" >&2; }

print_help() {
    cat <<'EOF'
gh-setup:label-bootstrap — sync a repo's GitHub labels to the dotfiles SSOT.

Usage:
  bash skills/label-bootstrap/lib/label-bootstrap.sh [options]

Options:
  --repo <owner/repo>  Target repo (default: gh repo view of current repo).
  --dry-run            Print the plan; make no API mutations.
  --prune              DELETE non-SSOT custom labels (default: off).
  -h, --help, help     Show this help.

Full spec: references/gh-labels.md
EOF
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --repo)
            [ "${2-}" ] || die "--repo requires a value"
            REPO="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --prune)
            PRUNE=true
            shift
            ;;
        -h | --help | help)
            print_help
            exit 0
            ;;
        *)
            die "Unknown option: $1"
            ;;
        esac
    done
}

# Resolve the SSOT feed from this script's own (symlink-resolved) location so
# it is found regardless of cwd or the entry-level skill symlink
# (~/.claude*/skills/<name> -> dotfiles/claude/skills/<name>). references/ is
# always a sibling of lib/, so this works standalone even if the skill
# directory is copied out of the dotfiles repo entirely.
resolve_ssot_file() {
    if [ -n "${GH_LABELS_SSOT:-}" ]; then
        printf '%s' "$GH_LABELS_SSOT"
        return 0
    fi
    local script_dir
    script_dir="$(cd "$(dirname "$0")" && pwd -P)"
    printf '%s' "${script_dir}/../references/gh-labels.md"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required. Install it first."
}

resolve_repo() {
    [ -n "$REPO" ] && return 0
    REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
    [ -n "$REPO" ] || die "--repo omitted and 'gh repo view' failed (run inside a GitHub-linked repo or pass --repo)."
}

# gh api wrapper honoring --dry-run. Prints the planned action either way.
# Returns the real gh api exit status (0 success, 1 failure) so callers that
# need to know (e.g. the rename step) can react; dry-run always reports 0.
# Usage: api_mutate "<plan line>" <gh api args...>
api_mutate() {
    local plan="$1"
    shift
    if $DRY_RUN; then
        printf '[dry-run] %s\n' "$plan"
        return 0
    fi
    if gh api "$@" >/dev/null 2>&1; then
        printf '%s\n' "$plan"
        return 0
    fi
    warn "$plan FAILED (permission / rate-limit / API error) — skipped"
    return 1
}

# Membership test against a newline-separated set on stdin-free vars.
in_set() {
    # $1 = needle, $2 = newline-separated haystack
    printf '%s\n' "$2" | grep -Fxq "$1"
}

main() {
    parse_args "$@"
    require_command gh

    local ssot_file
    ssot_file="$(resolve_ssot_file)"
    [ -r "$ssot_file" ] || die "SSOT feed not readable: $ssot_file"

    resolve_repo

    # --- Parse SSOT plain feeds -------------------------------------------
    # 10-label feed:  name|<6hex>|description
    # alias feed:     old|new     (two lowercase words)
    # pipeline feed:  pipeline|name|<6hex>|description        (dEitY719/dotfiles#1564)
    # tr -d '\r' + leading-whitespace tolerance guard against CRLF checkouts
    # and incidental fence indentation (gemini-code-assist review, PR dEitY719/dotfiles#1229).
    #
    # The three regexes are mutually exclusive by construction: a pipeline row
    # cannot match the 10-label pattern (what follows its first `|` is a label
    # name, not 6 hex digits) and cannot match the alias pattern (it carries
    # hyphens and three separators). So the prefix is a real namespace, not a
    # convention the parser hopes holds.
    local feed alias_feed pipeline_feed ssot_content
    ssot_content="$(tr -d '\r' <"$ssot_file")"
    feed="$(printf '%s\n' "$ssot_content" | grep -E '^[[:space:]]*[A-Za-z][A-Za-z0-9]*\|[0-9a-fA-F]{6}\|' || true)"
    alias_feed="$(printf '%s\n' "$ssot_content" | grep -E '^[[:space:]]*[a-z]+\|[a-z]+$' || true)"
    [ -n "$feed" ] || die "no label feed found in $ssot_file"

    # Pipeline-state labels (review-blocked / review-passed): provisioned by
    # this script but deliberately NOT part of the 10-label SSOT — they are
    # not an issue-classification axis and have no aliases. The prefix is
    # stripped here so they join the ordinary POST/PATCH loop below, and
    # because they land in `feed` they are also in the `--prune` keep set.
    # Deleting them would leave `gh-verify:review-all` unable to issue a verdict
    # (`_gh_pr_edit_safe_label` rc 3, dEitY719/dotfiles#326) and the merge train reading every
    # PR as unverified — the whole pipeline stops (dEitY719/dotfiles#1564).
    pipeline_feed="$(printf '%s\n' "$ssot_content" \
        | grep -E '^[[:space:]]*pipeline\|[A-Za-z][A-Za-z0-9_-]*\|[0-9a-fA-F]{6}\|' \
        | sed -e 's/^[[:space:]]*//' -e 's/^pipeline|//' || true)"
    if [ -n "$pipeline_feed" ]; then
        feed="$(printf '%s\n%s' "$feed" "$pipeline_feed")"
    fi

    # SSOT label names (for keep-set membership).
    local ssot_names
    ssot_names="$(printf '%s\n' "$feed" | cut -d'|' -f1)"

    # Look up SSOT "color|description" by name in one scan (not two).
    ssot_row() { printf '%s\n' "$feed" | awk -F'|' -v n="$1" '$1==n{sub(/^[^|]*\|/,""); print; exit}'; }

    # --- Fetch existing labels --------------------------------------------
    local existing
    if ! existing="$(gh api "repos/${REPO}/labels?per_page=100" --jq '.[].name' 2>/dev/null)"; then
        die "could not list labels on ${REPO}. Check network connectivity, repo permissions, or gh auth."
    fi

    local mode=""
    $DRY_RUN && mode=" (dry-run)"
    printf 'Target repo: %s%s\n' "$REPO" "$mode"

    # effective = existing with aliases applied (old removed, new added).
    local effective="$existing"
    local renamed_targets="" # new names that were renamed this run

    # Counters for the closing Summary/verdict line.
    local n_renamed=0 n_created=0 n_synced=0 n_pruned=0 n_failed=0

    # --- 1. Alias renames --------------------------------------------------
    local old new color desc
    while IFS='|' read -r old new; do
        [ -z "$old" ] && continue
        if in_set "$old" "$existing"; then
            IFS='|' read -r color desc <<<"$(ssot_row "$new")"
            # Only bookkeep the rename as done when the API call actually
            # succeeded — otherwise step 2 below must still sync '$new'
            # directly instead of silently skipping it (codex review, PR
            # dEitY719/dotfiles#1229: a failed rename must not mask an out-of-sync label).
            if api_mutate "rename label '${old}' -> '${new}' (sync color/desc)" \
                "repos/${REPO}/labels/${old}" -X PATCH \
                -f "new_name=${new}" -f "color=${color}" -f "description=${desc}"; then
                # Reflect in effective set: drop old, add new.
                effective="$(printf '%s\n' "$effective" | grep -Fxv "$old" || true)"
                in_set "$new" "$effective" || effective="$(printf '%s\n%s' "$effective" "$new")"
                renamed_targets="${renamed_targets}${new}"$'\n'
                n_renamed=$((n_renamed + 1))
            else
                n_failed=$((n_failed + 1))
            fi
        fi
    done <<<"$alias_feed"

    # --- 2. SSOT 10 + pipeline apply ---------------------------------------
    local name
    while IFS='|' read -r name color desc; do
        [ -z "$name" ] && continue
        if in_set "$name" "$renamed_targets"; then
            continue # already synced by the rename above
        fi
        if in_set "$name" "$effective"; then
            if api_mutate "PATCH label '${name}' (color=${color})" \
                "repos/${REPO}/labels/${name}" -X PATCH \
                -f "new_name=${name}" -f "color=${color}" -f "description=${desc}"; then
                n_synced=$((n_synced + 1))
            else
                n_failed=$((n_failed + 1))
            fi
        else
            if api_mutate "POST label '${name}' (color=${color})" \
                "repos/${REPO}/labels" -X POST \
                -f "name=${name}" -f "color=${color}" -f "description=${desc}"; then
                n_created=$((n_created + 1))
            else
                n_failed=$((n_failed + 1))
            fi
            effective="$(printf '%s\n%s' "$effective" "$name")"
        fi
    done <<<"$feed"

    # --- 3. Prune (opt-in only) -------------------------------------------
    if $PRUNE; then
        # keep = SSOT names (pipeline labels included — they were merged into
        #        `feed` above, so `ssot_names` already carries them) ∪ alias
        #        new names ∪ allowlist
        local keep alias_targets allow_nl
        alias_targets="$(printf '%s\n' "$alias_feed" | cut -d'|' -f2)"
        allow_nl="$ALLOWLIST"
        keep="$(printf '%s\n%s\n%s\n' "$ssot_names" "$alias_targets" "$allow_nl" | grep -v '^$' | sort -u)"

        local label
        while IFS= read -r label; do
            [ -z "$label" ] && continue
            if in_set "$label" "$keep"; then
                continue
            fi
            if api_mutate "DELETE label '${label}' (prune: not in SSOT/alias/allowlist)" \
                "repos/${REPO}/labels/${label}" -X DELETE; then
                n_pruned=$((n_pruned + 1))
            else
                n_failed=$((n_failed + 1))
            fi
        done <<<"$effective"
    else
        printf 'Prune skipped (--prune not set) — no labels deleted.\n'
    fi

    # --- Verdict -----------------------------------------------------------
    # A run where every mutation failed (e.g. a read-only token) must not
    # look identical, on stdout, to a fully successful one.
    printf 'Summary: renamed=%d created=%d synced=%d pruned=%d failed=%d\n' \
        "$n_renamed" "$n_created" "$n_synced" "$n_pruned" "$n_failed"
    if [ "$n_failed" -gt 0 ]; then
        printf '[FAIL] Label sync incomplete for %s%s (%d failure(s))\n' "$REPO" "$mode" "$n_failed"
        exit 1
    fi
    printf '[OK] Labels synced to SSOT for %s%s\n' "$REPO" "$mode"
}

main "$@"
