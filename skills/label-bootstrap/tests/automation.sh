#!/bin/bash
# Regression check for the `automation|` feed (dEitY719/gh-setup-skills#23):
# wontfix / not-implement / manual are provisioned alongside TODO, a rerun
# creates nothing, and --prune keeps all four. Run:
#   bash skills/label-bootstrap/tests/automation.sh
#
# Fakes a stateful `gh` on PATH (tests/lib/fake-gh.sh) so no real API calls
# are made.
set -euo pipefail

# shellcheck source=lib/fake-gh.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/fake-gh.sh" # brand-new repo: zero labels

assert_exclusion_labels() {
    for l in wontfix not-implement TODO manual; do
        grep -Fxq "$l" "$FAKE_LABELS" || fail "label '$l' missing ($1)"
    done
}

# 0. --dry-run on an empty repo plans the new feed but mutates nothing.
out="$(run --dry-run)"
assert_contains "$out" "[dry-run] POST label 'not-implement' (color=e99695)" "dry-run plans not-implement"
[ -s "$FAKE_LABELS" ] && fail "--dry-run created labels"

# 1. Empty repo: all four exclusion labels exist afterwards.
out="$(run)"
assert_contains "$out" 'Summary: renamed=0 created=18 synced=0 pruned=0 failed=0' "first-run summary"
assert_exclusion_labels "empty repo"
# not-implement parsed with its own color — the hyphen must not drop the row.
assert_contains "$out" "POST label 'not-implement' (color=e99695)" "not-implement parsed"

# 2. Rerun is idempotent: nothing created, everything force-synced.
out="$(run)"
assert_contains "$out" 'Summary: renamed=0 created=0 synced=18 pruned=0 failed=0' "rerun summary"

# 3. --prune keeps all four, deletes a stray custom label.
printf 'old-custom\n' >>"$FAKE_LABELS"
out="$(run --prune)"
assert_contains "$out" 'Summary: renamed=0 created=0 synced=18 pruned=1 failed=0' "prune summary"
assert_exclusion_labels "after --prune"
grep -Fxq old-custom "$FAKE_LABELS" && fail "--prune kept a non-SSOT label"

# 4. GitHub label names are case-insensitive: an existing `Manual` is synced
#    (not re-POSTed), recased to the SSOT `manual` by PATCH new_name, and
#    survives --prune.
printf 'Manual\n' >"$FAKE_LABELS"
out="$(run --prune)"
assert_contains "$out" 'Summary: renamed=0 created=17 synced=1 pruned=0 failed=0' "case-variant summary"
grep -Fxq manual "$FAKE_LABELS" || fail "case-variant 'Manual' not recased to 'manual' (or pruned)"
grep -Fxq Manual "$FAKE_LABELS" && fail "case-variant 'Manual' kept its old case"

echo "[OK] all label-bootstrap automation-feed checks passed"
