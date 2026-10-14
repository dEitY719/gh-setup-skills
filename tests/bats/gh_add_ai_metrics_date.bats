#!/usr/bin/env bats
# tests/bats/gh_add_ai_metrics_date.bats
# Verify the date-argument parsing helpers used by /gh-setup:add-ai-metrics.
# Runs the shipped functions in skills/add-ai-metrics/lib/ai-metrics.sh
# (documented in skills/add-ai-metrics/references/date-parsing.md); no hand copy.
# Moved from dEitY719/dotfiles tests/bats/skills/ (dEitY719/dotfiles#2200).

load 'test_helper'

setup() {
    setup_isolated_home
    load_ai_metrics_functions \
        parse_date_arg _emit_month last_day_of_month _minus_one_day _expand_day _valid_calendar_date build_search_clause
}

teardown() {
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# last_day_of_month — leap-year correctness across the fallback chain
# ---------------------------------------------------------------------------

@test "last_day_of_month: April → 30" {
    run last_day_of_month 2026 04
    assert_success
    assert_output "30"
}

@test "last_day_of_month: February non-leap (2026) → 28" {
    run last_day_of_month 2026 02
    assert_success
    assert_output "28"
}

@test "last_day_of_month: February leap year (2024) → 29" {
    run last_day_of_month 2024 02
    assert_success
    assert_output "29"
}

@test "last_day_of_month: December → 31" {
    run last_day_of_month 2026 12
    assert_success
    assert_output "31"
}

# ---------------------------------------------------------------------------
# parse_date_arg — single-day form (existing behaviour, no regression)
# ---------------------------------------------------------------------------

@test "parse_date_arg: 10-char YYYY-MM-DD → single passthrough" {
    run parse_date_arg "2026-04-30"
    assert_success
    assert_output "single 2026-04-30"
}

@test "parse_date_arg: 8-char YY-MM-DD → single with 20YY expansion" {
    run parse_date_arg "26-04-30"
    assert_success
    assert_output "single 2026-04-30"
}

# ---------------------------------------------------------------------------
# parse_date_arg — month form
# ---------------------------------------------------------------------------

@test "parse_date_arg: 5-char YY-MM → month range" {
    run parse_date_arg "26-04"
    assert_success
    assert_output "month 2026-04-01 2026-04-30"
}

@test "parse_date_arg: 7-char YYYY-MM → month range" {
    run parse_date_arg "2026-04"
    assert_success
    assert_output "month 2026-04-01 2026-04-30"
}

@test "parse_date_arg: month form covers leap February correctly" {
    run parse_date_arg "24-02"
    assert_success
    assert_output "month 2024-02-01 2024-02-29"
}

@test "parse_date_arg: month form covers non-leap February" {
    run parse_date_arg "26-02"
    assert_success
    assert_output "month 2026-02-01 2026-02-28"
}

# ---------------------------------------------------------------------------
# parse_date_arg — range form
# ---------------------------------------------------------------------------

@test "parse_date_arg: 8-char range A..B → half-open (end -1 day)" {
    run parse_date_arg "26-04-03..26-04-11"
    assert_success
    assert_output "range 2026-04-03 2026-04-10"
}

@test "parse_date_arg: 10-char range A..B → half-open (end -1 day)" {
    run parse_date_arg "2026-04-03..2026-04-11"
    assert_success
    assert_output "range 2026-04-03 2026-04-10"
}

@test "parse_date_arg: range with ~ separator → normalized to .." {
    run parse_date_arg "26-04-03~26-04-11"
    assert_success
    assert_output "range 2026-04-03 2026-04-10"
}

@test "parse_date_arg: range halves of mixed length both normalized" {
    run parse_date_arg "26-04-03..2026-04-11"
    assert_success
    assert_output "range 2026-04-03 2026-04-10"
}

@test "parse_date_arg: range crossing month boundary" {
    run parse_date_arg "26-04-30..26-05-02"
    assert_success
    assert_output "range 2026-04-30 2026-05-01"
}

@test "parse_date_arg: range crossing year boundary handles month rollover" {
    run parse_date_arg "26-12-31..27-01-02"
    assert_success
    assert_output "range 2026-12-31 2027-01-01"
}

# ---------------------------------------------------------------------------
# parse_date_arg — invalid inputs
# ---------------------------------------------------------------------------

@test "parse_date_arg: empty input rejected" {
    run parse_date_arg ""
    assert_failure
}

@test "parse_date_arg: 6-char YY-M-D rejected (wrong shape)" {
    run parse_date_arg "26-4-3"
    assert_failure
}

@test "parse_date_arg: range with empty start rejected" {
    run parse_date_arg "..26-04-11"
    assert_failure
}

@test "parse_date_arg: range with empty end rejected" {
    run parse_date_arg "26-04-03.."
    assert_failure
}

@test "parse_date_arg: alpha junk rejected" {
    run parse_date_arg "april-30"
    assert_failure
}

# ---------------------------------------------------------------------------
# build_search_clause
# ---------------------------------------------------------------------------

@test "build_search_clause: single → created:DATE" {
    run build_search_clause single 2026-04-30
    assert_success
    assert_output "created:2026-04-30"
}

@test "build_search_clause: month → created:A..B" {
    run build_search_clause month 2026-04-01 2026-04-30
    assert_success
    assert_output "created:2026-04-01..2026-04-30"
}

@test "build_search_clause: range → created:A..B (already half-open adjusted)" {
    run build_search_clause range 2026-04-03 2026-04-10
    assert_success
    assert_output "created:2026-04-03..2026-04-10"
}

@test "build_search_clause: unknown kind rejected" {
    run build_search_clause bogus 2026-04-01
    assert_failure
}

# ---------------------------------------------------------------------------
# End-to-end: parse_date_arg → build_search_clause composition
# ---------------------------------------------------------------------------

@test "e2e: month form composes to expected GitHub query" {
    out=$(parse_date_arg "26-04")
    # shellcheck disable=SC2086
    set -- $out  # split into kind/a/b
    run build_search_clause "$@"
    assert_success
    assert_output "created:2026-04-01..2026-04-30"
}

@test "e2e: range form composes (half-open semantics preserved)" {
    out=$(parse_date_arg "26-04-03..26-04-11")
    # shellcheck disable=SC2086
    set -- $out
    run build_search_clause "$@"
    assert_success
    assert_output "created:2026-04-03..2026-04-10"
}
