# Host-aware URL Rewrite — F-6

The script `lib/setup.sh` is now host-aware (post-#699) — it derives
all output URLs from `$HOST` set by `detect_host()`. This file
documents the same helpers in skill-callable form for cases where
the skill needs to rewrite URLs emitted by external tools (or older
output formats).

## Detect current host

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

Uses shell parameter expansion (no `cut` subprocess) and strips the
optional port from `ssh://user@host:2222/...` URLs.

Returns `github.com` on `git@github.com:...`, `github.samsungds.net`
on GHE, etc. Returns non-zero rc when not in a git repo.

## Rewrite legacy github.com URLs

```sh
_kanban_rewrite_urls() {
    local _host="$1"
    sed -e "s#https://github\\.com/#https://${_host}/#g"
}
```

Use when piping output from a tool that hardcodes `github.com`. The
new `lib/setup.sh` does NOT need this — it already substitutes `$HOST`
at the source (lines `project_url_from_owner_type` and
`workflows_url_from_owner_type`).

## Example

```sh
# Rewrite a captured stdout block
HOST=$(_kanban_host)
external_tool_output | _kanban_rewrite_urls "$HOST"
```

## Edge cases

- Bare `git@` remote with no host segment → `_kanban_host` returns
  rc=1, caller should default to `github.com`.
- Remote URL with port (`ssh://git@github.com:2222/...`) → host part
  is `github.com` (final `${_h%%:*}` step strips the port).
- Multiple origins (multi-remote repo) → only `origin` is consulted.
  This matches the dotfiles policy (always `origin`).
