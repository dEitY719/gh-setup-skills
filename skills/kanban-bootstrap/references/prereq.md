# Prereq Check — F-2 Procedure

## Tools

```sh
command -v gh >/dev/null 2>&1 || {
    printf 'gh CLI not found — install from https://cli.github.com\n' >&2
    return 1
}
command -v jq >/dev/null 2>&1 || {
    printf 'jq not found — apt/brew install jq\n' >&2
    return 1
}
```

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
```

Uses shell parameter expansion instead of `cut` (no subprocess fork),
and strips the optional port from `ssh://user@host:2222/...` URLs.

## Token scope check

```sh
HOST=$(_kanban_host) || {
    printf 'not in a git repository (or origin is unparseable)\n' >&2
    return 1
}

scopes=$(gh api --hostname "$HOST" -i user 2>/dev/null \
    | awk 'tolower($1) == "x-oauth-scopes:" { sub(/^[^:]*:[ \t]*/, ""); print; exit }')

case ",${scopes// /}," in
    *,project,*|*,read:project,*) : ;;
    *)
        printf 'token missing project scope — run: gh auth refresh -h %s -s project\n' "$HOST" >&2
        return 1
        ;;
esac
```

## Flag naming inconsistency (`gh api` vs `gh auth refresh`)

`gh api` uses `--hostname` for the target host — `-h` is reserved as
its help flag. `gh auth refresh`, however, keeps `-h` as its hostname
short flag. The two CLIs are intentionally inconsistent; both forms
above are correct as written. Do not "fix" one to match the other.

## rc matrix

| condition | rc | message |
|-----------|----|---------|
| gh missing | 1 | `gh CLI not found — install from https://cli.github.com` |
| jq missing | 1 | `jq not found — apt/brew install jq` |
| not in git | 1 | `not in a git repository (or origin is unparseable)` |
| project scope missing | 1 | `token missing project scope — run: gh auth refresh -h <host> -s project` |
| all good | 0 | (silent) |

Step 5 (label bootstrap) reuses the result of this check — `repo`
scope is implied by `project` scope, so no extra check.
