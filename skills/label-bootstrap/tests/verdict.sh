#!/bin/bash
# Regression check for lib/label-bootstrap.sh's Summary/verdict output
# (skill-check FAIL #9, dEitY719/gh-setup-skills#4). Run via tests/run.sh or
# bash skills/label-bootstrap/tests/verdict.sh
#
# Fakes `gh` on PATH (tests/lib/fake-gh.sh) so no real API calls are made.
# Asserts the Summary line and [OK]/[FAIL] verdict for three paths: dry-run
# success, real-run success, and a fully-failed real run (read-only token).
set -euo pipefail

# shellcheck source=lib/fake-gh.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/fake-gh.sh"

# --- Case 1 & 2: every gh call succeeds --------------------------------
printf 'bug\nfeat\nold-custom\n' >"$FAKE_LABELS"

out="$(run --dry-run)"
assert_contains "$out" 'Summary: renamed=1 created=16 synced=1 pruned=0 failed=0' "dry-run summary"
assert_contains "$out" '[OK] Labels synced to SSOT for fake/repo (dry-run)' "dry-run verdict"

out="$(run)"
rc=$?
assert_contains "$out" 'Summary: renamed=1 created=16 synced=1 pruned=0 failed=0' "real-run summary"
assert_contains "$out" '[OK] Labels synced to SSOT for fake/repo' "real-run verdict"
[ "$rc" -eq 0 ] || fail "real-run success path must exit 0"

# --- Case 3: every gh mutation fails (read-only token) ------------------
printf 'bug\nfeat\nold-custom\n' >"$FAKE_LABELS"

set +e
out="$(FAKE_GH_FAIL_MUTATIONS=1 run --prune 2>/dev/null)"
rc=$?
set -e
assert_contains "$out" 'Summary: renamed=0 created=0 synced=0 pruned=0 failed=21' "all-fail summary"
assert_contains "$out" '[FAIL] Label sync incomplete for fake/repo' "all-fail verdict"
[ "$rc" -eq 1 ] || fail "a run where every mutation fails must exit non-zero (got $rc)"

echo "[OK] all label-bootstrap verdict checks passed"
