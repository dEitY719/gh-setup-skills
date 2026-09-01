#!/usr/bin/env bash

set -euo pipefail

# -----------------------------------------------------------------------------
# gh-setup:docs-bootstrap — scaffold a kind-split docs/ tree in an (empty) repo.
#
# Creates the 7-folder "folder = document kind, feature = filename" structure,
# drops a .gitkeep into every leaf directory so git tracks the empty folders,
# and writes a single docs/README.md describing the policy.
#
# Self-contained except for the docs/README.md body, which is read from the
# sibling references/docs-readme-template.md (single SSOT for the policy text).
# -----------------------------------------------------------------------------

# ─── Minimal, color-aware logging (no external UX lib — copy-paste safe) ──────
if [ -n "${NO_COLOR:-}" ] || [ "${TERM:-}" = "dumb" ] || ! command -v tput >/dev/null 2>&1; then
    C_RESET="" C_OK="" C_WARN="" C_ERR="" C_INFO="" C_MUTE=""
else
    C_RESET="$(tput sgr0 2>/dev/null || echo '')"
    C_OK="$(tput setaf 2 2>/dev/null || echo '')"
    C_WARN="$(tput setaf 3 2>/dev/null || echo '')"
    C_ERR="$(tput setaf 1 2>/dev/null || echo '')"
    C_INFO="$(tput setaf 6 2>/dev/null || echo '')"
    C_MUTE="$(tput setaf 8 2>/dev/null || echo '')"
fi

log_ok() { printf '%s[OK]%s %s\n' "$C_OK" "$C_RESET" "$1"; }
log_info() { printf '%s[INFO]%s %s\n' "$C_INFO" "$C_RESET" "$1"; }
log_warn() { printf '%s[WARN]%s %s\n' "$C_WARN" "$C_RESET" "$1" >&2; }
log_err() { printf '%s[FAIL]%s %s\n' "$C_ERR" "$C_RESET" "$1" >&2; }
log_plan() { printf '  %s%s%s %s\n' "$C_MUTE" "$1" "$C_RESET" "$2"; }

die() {
    log_err "$1"
    exit 1
}

# ─── Layout SSOT ──────────────────────────────────────────────────────────────
# Leaf directories that each receive a .gitkeep. architecture/ is a parent of
# system/ and features/, so it is intentionally absent (its leaves cover it).
LEAF_DIRS=(
    adr
    product
    design
    architecture/system
    architecture/features
    testing
    guides
    public
)

README_NAME="README.md"

# ─── Argument parsing ─────────────────────────────────────────────────────────
TARGET="."
MODE="dry-run" # dry-run | check | apply | help
FORCE=false

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/../references/docs-readme-template.md"

print_usage() {
    cat <<'EOF'
gh-setup:docs-bootstrap — scaffold a kind-split docs/ tree.

Usage:
  bash scaffold.sh [path] [--dry-run|--check|--apply] [--force] [-h|--help]

Modes (priority: --help > --check > --apply > --dry-run):
  --dry-run   (default) Print the creation plan; write nothing.
  --check     Read-only audit — report whether docs/ already conforms.
              Exit 0 if complete, non-zero if anything is missing.
  --apply     Create the directories, .gitkeep files, and docs/README.md.
  --force     With --apply, overwrite an existing docs/README.md.
  -h|--help   Show this help and exit.

Arguments:
  path        Target repo root (default: current directory). docs/ is
              created under it.
EOF
}

parse_args() {
    local saw_help=false saw_check=false saw_apply=false saw_target=false
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -h | --help | help)
            saw_help=true
            shift
            ;;
        --check)
            saw_check=true
            shift
            ;;
        --apply)
            saw_apply=true
            shift
            ;;
        --dry-run)
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        -*)
            die "Unknown option: $1 (try --help)"
            ;;
        *)
            # Reject empty / duplicate target paths — an empty TARGET would
            # resolve docs_root() to "/docs" (system root) and risk writing
            # there (gemini PR #1030 review).
            if $saw_target; then
                die "Multiple target paths given: '$TARGET' and '$1' (only one allowed)"
            fi
            [ -n "$1" ] || die "Target path cannot be empty"
            TARGET="$1"
            saw_target=true
            shift
            ;;
        esac
    done

    # Mode priority: help > check > apply > dry-run.
    if $saw_help; then
        MODE="help"
    elif $saw_check; then
        MODE="check"
        if $saw_apply; then
            log_warn "--check overrides --apply (read-only audit wins)"
        fi
    elif $saw_apply; then
        MODE="apply"
    else
        MODE="dry-run"
    fi
}

# ─── Helpers ──────────────────────────────────────────────────────────────────
docs_root() { printf '%s/docs' "${TARGET%/}"; }

render_readme() {
    [ -r "$TEMPLATE_FILE" ] || die "README template not found: $TEMPLATE_FILE"
    cat "$TEMPLATE_FILE"
}

# ─── Modes ──────────────────────────────────────────────────────────────────-─
do_check() {
    local docs missing=0 d keep readme
    docs="$(docs_root)"

    log_info "Auditing ${docs}/ for the kind-split layout"
    for d in "${LEAF_DIRS[@]}"; do
        if [ -d "${docs}/${d}" ]; then
            log_plan "[ok]  " "${d}/"
        else
            log_plan "[miss]" "${d}/  (directory absent)"
            missing=$((missing + 1))
        fi
        keep="${docs}/${d}/.gitkeep"
        if [ ! -f "$keep" ]; then
            log_plan "[miss]" "${d}/.gitkeep"
            missing=$((missing + 1))
        fi
    done

    readme="${docs}/${README_NAME}"
    if [ -f "$readme" ]; then
        log_plan "[ok]  " "${README_NAME}"
    else
        log_plan "[miss]" "${README_NAME}"
        missing=$((missing + 1))
    fi

    if [ "$missing" -eq 0 ]; then
        log_ok "docs/ conforms to the kind-split layout (8 leaves + README)."
        return 0
    fi
    log_err "docs/ is missing ${missing} item(s). Run with --apply to scaffold."
    return 1
}

do_plan_or_apply() {
    local docs d keep readme apply="$1"
    docs="$(docs_root)"

    if $apply; then
        log_info "Scaffolding ${docs}/ (kind-split layout)"
    else
        log_info "[dry-run] Plan for ${docs}/ — nothing will be written"
    fi

    for d in "${LEAF_DIRS[@]}"; do
        keep="${docs}/${d}/.gitkeep"
        if [ -f "$keep" ]; then
            log_plan "skip  " "${d}/.gitkeep (exists)"
            continue
        fi
        if $apply; then
            mkdir -p "${docs}/${d}" || die "mkdir failed: ${docs}/${d}"
            : >"$keep" || die "write failed: $keep"
            log_plan "create" "${d}/.gitkeep"
        else
            log_plan "create" "${d}/ + .gitkeep"
        fi
    done

    readme="${docs}/${README_NAME}"
    if [ -f "$readme" ] && ! $FORCE; then
        log_plan "skip  " "${README_NAME} (exists — use --force to overwrite)"
    elif $apply; then
        mkdir -p "$docs" || die "mkdir failed: $docs"
        render_readme >"$readme" || die "write failed: $readme"
        log_plan "create" "${README_NAME}"
    else
        log_plan "create" "${README_NAME}"
    fi

    if $apply; then
        log_ok "docs/ scaffolded. Empty folders are tracked via .gitkeep."
    else
        log_ok "Dry-run complete. Re-run with --apply to write."
    fi
}

main() {
    parse_args "$@"
    case "$MODE" in
    help) print_usage ;;
    check) do_check ;;
    apply) do_plan_or_apply true ;;
    dry-run) do_plan_or_apply false ;;
    esac
}

main "$@"
