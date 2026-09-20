# Prereq Check — F-2 Procedure

## Host detection

```sh
_kanban_host() {
    local _u _h=''
    _u=$(git remote get-url origin 2>/dev/null) || _u=''
    case "$_u" in
        git@*)     _h="${_u#git@}";     _h="${_h%%:*}" ;;
        https://*) _h="${_u#https://}"; _h="${_h%%/*}" ;;
        ssh://*)   _h="${_u#ssh://}"; _h="${_h%%/*}"; _h="${_h#*@}"; _h="${_h%%:*}" ;;
    esac
    printf '%s' "${_h:-github.com}"
}

HOST=$(_kanban_host)
```

Uses shell parameter expansion instead of `cut` (no subprocess fork), and
strips the optional port from `ssh://user@host:2222/...` URLs. `$HOST` feeds
Step 2's `gh repo view` call (and Step 7's smoke-test command).

## No origin is not an error here

This mirrors `lib/setup.sh`'s `detect_host` exactly — same three URL shapes,
same `github.com` fallback — and must keep mirroring it. It used to abort with
rc=1 whenever `git remote get-url origin` failed, which made the SKILL-level
gate stricter than the script it wraps: `--owner`/`--repo` are a documented
override that needs no checkout at all (`lib/setup.sh`'s `detect_repo_defaults`
short-circuits its own auto-detect when both are supplied), yet a caller who
passed both from outside a git repo was rejected at Step 1 before the script
that would have handled the request ever ran (dEitY719/gh-setup-skills#10).

A run that genuinely has no target still fails, just later and with a better
message: `lib/setup.sh` dies with `--owner is required (auto-detect failed;
pass --owner or run inside a GitHub-linked git repo)` on Step 5's dry-run
dispatch. `skills/kanban-bootstrap/tests/host.sh` asserts both functions agree.

## Tool / token-scope checks are not duplicated here

`lib/setup.sh` already checks for `gh`/`jq` and the token's `project` scope at
the top of its own `main()` (`require_command`, `require_project_scope`) — a
miss there aborts with rc=1 and a stderr hint, which Step 5's dry-run dispatch
surfaces before any mutation runs. A second copy of that check lived here
until it drifted from the script's own version (different `--hostname` usage,
different refresh-hint text for two failure paths). Removing it makes
`lib/setup.sh` the single owner; this file only resolves `$HOST`, which the
script cannot supply back to the SKILL-level flow that needs it before Step 2.

## rc matrix

| condition | rc | `$HOST` |
|-----------|----|---------|
| `origin` parses | 0 | host from the URL |
| no `origin`, not a git repo, or URL unparseable | 0 | `github.com` |
