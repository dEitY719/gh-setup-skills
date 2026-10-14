#!/usr/bin/env bash
# tests/bats/test_helper.bash -- shared setup for this repo's bats suite.
# Run: BATS_LIB_PATH=<dir with bats-support,bats-assert> bats -r tests/bats

bats_load_library bats-support
bats_load_library bats-assert

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

AI_METRICS_LIB="$REPO_ROOT/skills/add-ai-metrics/lib/ai-metrics.sh"

# Define the named functions from the shipped
# skills/add-ai-metrics/lib/ai-metrics.sh, nothing else. The lib cannot be
# sourced whole: it ends in an unconditional `main "$@"` dispatch and defines
# its own run(), which would shadow bats' run. So lift each `name() {` .. `}`
# block out, the way skills/add-ai-metrics/tests/shell-common-sibling.sh does,
# and fail loudly if one is missing so a rename cannot pass silently.
load_ai_metrics_functions() {
    local fn body
    for fn in "$@"; do
        body="$(sed -n "/^${fn}() {\$/,/^}\$/p" "$AI_METRICS_LIB")"
        [ -n "$body" ] || {
            echo "load_ai_metrics_functions: ${fn}() not found in $AI_METRICS_LIB" >&2
            return 1
        }
        eval "$body"
    done
}

setup_isolated_home() {
    TEST_TEMP_HOME="$(mktemp -d)"
    export HOME="$TEST_TEMP_HOME"
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_CACHE_HOME="$HOME/.cache"
    export XDG_DATA_HOME="$HOME/.local/share"
    export XDG_STATE_HOME="$HOME/.local/state"
    unset CLAUDE_CONFIG_DIR
    export TERM=dumb
}

teardown_isolated_home() {
    [ -n "${TEST_TEMP_HOME:-}" ] && [ -d "$TEST_TEMP_HOME" ] && rm -rf "$TEST_TEMP_HOME"
    unset TEST_TEMP_HOME
}
