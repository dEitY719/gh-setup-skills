#!/bin/bash
# Regression check for #25 R-1 / R-2: labels past the first page of 100 are
# seen (--paginate), and names with spaces / colons / non-ASCII are
# URL-encoded in PATCH/DELETE paths.
# Run: bash skills/label-bootstrap/tests/pagination-encoding.sh
set -euo pipefail

# shellcheck source=lib/fake-gh.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/fake-gh.sh"

# 115-label repo: 110 custom fillers first, so the SSOT label `feat` and the
# special-character names all sit past the first page.
for i in $(seq -w 1 110); do printf 'custom-%s\n' "$i"; done >"$FAKE_LABELS"
printf '%s\n' feat 'good first issue' 'priority: high' '집중' 'Bug' >>"$FAKE_LABELS"

# R-1: `feat` (row 111) must be PATCHed, not POSTed (POST would 422 -> failed).
out="$(run)"
assert_contains "$out" "PATCH label 'feat'" "feat past page 1 is synced"
assert_contains "$out" "rename label 'bug' -> 'fix'" "Bug past page 1 is renamed"
assert_contains "$out" 'failed=0' "no 422 on labels past page 1"

# R-2: --prune deletes encoded names without 404; allowlisted name survives.
out="$(run --prune)"
assert_contains "$out" 'Summary: renamed=0 created=0 synced=18 pruned=112 failed=0' "prune summary"
grep -q 'labels/priority%3A%20high$' "$FAKE_GH_LOG" || fail "colon/space name not encoded"
grep -q 'labels/%EC%A7%91%EC%A4%91$' "$FAKE_GH_LOG" || fail "non-ASCII name not encoded"
grep -Fxq 'good first issue' "$FAKE_LABELS" || fail "allowlisted 'good first issue' pruned"
grep -Fxq 'priority: high' "$FAKE_LABELS" && fail "'priority: high' not pruned"
grep -Fxq 'custom-110' "$FAKE_LABELS" && fail "label past page 1 missed by --prune"
[ "$(wc -l <"$FAKE_LABELS")" -eq 19 ] || fail "expected 18 SSOT + good first issue, got $(wc -l <"$FAKE_LABELS")"

echo "[OK] all label-bootstrap pagination/encoding checks passed"
