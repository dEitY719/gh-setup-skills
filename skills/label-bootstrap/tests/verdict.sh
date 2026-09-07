#!/bin/bash
# Regression check for lib/label-bootstrap.sh's Summary/verdict output
# (skill-check FAIL #9, dEitY719/gh-setup-skills#4). Not wired into CI — this
# repo has no test runner yet (see CLAUDE.md "Known migration debt" for the
# sibling pattern) — run manually: bash skills/label-bootstrap/tests/verdict.sh
#
# Fakes `gh` on PATH so no real API calls are made. Asserts the Summary line
# and [OK]/[FAIL] verdict for three paths: dry-run success, real-run success,
# and a fully-failed real run (read-only-token simulation).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT="${SCRIPT_DIR}/../lib/label-bootstrap.sh"
FAKE_BIN="$(mktemp -d)"
trap 'rm -rf "$FAKE_BIN"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    # $1 = haystack, $2 = needle, $3 = message
    printf '%s\n' "$1" | grep -qF "$2" || fail "$3 (expected to find: $2)"
}

# --- Case 1 & 2: every gh call succeeds --------------------------------
cat >"${FAKE_BIN}/gh" <<'EOF'
#!/bin/bash
if [ "$1" = "api" ]; then
    shift
    if [[ "$1" == repos/*/labels?per_page=100 ]]; then
        printf 'bug\nfeat\nold-custom\n'
        exit 0
    fi
    exit 0
fi
exit 1
EOF
chmod +x "${FAKE_BIN}/gh"

out="$(PATH="${FAKE_BIN}:${PATH}" bash "$SCRIPT" --repo fake/repo --dry-run)"
assert_contains "$out" 'Summary: renamed=1 created=10 synced=1 pruned=0 failed=0' "dry-run summary"
assert_contains "$out" '[OK] Labels synced to SSOT for fake/repo (dry-run)' "dry-run verdict"

out="$(PATH="${FAKE_BIN}:${PATH}" bash "$SCRIPT" --repo fake/repo)"
rc=$?
assert_contains "$out" 'Summary: renamed=1 created=10 synced=1 pruned=0 failed=0' "real-run summary"
assert_contains "$out" '[OK] Labels synced to SSOT for fake/repo' "real-run verdict"
[ "$rc" -eq 0 ] || fail "real-run success path must exit 0"

# --- Case 3: every gh mutation fails (read-only token) ------------------
cat >"${FAKE_BIN}/gh" <<'EOF'
#!/bin/bash
if [ "$1" = "api" ]; then
    shift
    if [[ "$1" == repos/*/labels?per_page=100 ]]; then
        printf 'bug\nfeat\nold-custom\n'
        exit 0
    fi
    exit 1
fi
exit 1
EOF
chmod +x "${FAKE_BIN}/gh"

set +e
out="$(PATH="${FAKE_BIN}:${PATH}" bash "$SCRIPT" --repo fake/repo --prune 2>/dev/null)"
rc=$?
set -e
assert_contains "$out" 'Summary: renamed=0 created=0 synced=0 pruned=0 failed=15' "all-fail summary"
assert_contains "$out" '[FAIL] Label sync incomplete for fake/repo' "all-fail verdict"
[ "$rc" -eq 1 ] || fail "a run where every mutation fails must exit non-zero (got $rc)"

echo "[OK] all label-bootstrap verdict checks passed"
