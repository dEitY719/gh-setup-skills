#!/bin/bash
# Drift guard for kanban-bootstrap's two copies of host resolution
# (dEitY719/gh-setup-skills#10). references/prereq.md's `_kanban_host` runs at
# SKILL level before Step 2; lib/setup.sh's `detect_host` runs inside the
# script. They must agree on every input — the bug this covers was prereq.md
# aborting (rc=1) where detect_host defaults to github.com, which rejected
# `--owner`/`--repo` callers outside a git checkout before the script that
# handles them ever ran.
#
# Fakes `git` on PATH so nothing touches a real remote. Run manually or via
# tests/run.sh: bash skills/kanban-bootstrap/tests/host.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PREREQ="${SCRIPT_DIR}/../references/prereq.md"
SETUP="${SCRIPT_DIR}/../lib/setup.sh"
FAKE_BIN="$(mktemp -d)"
trap 'rm -rf "$FAKE_BIN"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

# prereq.md ships its host resolution as the file's first ```sh block, ending
# with `HOST=$(_kanban_host)`; eval it verbatim so the test covers the text
# the skill actually follows, not a transcription of it.
PREREQ_SNIPPET="$(awk '/^```sh$/ {f=1; next} f && /^```$/ {exit} f' "$PREREQ")"
[ -n "$PREREQ_SNIPPET" ] || fail "no sh block found in $PREREQ"

# setup.sh ends in `main "$@"`, so it cannot be sourced — lift just the one
# function out of it.
SETUP_SNIPPET="$(sed -n '/^detect_host() {$/,/^}$/p' "$SETUP")"
[ -n "$SETUP_SNIPPET" ] || fail "detect_host not found in $SETUP"

fake_git() {
    # $1 = origin URL to report, or the empty string to fail like a non-repo
    if [ -n "$1" ]; then
        printf '#!/bin/bash\nprintf %%s\\\\n %q\n' "$1" >"${FAKE_BIN}/git"
    else
        printf '#!/bin/bash\nexit 128\n' >"${FAKE_BIN}/git"
    fi
    chmod +x "${FAKE_BIN}/git"
}

check() {
    # $1 = origin URL (empty = no repo), $2 = expected host
    local url="$1" want="$2" got_prereq got_setup
    fake_git "$url"
    got_prereq="$(PATH="${FAKE_BIN}:${PATH}" bash -c "${PREREQ_SNIPPET}"$'\n''printf %s "$HOST"')"
    got_setup="$(PATH="${FAKE_BIN}:${PATH}" bash -c "${SETUP_SNIPPET}"$'\n''detect_host; printf %s "$HOST"')"
    [ "$got_prereq" = "$want" ] || fail "prereq.md: '${url:-<no origin>}' -> '$got_prereq', want '$want'"
    [ "$got_setup" = "$want" ] || fail "setup.sh: '${url:-<no origin>}' -> '$got_setup', want '$want'"
}

check 'git@github.com:owner/repo.git'                 github.com
check 'https://github.com/owner/repo.git'             github.com
check 'git@github.samsungds.net:owner/repo.git'       github.samsungds.net
check 'https://github.samsungds.net/owner/repo.git'   github.samsungds.net
check 'ssh://git@github.samsungds.net:2222/owner/repo' github.samsungds.net

# The regression itself: no origin, and an origin git can report but neither
# function can parse. Both must yield the github.com default, not an abort —
# this is the path an explicit --owner/--repo invocation takes.
check ''                                              github.com
check '/srv/mirrors/repo.git'                         github.com

echo "[OK] prereq.md and lib/setup.sh resolve the same host on all 7 inputs"
