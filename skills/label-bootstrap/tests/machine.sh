#!/bin/bash
# Regression check for the `machine|` feed (dEitY719/gh-setup-skills#25):
# home-pc / internal-pc / external-pc are created with their SSOT colors, a
# rerun creates nothing, --prune keeps them, and --dry-run mutates nothing.
# Run: bash skills/label-bootstrap/tests/machine.sh
set -euo pipefail

# shellcheck source=lib/fake-gh.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/fake-gh.sh" # brand-new repo: zero labels

assert_machine_labels() {
    for l in home-pc internal-pc external-pc; do
        grep -Fxq "$l" "$FAKE_LABELS" || fail "label '$l' missing ($1)"
    done
}

# 0. --dry-run plans the three POSTs and makes zero mutating calls.
out="$(run --dry-run)"
assert_contains "$out" "[dry-run] POST label 'home-pc' (color=fef2c0)" "dry-run plans home-pc"
assert_contains "$out" "[dry-run] POST label 'internal-pc' (color=d4c5f9)" "dry-run plans internal-pc"
assert_contains "$out" "[dry-run] POST label 'external-pc' (color=c5def5)" "dry-run plans external-pc"
[ -s "$FAKE_GH_LOG" ] && fail "--dry-run made mutating calls: $(cat "$FAKE_GH_LOG")"
[ -s "$FAKE_LABELS" ] && fail "--dry-run created labels"

# 1. Empty repo: 18 labels created, the three machine labels among them.
out="$(run)"
assert_contains "$out" 'Summary: renamed=0 created=18 synced=0 pruned=0 failed=0' "first-run summary"
assert_machine_labels "empty repo"

# 2. Rerun is idempotent.
out="$(run)"
assert_contains "$out" 'Summary: renamed=0 created=0 synced=18 pruned=0 failed=0' "rerun summary"

# 3. --prune keeps the machine labels.
out="$(run --prune)"
assert_contains "$out" 'pruned=0 failed=0' "prune summary"
assert_machine_labels "after --prune"

# 4. Case variant `Home-PC` is synced and recased, not re-POSTed.
printf 'Home-PC\n' >"$FAKE_LABELS"
out="$(run --prune)"
assert_contains "$out" 'Summary: renamed=0 created=17 synced=1 pruned=0 failed=0' "case-variant summary"
grep -Fxq home-pc "$FAKE_LABELS" || fail "case-variant 'Home-PC' not recased to 'home-pc'"

echo "[OK] all label-bootstrap machine-feed checks passed"
