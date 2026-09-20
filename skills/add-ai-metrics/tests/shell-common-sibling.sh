#!/bin/bash
# Guard for the one part of the plugin-root convention that reaches this skill
# (dEitY719/gh-setup-skills#14, rolling out dEitY719/harness-skills#37).
#
# resolve_repo sources dotfiles' gh_host.sh when a checkout is present. That
# helper resolves its OWN sibling dotfiles_root.sh through
# ${SHELL_COMMON:-$HOME/dotfiles/shell-common} while it is being sourced, so
# SHELL_COMMON has to be set BEFORE the `.`. Unset, the lookup goes to
# $HOME/dotfiles even when DOTFILES_ROOT points somewhere else: it misses, and
# gh_host.sh prints "#1454 guard skipped (#724)" and carries on without that
# guard. Resolution still succeeds, which is why only the helper's own stderr
# shows it — an exit-status assertion would pass either way.
#
# The rest of the convention does NOT apply here and this file deliberately
# does not assert it: this repo vendors no lib/vendor/shell-common, so there is
# no tier 2 to reach and nothing to point CLAUDE_PLUGIN_ROOT at, and
# resolve_repo's no-dotfiles path is a complete inline URL parse rather than a
# tier-5 stop. ai-metrics.sh is also executed, never sourced, so a poisoned
# SHELL_COMMON cannot outlive the process.
#
# Fakes git on PATH and builds a DOTFILES_ROOT away from $HOME, so nothing
# touches a real remote or a real dotfiles checkout. Run manually or via
# tests/run.sh: bash skills/add-ai-metrics/tests/shell-common-sibling.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
METRICS="${SCRIPT_DIR}/../lib/ai-metrics.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# A DOTFILES_ROOT that is NOT $HOME/dotfiles — the only shape that shows the
# bug, because with the default path the helper's own fallback happens to land
# in the right place and hides it.
SC="$WORK/dotfiles/shell-common/functions"
mkdir -p "$SC" "$WORK/home" "$WORK/bin"

# Stands in for dotfiles' gh_host.sh: the same source-time sibling lookup and
# the same warning, reduced to the two lines this test is about.
cat >"$SC/gh_host.sh" <<'HOST'
_drg_helper="${SHELL_COMMON:-$HOME/dotfiles/shell-common}/functions/dotfiles_root.sh"
if [ -r "$_drg_helper" ]; then
    . "$_drg_helper"
fi
if ! command -v _dotfiles_root_guard_self >/dev/null 2>&1; then
    printf '[gh_host] %s missing or did not define _dotfiles_root_guard_self — #1454 guard skipped (#724).\n' \
        "$_drg_helper" >&2
fi
_gh_parse_owner_repo_url() { printf 'acme/widget'; }
_gh_host_from_url() { printf 'github.com'; }
_gh_resolve_host() { printf 'github.com'; }
HOST
printf '_dotfiles_root_guard_self() { :; }\n' >"$SC/dotfiles_root.sh"

# resolve_repo is not callable on its own — ai-metrics.sh ends in a dispatch —
# so lift the function out and run it the way the script does.
SNIPPET="$(sed -n '/^resolve_repo() {$/,/^}$/p' "$METRICS")"
[ -n "$SNIPPET" ] || fail "resolve_repo not found in $METRICS"

printf '#!/bin/bash\nprintf %%s\\n "git@github.com:acme/widget.git"\n' >"$WORK/bin/git"
chmod +x "$WORK/bin/git"

run() { # run <repo-or-empty> -> the run's stderr, on stdout
    # Braces rather than `2>&1 >/dev/null`: same effect, but unambiguous both
    # to SC2069 and to the next reader — only stderr is captured, and stderr
    # is the whole observable here.
    { env -u SHELL_COMMON -u GH_HOST PATH="$WORK/bin:$PATH" \
        HOME="$WORK/home" DOTFILES_ROOT="$WORK/dotfiles" \
        REPO="$1" REMOTE=origin \
        bash -c "
            set -euo pipefail
            die() { printf 'die: %s\n' \"\$1\" >&2; exit 1; }
            $SNIPPET
            resolve_repo
            printf 'repo=%s host=%s\n' \"\$TARGET_REPO\" \"\$TARGET_HOST\"
        " >/dev/null; } 2>&1
}

# Both branches source gh_host.sh, so both have to set SHELL_COMMON first:
# the --repo branch for the setup-mode mapping, the remote branch for URL
# parsing. Fixing one and not the other is the shape this asserts against.
for label in '--repo given' 'remote path'; do
    case "$label" in
        '--repo given') err="$(run acme/widget)" ;;
        *)              err="$(run '')" ;;
    esac
    case "$err" in
        *'#1454 guard skipped'*)
            fail "$label: gh_host.sh could not find its sibling — SHELL_COMMON was not set before the source ($err)" ;;
        '') ;;
        *) fail "$label: unexpected stderr from resolve_repo: $err" ;;
    esac
done

echo "[OK] resolve_repo sets SHELL_COMMON before sourcing gh_host.sh, on both paths"
