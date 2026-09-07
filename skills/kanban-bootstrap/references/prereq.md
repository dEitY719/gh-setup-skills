# Prereq Check — F-2 Procedure

## Host detection

```sh
_kanban_host() {
    local _u _h
    _u=$(git remote get-url origin 2>/dev/null) || return 1
    case "$_u" in
        git@*)     _h="${_u#git@}";     printf '%s' "${_h%%:*}" ;;
        https://*) _h="${_u#https://}"; printf '%s' "${_h%%/*}" ;;
        ssh://*)   _h="${_u#ssh://}"; _h="${_h%%/*}"; _h="${_h#*@}"; printf '%s' "${_h%%:*}" ;;
        *) return 1 ;;
    esac
}

HOST=$(_kanban_host) || {
    printf 'not in a git repository (or origin is unparseable)\n' >&2
    return 1
}
```

Uses shell parameter expansion instead of `cut` (no subprocess fork), and
strips the optional port from `ssh://user@host:2222/...` URLs. `$HOST` feeds
Step 2's `gh repo view` call (and Step 7's smoke-test command).

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

| condition | rc | message |
|-----------|----|---------|
| not in a git repo (or origin unparseable) | 1 | `not in a git repository (or origin is unparseable)` |
| all good | 0 | (silent) |
