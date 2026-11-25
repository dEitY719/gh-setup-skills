#!/bin/sh

set -eu

# -----------------------------------------------------------------------------
# gh-setup:adr-bootstrap -- an ADR management system for docs/adr/.
#
#   scaffold   write docs/adr/README.md (rules) + docs/adr/NNNN-template.md
#   new        number the next ADR (max existing + 1) and render the template
#   supersede  new ADR + one "superseded" line in the old ADR's status section
#   --check    read-only hygiene audit: duplicate numbers, bad file names,
#              missing status / Accepted, broken supersede references
#
# Dry-run is the default for every writing mode; only --apply writes. Template
# and README bodies are read from ../references/ (single SSOT). POSIX sh.
# -----------------------------------------------------------------------------

log_ok() { printf '[OK] %s\n' "$1"; }
log_info() { printf '[INFO] %s\n' "$1"; }
log_err() { printf '[FAIL] %s\n' "$1" >&2; }
log_plan() { printf '  %s %s\n' "$1" "$2"; }
die() {
    log_err "$1"
    exit 1
}

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
SELF="$SCRIPT_DIR/$(basename -- "$0")"
REF_DIR="$SCRIPT_DIR/../references"
TODAY=${ADR_DATE:-$(date +%Y-%m-%d)}

print_usage() {
    cat <<'EOF'
gh-setup:adr-bootstrap -- ADR scaffold / new / supersede / check.

Usage:
  adr.sh [path] [scaffold] [--apply] [--force] [--lang ko|en]
  adr.sh [path] new "<title>" [--slug <kebab>] [--apply] [--lang ko|en]
  adr.sh [path] supersede <number|path> "<title>" [--slug <kebab>] [--apply] [--lang ko|en]
  adr.sh [path] --check
  adr.sh --self-test | -h | --help

  path      repo root (default .); ADRs live in <path>/docs/adr/
  --apply   write (default is a dry-run that prints every planned file in full)
  --force   scaffold only: overwrite an existing README.md / NNNN-template.md
  --lang    template language: ko (default, declarative-title form) | en (MADR)
  --slug    English kebab-case file slug; required when the title is not ASCII
  --check   read-only audit, exit 0 clean / 1 findings
EOF
}

# --- Arguments ----------------------------------------------------------------
TARGET="."
MODE=""
CHECK=false
APPLY=false
FORCE=false
ADR_LANG="ko"
LANG_SET=false
SLUG=""
TITLE=""
OLD_REF=""
SAW_TARGET=false

while [ "$#" -gt 0 ]; do
    case "$1" in
    -h | --help) MODE="help" ;;
    --self-test) MODE="self-test" ;;
    --check) CHECK=true ;;
    --apply) APPLY=true ;;
    --dry-run) ;;
    --force) FORCE=true ;;
    --lang)
        [ "$#" -ge 2 ] || die "--lang needs ko or en"
        shift
        ADR_LANG="$1"
        LANG_SET=true
        ;;
    --lang=*)
        ADR_LANG="${1#--lang=}"
        LANG_SET=true
        ;;
    --slug)
        [ "$#" -ge 2 ] || die "--slug needs a value"
        shift
        SLUG="$1"
        ;;
    --slug=*) SLUG="${1#--slug=}" ;;
    -*) die "Unknown option: $1 (try --help)" ;;
    *)
        # bare "help" is a mode only as arg #1, so a title or ref "help" stays data
        if [ -z "$MODE" ] && ! $SAW_TARGET && [ "$1" = help ]; then
            MODE="help"
        elif [ -z "$MODE" ] && { [ "$1" = scaffold ] || [ "$1" = new ] || [ "$1" = supersede ]; }; then
            MODE="$1"
        elif [ "$MODE" = new ] && [ -z "$TITLE" ]; then
            TITLE="$1"
        elif [ "$MODE" = supersede ] && [ -z "$OLD_REF" ]; then
            OLD_REF="$1"
        elif [ "$MODE" = supersede ] && [ -z "$TITLE" ]; then
            TITLE="$1"
        elif [ -z "$MODE" ] && ! $SAW_TARGET; then
            [ -n "$1" ] || die "Target path cannot be empty"
            TARGET="$1"
            SAW_TARGET=true
        else
            die "Unexpected argument: $1 (try --help)"
        fi
        ;;
    esac
    shift
done

case "$ADR_LANG" in ko | en) ;; *) die "--lang must be ko or en, got: $ADR_LANG" ;; esac
if [ "$MODE" != help ] && [ "$MODE" != self-test ]; then
    if $CHECK; then
        # --check is read-only; silently dropping a write request would surprise the user.
        { [ -z "$MODE" ] && ! $APPLY; } || die "--check is read-only: do not combine it with a mode or --apply"
        MODE="check"
    fi
    [ -n "$MODE" ] || MODE="scaffold"
fi

ADR_DIR="${TARGET%/}/docs/adr"

# --- Helpers ------------------------------------------------------------------
strip_zeros() {
    _z=$(printf '%s' "$1" | sed 's/^0*//')
    printf '%s' "${_z:-0}"
}

# Highest NNNN- prefix + 1. Non-NNNN files never count (they are --check findings).
next_number() {
    _max=0
    for _f in "$ADR_DIR"/[0-9][0-9][0-9][0-9]-?*.md; do
        [ -f "$_f" ] || continue
        _n=$(basename -- "$_f")
        _n=$(strip_zeros "${_n%%-*}")
        if [ "$_n" -gt "$_max" ]; then _max=$_n; fi
    done
    [ "$_max" -lt 9999 ] || die "ADR numbers are exhausted at 9999 (NNNN- is four digits)"
    printf '%04d' $((_max + 1))
}

resolve_slug() {
    if [ -n "$SLUG" ]; then
        printf '%s' "$SLUG" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$' ||
            die "--slug must be lowercase kebab-case ([a-z0-9-]): $SLUG"
    elif printf '%s' "$TITLE" | LC_ALL=C grep -q '[^ -~]'; then
        die "Title is not ASCII: propose an English kebab-case slug and pass --slug <slug> (file names stay English; the title stays in the body)"
    else
        SLUG=$(printf '%s' "$TITLE" | LC_ALL=C tr 'A-Z' 'a-z' |
            LC_ALL=C sed -e 's/[^a-z0-9][^a-z0-9]*/-/g' -e 's/^-//' -e 's/-$//')
        [ -n "$SLUG" ] || die "Cannot derive a slug from the title; pass --slug <slug>"
    fi
}

# The repo's own docs/adr/NNNN-template.md wins unless --lang was given, so a
# customised template is honoured and its language (## Status = en) carries over.
require_template() {
    TEMPLATE="$REF_DIR/template-$ADR_LANG.md"
    if ! $LANG_SET && [ -r "$ADR_DIR/NNNN-template.md" ]; then
        TEMPLATE="$ADR_DIR/NNNN-template.md"
        if grep -q '^## Status' "$TEMPLATE"; then ADR_LANG=en; else ADR_LANG=ko; fi
    fi
    [ -r "$TEMPLATE" ] || die "template not found: $TEMPLATE"
}

# Template with line 1 -> "# <title>" and the placeholder status line -> $2.
render() {
    ADR_T="$1" ADR_S="$2" awk '
        NR == 1 && /^# / { print "# " ENVIRON["ADR_T"]; next }
        !done && /^Accepted — YYYY-MM-DD/ { print ENVIRON["ADR_S"]; done = 1; next }
        { print }' "$TEMPLATE"
}

# stdin -> file on --apply; otherwise print the full planned content.
emit() {
    log_plan "${3:-create}" "$2"
    if $APPLY; then
        cat >"$1" || die "write failed: $1"
    else
        printf -- '----- %s -----\n' "$2"
        cat
        printf -- '----- end %s -----\n' "$2"
    fi
}

# One heading pattern for both readers, so they cannot drift apart.
STATUS_RE='^## (상태|Status)[ \t\r]*$'

status_heading_line() {
    awk -v re="$STATUS_RE" '$0 ~ re { print NR; exit }' "$1"
}

status_section() {
    awk -v re="$STATUS_RE" 'f && /^## / { exit } f { print } $0 ~ re { f = 1 }' "$1"
}

finish() {
    if $APPLY; then
        log_ok "$1"
    else
        log_ok "Dry-run complete. Re-run with --apply to write."
    fi
}

# --- Modes --------------------------------------------------------------------
do_scaffold() {
    [ -d "$TARGET" ] || die "Not a directory: $TARGET"
    if $APPLY; then log_info "Scaffolding $ADR_DIR/"; else log_info "[dry-run] Plan for $ADR_DIR/ -- nothing will be written"; fi
    if [ ! -d "$ADR_DIR" ]; then
        if $APPLY; then mkdir -p "$ADR_DIR" || die "mkdir failed: $ADR_DIR"; fi
        log_plan "create" "docs/adr/"
    fi
    for _pair in "README.md:readme-$ADR_LANG.md" "NNNN-template.md:template-$ADR_LANG.md"; do
        _dst=${_pair%%:*}
        _src="$REF_DIR/${_pair#*:}"
        [ -r "$_src" ] || die "reference not found: $_src"
        _verb=create
        if [ -e "$ADR_DIR/$_dst" ]; then
            if ! $FORCE; then
                log_plan "skip  " "docs/adr/$_dst (exists -- use --force to overwrite)"
                continue
            fi
            _verb=overwrite
        fi
        emit "$ADR_DIR/$_dst" "docs/adr/$_dst" "$_verb" <"$_src"
    done
    finish "docs/adr/ is ready. Next: git add docs/adr && git commit -m \"docs(adr): bootstrap ADR records\""
}

prepare_new() {
    [ -n "$TITLE" ] || die "$1 needs a title -- write the decision as one declarative sentence (제목을 선언문 한 문장으로)"
    [ -d "$TARGET" ] || die "Not a directory: $TARGET"
    [ -d "$ADR_DIR" ] || die "$ADR_DIR not found -- run scaffold first"
    require_template
    resolve_slug
    NUM=$(next_number)
    NEW_FILE="$NUM-$SLUG.md"
    [ ! -e "$ADR_DIR/$NEW_FILE" ] || die "already exists: docs/adr/$NEW_FILE"
    log_info "Next number: $NUM (highest existing + 1), slug: $SLUG"
}

do_new() {
    prepare_new new
    render "$TITLE" "Accepted — $TODAY." | emit "$ADR_DIR/$NEW_FILE" "docs/adr/$NEW_FILE"
    finish "Created docs/adr/$NEW_FILE. Fill in the body, then commit it."
}

list_candidates() {
    printf 'Candidates in docs/adr/:\n'
    for _f in "$ADR_DIR"/[0-9][0-9][0-9][0-9]-?*.md; do
        [ -f "$_f" ] && printf '  %s\n' "$(basename -- "$_f")"
    done
    return 0
}

resolve_old() {
    OLD_FILE=""
    case "$OLD_REF" in
    *[!0-9]*)
        for _c in "$ADR_DIR/$OLD_REF" "$OLD_REF"; do
            if [ -f "$_c" ]; then
                OLD_FILE="$_c"
                break
            fi
        done
        if [ -n "$OLD_FILE" ] && [ -L "$OLD_FILE" ]; then
            die "Refusing to rewrite a symlink: $OLD_REF -- nothing written"
        fi
        if [ -n "$OLD_FILE" ] && ! basename -- "$OLD_FILE" | grep -Eq '^[0-9]{4}-.+\.md$'; then
            die "Not an NNNN-*.md ADR: $OLD_REF"
        fi
        if [ -n "$OLD_FILE" ] && [ "$(CDPATH='' cd -- "$(dirname -- "$OLD_FILE")" && pwd -P)" != "$(CDPATH='' cd -- "$ADR_DIR" && pwd -P)" ]; then
            die "Not inside $ADR_DIR: $OLD_REF -- nothing written"
        fi
        ;;
    *)
        _p=$(printf '%04d' "$(strip_zeros "$OLD_REF")")
        _hits=0
        for _f in "$ADR_DIR/$_p"-?*.md; do
            [ -f "$_f" ] || continue
            _hits=$((_hits + 1))
            OLD_FILE="$_f"
        done
        if [ -n "$OLD_FILE" ] && [ -L "$OLD_FILE" ]; then
            die "Refusing to rewrite a symlink: $OLD_FILE -- nothing written"
        fi
        if [ "$_hits" -gt 1 ]; then
            log_err "ADR number $_p is ambiguous (duplicate number) -- pass the file path instead"
            list_candidates
            exit 1
        fi
        ;;
    esac
    if [ -z "$OLD_FILE" ]; then
        log_err "ADR to supersede not found: $OLD_REF -- nothing written"
        list_candidates
        exit 1
    fi
}

do_supersede() {
    [ -n "$OLD_REF" ] || die "supersede needs <old number|path> and a new title"
    [ -d "$ADR_DIR" ] || die "$ADR_DIR not found -- run scaffold first"
    resolve_old
    _ob=$(basename -- "$OLD_FILE")
    _on=${_ob%%-*}
    _h=$(status_heading_line "$OLD_FILE")
    [ -n "$_h" ] || die "docs/adr/$_ob has no status section (## 상태 / ## Status) -- cannot record the supersession"
    if status_section "$OLD_FILE" | grep -Eq ' 로 대체됨|Superseded by '; then
        die "docs/adr/$_ob is already superseded -- supersede the newest ADR in the chain instead; nothing written"
    fi
    if $APPLY && [ ! -w "$OLD_FILE" ]; then die "docs/adr/$_ob is not writable -- nothing written"; fi
    # Without --lang and a local template, the new ADR follows the old one's language.
    if ! $LANG_SET && sed -n "${_h}p" "$OLD_FILE" | grep -q Status; then ADR_LANG=en; fi
    prepare_new supersede
    if sed -n "${_h}p" "$OLD_FILE" | grep -q Status; then
        _old_line="Superseded by $NUM — $TODAY."
    else
        _old_line="$NUM 로 대체됨 — $TODAY."
    fi
    if [ "$ADR_LANG" = en ]; then
        _st="Accepted — $TODAY. Supersedes $_on."
    else
        _st="Accepted — $TODAY. $_on 을 대체한다."
    fi
    # Insert after the last non-blank line of the status section (a CR-only line is blank).
    _at=$(awk -v h="$_h" '{ sub(/\r$/, "") } NR > h && /^## / { exit } NR > h && NF { l = NR } END { print (l ? l : h) }' "$OLD_FILE")
    _cr=$(printf '\r')
    case "$(sed -n "${_at}p" "$OLD_FILE")" in *"$_cr") _old_line="$_old_line$_cr" ;; esac

    if $APPLY; then
        # Build the old ADR's new content first, so a failure here writes nothing at all.
        _tmp="$OLD_FILE.adr-bootstrap.$$"
        _last=$(head -n "$_at" "$OLD_FILE" | tail -c 1)
        # head/tail keep every other byte, including a missing final newline
        {
            head -n "$_at" "$OLD_FILE"
            [ -z "$_last" ] || printf '\n'
            printf '%s\n' "$_old_line"
            tail -n "+$((_at + 1))" "$OLD_FILE"
        } >"$_tmp" || {
            rm -f "$_tmp"
            die "rewrite failed: $OLD_FILE -- nothing written"
        }
    fi
    render "$TITLE" "$_st" | emit "$ADR_DIR/$NEW_FILE" "docs/adr/$NEW_FILE"
    log_plan "modify" "docs/adr/$_ob (+1 line after line $_at, nothing else): $_old_line"
    if $APPLY; then
        cat "$_tmp" >"$OLD_FILE" || die "write failed: $OLD_FILE (intended content left in $_tmp)"
        rm -f "$_tmp"
    fi
    finish "Created docs/adr/$NEW_FILE and marked docs/adr/$_ob superseded."
}

do_check() {
    [ -d "$ADR_DIR" ] || die "$ADR_DIR not found -- nothing to check"
    log_info "Auditing $ADR_DIR/"
    FINDINGS=0
    finding() {
        log_plan "[warn]" "$1"
        FINDINGS=$((FINDINGS + 1))
    }

    _nums=""
    for _f in "$ADR_DIR"/[0-9][0-9][0-9][0-9]-?*.md; do
        [ -f "$_f" ] || continue
        _b=$(basename -- "$_f")
        _nums="$_nums${_b%%-*}
"
    done
    for _d in $(printf '%s' "$_nums" | sort | uniq -d); do
        finding "duplicate number $_d: $(cd "$ADR_DIR" && ls "$_d"-*.md | tr '\n' ' ')"
    done

    for _f in "$ADR_DIR"/*.md; do
        [ -f "$_f" ] || continue
        _b=$(basename -- "$_f")
        case "$_b" in README.md | NNNN-template.md) continue ;; esac
        if ! printf '%s' "$_b" | grep -Eq '^[0-9]{4}-.+\.md$'; then
            finding "file name does not match NNNN-<slug>.md (excluded from numbering): $_b"
        fi
    done

    for _f in "$ADR_DIR"/[0-9][0-9][0-9][0-9]-?*.md; do
        [ -f "$_f" ] || continue
        _b=$(basename -- "$_f")
        _sec=$(status_section "$_f")
        if [ -z "$(status_heading_line "$_f")" ]; then
            finding "no status section (## 상태 / ## Status): $_b"
        elif ! printf '%s\n' "$_sec" | grep -q 'Accepted'; then
            finding "status section has no Accepted line: $_b"
        fi
        # Both directions: old -> new ("로 대체됨" / "Superseded by") and new -> old
        # ("을 대체한다" / "Supersedes"). sed, not grep -o, to stay POSIX.
        _refs=$(printf '%s\n' "$_sec" | sed -n -E -e 's/.*([0-9]{4}) 로 대체됨.*/\1/p' -e 's/.*Superseded by ([0-9]{4}).*/\1/p' \
            -e 's/.*Supersedes ([0-9]{4}).*/\1/p' -e 's/.*([0-9]{4}) 을 대체한다.*/\1/p')
        for _r in $_refs; do
            _ok=false
            for _t in "$ADR_DIR/$_r"-*.md; do [ -f "$_t" ] && _ok=true; done
            $_ok || finding "broken supersede reference $_r (no $_r-*.md): $_b"
        done
    done

    if [ "$FINDINGS" -eq 0 ]; then
        log_ok "docs/adr/ is clean."
        return 0
    fi
    log_err "docs/adr/ has $FINDINGS finding(s)."
    return 1
}

# --- Self-test ----------------------------------------------------------------
self_test() {
    ST=$(mktemp -d "${TMPDIR:-/tmp}/adr-selftest.XXXXXX")
    trap 'rm -rf "$ST"' EXIT
    export ADR_DATE=2026-01-02
    pass=0
    ok() { pass=$((pass + 1)); }
    bad() {
        printf '[FAIL] self-test: %s\n' "$1" >&2
        exit 1
    }
    run() { sh "$SELF" "$@" >"$ST/out" 2>&1; }

    # scaffold: empty repo, docs-bootstrap shell, populated repo -- idempotent.
    mkdir -p "$ST/empty" "$ST/shell/docs/adr" "$ST/full/docs/adr"
    : >"$ST/shell/docs/adr/.gitkeep"
    printf '# A\n\n## 상태\nAccepted — 2025-01-01.\n' >"$ST/full/docs/adr/0042-a.md"
    run "$ST/empty" || bad "dry-run scaffold failed"
    [ ! -e "$ST/empty/docs" ] || bad "dry-run wrote files"
    grep -q '## 기각한 안' "$ST/out" || bad "dry-run did not print the template in full"
    ok
    for r in empty shell full; do
        run "$ST/$r" scaffold --apply || bad "scaffold --apply failed on $r"
        [ -f "$ST/$r/docs/adr/README.md" ] && [ -f "$ST/$r/docs/adr/NNNN-template.md" ] || bad "scaffold missing files on $r"
        run "$ST/$r" --apply || bad "scaffold rerun failed on $r"
        [ "$(grep -c '^  skip' "$ST/out")" -eq 2 ] && ! grep -q '^  create' "$ST/out" || bad "rerun not all-skip on $r"
        ok
    done
    [ -f "$ST/shell/docs/adr/.gitkeep" ] || bad ".gitkeep removed"
    [ -f "$ST/full/docs/adr/0042-a.md" ] || bad "existing ADR touched"
    ok

    # new: max + 1, consecutive, dry-run writes nothing.
    run "$ST/full" new "Use Postgres" || bad "dry-run new failed"
    [ ! -e "$ST/full/docs/adr/0043-use-postgres.md" ] || bad "dry-run new wrote a file"
    run "$ST/full" new "Use Postgres" --apply || bad "new --apply failed"
    run "$ST/full" new "Drop Redis" --apply || bad "second new failed"
    [ -f "$ST/full/docs/adr/0043-use-postgres.md" ] && [ -f "$ST/full/docs/adr/0044-drop-redis.md" ] || bad "numbering not 0043 -> 0044"
    head -n 1 "$ST/full/docs/adr/0043-use-postgres.md" | grep -qx '# Use Postgres' || bad "title not rendered"
    grep -qx 'Accepted — 2026-01-02.' "$ST/full/docs/adr/0043-use-postgres.md" || bad "status not rendered"
    ok
    if run "$ST/full" new "결정 제목"; then bad "non-ASCII title without --slug accepted"; fi
    run "$ST/full" new --apply "API 는 REST 를 쓴다" --slug api-uses-rest || bad "--slug failed"
    grep -qx '# API 는 REST 를 쓴다' "$ST/full/docs/adr/0045-api-uses-rest.md" || bad "Korean title not kept in body"
    if run "$ST/full" new; then bad "new without title accepted"; fi
    ok

    # --lang: ko skeleton vs MADR skeleton.
    run "$ST/full" new "English one" --lang en --apply || bad "--lang en failed"
    for h in Status Context Decision Consequences; do
        grep -q "^## $h" "$ST/full/docs/adr/0046-english-one.md" || bad "en template lacks ## $h"
    done
    for h in 상태 결정 이유 '기각한 안' 결과; do
        grep -q "^## $h" "$ST/full/docs/adr/0043-use-postgres.md" || bad "ko template lacks ## $h"
    done
    ok

    # supersede: old ADR gains exactly one line, nothing else changes.
    cp "$ST/full/docs/adr/0043-use-postgres.md" "$ST/orig"
    run "$ST/full" supersede 0043 "Use MySQL" || bad "dry-run supersede failed"
    cmp -s "$ST/orig" "$ST/full/docs/adr/0043-use-postgres.md" || bad "dry-run supersede modified the old ADR"
    run "$ST/full" supersede 43 "Use MySQL" --apply || bad "supersede --apply failed"
    grep -qx 'Accepted — 2026-01-02. 0043 을 대체한다.' "$ST/full/docs/adr/0047-use-mysql.md" || bad "new status lacks supersedes line"
    diff "$ST/orig" "$ST/full/docs/adr/0043-use-postgres.md" >"$ST/diff" || true
    [ "$(grep -c '^>' "$ST/diff")" -eq 1 ] && [ "$(grep -c '^<' "$ST/diff")" -eq 0 ] || bad "old ADR changed beyond one line"
    grep -qx '> 0047 로 대체됨 — 2026-01-02.' "$ST/diff" || bad "wrong superseded line"
    _sec=$(status_section "$ST/full/docs/adr/0043-use-postgres.md")
    printf '%s' "$_sec" | grep -q '0047 로 대체됨' || bad "superseded line not inside the status section"
    _before=$(ls "$ST/full/docs/adr" | wc -l)
    if run "$ST/full" supersede 0099 "Nope" --apply; then bad "missing supersede target accepted"; fi
    grep -q 'Candidates' "$ST/out" || bad "no candidates listed"
    [ "$(ls "$ST/full/docs/adr" | wc -l)" -eq "$_before" ] || bad "failed supersede wrote a file"
    mkdir -p "$ST/other"
    printf '# X\n\n## 상태\nAccepted — 2025-01-01.\n' >"$ST/other/0001-x.md"
    if run "$ST/full" supersede "$ST/other/0001-x.md" "Nope" --apply; then bad "supersede outside docs/adr accepted"; fi
    # no trailing newline after a later section: only the one line may change
    printf '# N\n\n## 상태\nAccepted — 2025-01-01.\n\n## 결정\nx' >"$ST/full/docs/adr/0090-n.md"
    cp "$ST/full/docs/adr/0090-n.md" "$ST/orig"
    run "$ST/full" supersede 90 "Next N" --apply || bad "supersede on no-EOL file failed"
    [ "$(tail -c 1 "$ST/full/docs/adr/0090-n.md")" = x ] || bad "supersede added a final newline"
    ok

    # --check: clean repo passes; fixture with all four defects fails on each.
    printf '# R\r\n\r\n## Status\r\nAccepted — 2025-01-01. Superseded by the 2024 plan.\r\n' >"$ST/full/docs/adr/0095-crlf.md"
    run "$ST/full" --check || bad "--check failed on a clean repo (CRLF / prose year)"
    mkdir -p "$ST/bad/docs/adr"
    printf '# A\n\n## 상태\nAccepted — 2025-01-01.\n0099 로 대체됨 — 2025-02-01.\n' >"$ST/bad/docs/adr/0002-a.md"
    printf '# B\n\n## 상태\nAccepted — 2025-01-01.\n' >"$ST/bad/docs/adr/0002-b.md"
    printf '# C\n\n## 결정\nx\n' >"$ST/bad/docs/adr/0003-c.md"
    printf '# D\n\n## Status\nProposed\n' >"$ST/bad/docs/adr/0004-d.md"
    printf '# notes\n' >"$ST/bad/docs/adr/notes.md"
    cp -R "$ST/bad" "$ST/bad.orig"
    if run "$ST/bad" --check; then bad "--check passed a broken fixture"; fi
    for want in 'duplicate number 0002' 'does not match NNNN' 'no status section' 'no Accepted line' 'broken supersede reference 0099'; do
        grep -q "$want" "$ST/out" || bad "--check missed: $want"
    done
    diff -r "$ST/bad" "$ST/bad.orig" >/dev/null || bad "--check modified files"
    run "$ST/bad" new "Next one" --apply || bad "new beside non-NNNN file failed"
    [ -f "$ST/bad/docs/adr/0005-next-one.md" ] || bad "non-NNNN file affected numbering"
    ok

    # review fixes: local template, already-superseded, symlink, CRLF, cap, forward refs.
    mkdir -p "$ST/loc/docs/adr"
    printf '# T\n\n## Status\nAccepted — YYYY-MM-DD. (owner)\n\n## Team section\n' >"$ST/loc/docs/adr/NNNN-template.md"
    run "$ST/loc" new "Local one" --apply || bad "new with local template failed"
    grep -q '^## Team section' "$ST/loc/docs/adr/0001-local-one.md" || bad "local NNNN-template.md ignored"
    grep -qx 'Accepted — 2026-01-02.' "$ST/loc/docs/adr/0001-local-one.md" || bad "local template status not rendered"
    run "$ST/loc" supersede 1 "Local two" --apply || bad "supersede (en via local template) failed"
    grep -qx 'Accepted — 2026-01-02. Supersedes 0001.' "$ST/loc/docs/adr/0002-local-two.md" || bad "en supersede line not used"
    cp "$ST/loc/docs/adr/0001-local-one.md" "$ST/orig"
    if run "$ST/loc" supersede 1 "Again" --apply; then bad "double supersede accepted"; fi
    cmp -s "$ST/orig" "$ST/loc/docs/adr/0001-local-one.md" && [ ! -e "$ST/loc/docs/adr/0003-again.md" ] || bad "refused supersede wrote something"
    ln -s "$ST/other/0001-x.md" "$ST/loc/docs/adr/0010-link.md"
    if run "$ST/loc" supersede 10 "Via link" --apply; then bad "supersede through a symlink accepted"; fi
    rm -f "$ST/loc/docs/adr/0010-link.md"
    printf '# C\r\n\r\n## Status\r\nAccepted — 2025-01-01.\r\n\r\n## Context\r\nx\r\n' >"$ST/loc/docs/adr/0020-crlf.md"
    run "$ST/loc" supersede 20 "After CRLF" --apply || bad "supersede on CRLF failed"
    [ "$(sed -n 5p "$ST/loc/docs/adr/0020-crlf.md")" = "$(printf 'Superseded by 0021 — 2026-01-02.\r')" ] || bad "CRLF supersede line misplaced or LF-only"
    printf '# F\n\n## Status\nAccepted — 2025-01-01. Supersedes 0077.\n' >"$ST/loc/docs/adr/0030-f.md"
    if run "$ST/loc" --check; then bad "broken forward reference passed --check"; fi
    grep -q 'broken supersede reference 0077' "$ST/out" || bad "--check missed forward ref 0077"
    rm -f "$ST/loc/docs/adr/0030-f.md"
    if run "$ST/loc" new "X" --check; then bad "--check combined with new accepted"; fi
    printf '# M\n\n## Status\nAccepted — 2025-01-01.\n' >"$ST/loc/docs/adr/9999-max.md"
    if run "$ST/loc" new "Overflow" --apply; then bad "numbering past 9999 accepted"; fi
    ok

    # error cases
    if run "$ST/nope"; then bad "missing path accepted"; fi
    if run "$ST/empty" --lang fr; then bad "bad --lang accepted"; fi
    ok
    log_ok "adr.sh self-test: $pass groups passed"
}

case "$MODE" in
help) print_usage ;;
self-test) self_test ;;
check) do_check ;;
scaffold) do_scaffold ;;
new) do_new ;;
supersede) do_supersede ;;
esac
