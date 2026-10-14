#!/usr/bin/env bats
# tests/bats/gh_add_ai_metrics_pace.bats
# Verify the pace/limit/budget helpers used by /gh-setup:add-ai-metrics.
# Runs the shipped functions in skills/add-ai-metrics/lib/ai-metrics.sh
# (documented in skills/add-ai-metrics/references/pace-control.md); no hand copy.
# Moved from dEitY719/dotfiles tests/bats/skills/ (dEitY719/dotfiles#2200).

load 'test_helper'

setup() {
    setup_isolated_home
    load_ai_metrics_functions \
        parse_duration format_duration sleep_pace check_budget compute_eta
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# parse_duration — accepted forms
# ---------------------------------------------------------------------------

@test "parse_duration: 30s → 30" {
    run parse_duration "30s"
    assert_success
    assert_output "30"
}

@test "parse_duration: 5m → 300" {
    run parse_duration "5m"
    assert_success
    assert_output "300"
}

@test "parse_duration: 1h → 3600" {
    run parse_duration "1h"
    assert_success
    assert_output "3600"
}

@test "parse_duration: 1h30m → 5400 (compound)" {
    run parse_duration "1h30m"
    assert_success
    assert_output "5400"
}

@test "parse_duration: 1m30s → 90 (compound minor units)" {
    run parse_duration "1m30s"
    assert_success
    assert_output "90"
}

@test "parse_duration: 4h30m → 16200 (the canonical overnight budget)" {
    run parse_duration "4h30m"
    assert_success
    assert_output "16200"
}

# ---------------------------------------------------------------------------
# parse_duration — rejected forms
# ---------------------------------------------------------------------------

@test "parse_duration: empty rejected" {
    run parse_duration ""
    assert_failure
}

@test "parse_duration: bare number (no unit) rejected" {
    run parse_duration "3"
    assert_failure
}

@test "parse_duration: unsupported unit (d) rejected" {
    run parse_duration "5d"
    assert_failure
}

@test "parse_duration: fractional value rejected" {
    run parse_duration "1.5h"
    assert_failure
}

@test "parse_duration: trailing bare number rejected" {
    run parse_duration "1h30"
    assert_failure
}

@test "parse_duration: alpha junk rejected" {
    run parse_duration "fast"
    assert_failure
}

# ---------------------------------------------------------------------------
# format_duration — round-trip readability
# ---------------------------------------------------------------------------

@test "format_duration: 0 → 0s" {
    run format_duration 0
    assert_success
    assert_output "0s"
}

@test "format_duration: 90 → 1m30s" {
    run format_duration 90
    assert_success
    assert_output "1m30s"
}

@test "format_duration: 3600 → 1h" {
    run format_duration 3600
    assert_success
    assert_output "1h"
}

@test "format_duration: 5400 → 1h30m" {
    run format_duration 5400
    assert_success
    assert_output "1h30m"
}

@test "format_duration: 16200 → 4h30m (overnight budget)" {
    run format_duration 16200
    assert_success
    assert_output "4h30m"
}

@test "format_duration: parse_duration round-trip preserves canonical strings" {
    secs=$(parse_duration "1h30m")
    run format_duration "$secs"
    assert_success
    assert_output "1h30m"
}

# ---------------------------------------------------------------------------
# sleep_pace — must NOT actually sleep when 0
# ---------------------------------------------------------------------------

@test "sleep_pace: 0 returns immediately (no actual sleep)" {
    start=$EPOCHREALTIME
    run sleep_pace 0
    assert_success
    end=$EPOCHREALTIME
    # Tolerate 50ms — well under any real sleep call.
    delta_ms=$(awk -v s="$start" -v e="$end" 'BEGIN { printf "%d", (e - s) * 1000 }')
    [ "$delta_ms" -lt 50 ]
}

@test "sleep_pace: unset arg defaults to 0 and returns immediately" {
    start=$EPOCHREALTIME
    run sleep_pace
    assert_success
    end=$EPOCHREALTIME
    delta_ms=$(awk -v s="$start" -v e="$end" 'BEGIN { printf "%d", (e - s) * 1000 }')
    [ "$delta_ms" -lt 50 ]
}

# ---------------------------------------------------------------------------
# check_budget — boundary semantics
# ---------------------------------------------------------------------------

@test "check_budget: well under budget → false (continue)" {
    run check_budget 100 16200
    assert_failure
}

@test "check_budget: one second short of budget → false (continue)" {
    run check_budget 16199 16200
    assert_failure
}

@test "check_budget: exactly at budget → true (stop, conservative)" {
    run check_budget 16200 16200
    assert_success
}

@test "check_budget: over budget → true (stop)" {
    run check_budget 99999 16200
    assert_success
}

@test "check_budget: budget unset (0) → never stops" {
    run check_budget 99999 0
    assert_failure
}

@test "check_budget: budget empty string → never stops" {
    run check_budget 99999 ""
    assert_failure
}

# ---------------------------------------------------------------------------
# compute_eta — wall-clock estimate for --dry-run
# ---------------------------------------------------------------------------

@test "compute_eta: 0 writes → no-writes string" {
    run compute_eta 0 180
    assert_success
    assert_output "0s (no writes)"
}

@test "compute_eta: 1 write → 0s (no gap to wait through)" {
    run compute_eta 1 180
    assert_success
    assert_output "0s"
}

@test "compute_eta: 12 writes × 3m → 33m (11 gaps × 3m)" {
    run compute_eta 12 180
    assert_success
    assert_output "33m"
}

@test "compute_eta: 200 writes × 3m → 9h57m" {
    run compute_eta 200 180
    assert_success
    assert_output "9h57m"
}

@test "compute_eta: pace=0 (no pacing) → no-pace string" {
    run compute_eta 100 0
    assert_success
    assert_output "<1m (no pace)"
}
