#!/bin/bash
# Shared test harness for skills/label-bootstrap/tests/*.sh (#25 F-7).
# Source it; it creates $WORK (removed on EXIT) with a stateful fake `gh` on
# $WORK/bin that models the parts of the GitHub label API the script uses:
#   - list: one label name per line from $FAKE_LABELS; without --paginate only
#     the first page (100 names) is returned, as the real API does.
#   - POST/PATCH/DELETE: path names are URL-decoded; an undecodable or unknown
#     name 404s (exit 1), matched case-insensitively like GitHub.
#   - FAKE_GH_FAIL_MUTATIONS=1 makes every mutation fail (read-only token).
#   - every mutation is appended to $FAKE_GH_LOG (for --dry-run checks).
# Helpers: run <args> (script against fake/repo), fail, assert_contains.

LB_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)/lib/label-bootstrap.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export FAKE_LABELS="${WORK}/labels" FAKE_GH_LOG="${WORK}/mutations"
: >"$FAKE_LABELS"
: >"$FAKE_GH_LOG"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    printf '%s\n' "$1" | grep -qF -- "$2" || fail "$3 (expected to find: $2)"
}

mkdir -p "${WORK}/bin"
cat >"${WORK}/bin/gh" <<'FAKE'
#!/bin/bash
[ "$1" = "api" ] || exit 1
shift
paginate=false path="" method="" name="" new_name=""
while [ "$#" -gt 0 ]; do
    case "$1" in
    --paginate) paginate=true; shift ;;
    --jq) shift 2 ;;
    -X) method="$2"; shift 2 ;;
    -f) case "$2" in name=*) name="${2#name=}" ;; new_name=*) new_name="${2#new_name=}" ;; esac; shift 2 ;;
    *) path="$1"; shift ;;
    esac
done
if [ -z "$method" ] && [[ "$path" == repos/*/labels\?per_page=100 ]]; then
    if $paginate; then cat "$FAKE_LABELS"; else head -n 100 "$FAKE_LABELS"; fi
    exit 0
fi
printf '%s %s\n' "$method" "$path" >>"$FAKE_GH_LOG"
[ "${FAKE_GH_FAIL_MUTATIONS:-}" = 1 ] && exit 1
# Raw spaces/colons in a path are what the real API 404s on.
case "$path" in *' '* | *:*) exit 1 ;; esac
target="${path##*/labels/}"
target="$(printf '%b' "${target//%/\\x}")"
exists() { awk -v n="$1" 'tolower($0)==tolower(n){f=1} END{exit !f}' "$FAKE_LABELS"; }
case "$method" in
POST) exists "$name" && exit 1 # 422 already_exists
    printf '%s\n' "$name" >>"$FAKE_LABELS" ;;
PATCH) exists "$target" || exit 1
    awk -v old="$target" -v new="$new_name" \
        'tolower($0)==tolower(old){$0=new} {print}' "$FAKE_LABELS" >"${FAKE_LABELS}.tmp"
    mv "${FAKE_LABELS}.tmp" "$FAKE_LABELS" ;;
DELETE) exists "$target" || exit 1
    awk -v n="$target" 'tolower($0)!=tolower(n)' "$FAKE_LABELS" >"${FAKE_LABELS}.tmp"
    mv "${FAKE_LABELS}.tmp" "$FAKE_LABELS" ;;
esac
exit 0
FAKE
chmod +x "${WORK}/bin/gh"

run() { PATH="${WORK}/bin:${PATH}" bash "$LB_SCRIPT" --repo fake/repo "$@"; }
