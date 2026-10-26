#!/bin/bash
# Regression check for the `automation|` feed (dEitY719/gh-setup-skills#23):
# wontfix / not-implement / manual are provisioned alongside TODO, a rerun
# creates nothing, and --prune keeps all four. Run:
#   bash skills/label-bootstrap/tests/automation.sh
#
# Fakes a stateful `gh` on PATH (labels persisted in a temp file) so no real
# API calls are made.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT="${SCRIPT_DIR}/../lib/label-bootstrap.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export FAKE_LABELS="${WORK}/labels"
: >"$FAKE_LABELS" # brand-new repo: zero labels

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
path="$1"
shift
if [[ "$path" == repos/*/labels?per_page=100 ]]; then
    cat "$FAKE_LABELS"
    exit 0
fi
method="" name=""
while [ "$#" -gt 0 ]; do
    case "$1" in
    -X) method="$2"; shift 2 ;;
    -f) case "$2" in name=*) name="${2#name=}" ;; esac; shift 2 ;;
    *) shift ;;
    esac
done
case "$method" in
POST) printf '%s\n' "$name" >>"$FAKE_LABELS" ;;
DELETE) grep -Fxv "${path##*/labels/}" "$FAKE_LABELS" >"${FAKE_LABELS}.tmp" || true
    mv "${FAKE_LABELS}.tmp" "$FAKE_LABELS" ;;
esac
exit 0
FAKE
chmod +x "${WORK}/bin/gh"

run() { PATH="${WORK}/bin:${PATH}" bash "$SCRIPT" --repo fake/repo "$@"; }

# 1. Empty repo: all four exclusion labels exist afterwards.
out="$(run)"
assert_contains "$out" 'Summary: renamed=0 created=15 synced=0 pruned=0 failed=0' "first-run summary"
for l in wontfix not-implement TODO manual; do
    grep -Fxq "$l" "$FAKE_LABELS" || fail "label '$l' not created on an empty repo"
done
# not-implement parsed with its own color — the hyphen must not drop the row.
assert_contains "$out" "POST label 'not-implement' (color=e99695)" "not-implement parsed"

# 2. Rerun is idempotent: nothing created, everything force-synced.
out="$(run)"
assert_contains "$out" 'Summary: renamed=0 created=0 synced=15 pruned=0 failed=0' "rerun summary"

# 3. --prune keeps all four, deletes a stray custom label.
printf 'old-custom\n' >>"$FAKE_LABELS"
out="$(run --prune)"
assert_contains "$out" 'Summary: renamed=0 created=0 synced=15 pruned=1 failed=0' "prune summary"
for l in wontfix not-implement TODO manual; do
    grep -Fxq "$l" "$FAKE_LABELS" || fail "--prune deleted '$l'"
done
grep -Fxq old-custom "$FAKE_LABELS" && fail "--prune kept a non-SSOT label"

# 4. GitHub label names are case-insensitive: an existing `Manual` is synced
#    (not re-POSTed) and survives --prune.
printf 'Manual\n' >"$FAKE_LABELS"
out="$(run --prune)"
assert_contains "$out" 'Summary: renamed=0 created=14 synced=1 pruned=0 failed=0' "case-variant summary"
grep -Fxq Manual "$FAKE_LABELS" || fail "--prune deleted case-variant 'Manual'"

echo "[OK] all label-bootstrap automation-feed checks passed"
