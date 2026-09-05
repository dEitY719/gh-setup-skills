# gh-setup:kanban-bootstrap — Help

Bootstrap a GitHub Projects v2 kanban board for the current repo.
Wraps the single SSOT script at `lib/setup.sh` with prereq checks,
label bootstrap, and host-aware UI checklist.

## Usage

```
/gh-setup:kanban-bootstrap [--owner <login>] [--repo <name>] [options]
```

## Options (skill-layer)

| Option | Description | Default |
|---|---|---|
| `--no-bootstrap-labels` | Skip the label registration step (target repo follows a different label policy) | labels bootstrapped |
| `--force-label-sync` | Back-compat **no-op** (dEitY719/dotfiles#1226): `gh-setup:label-bootstrap` now always force-syncs SSOT label colors/descriptions, so this flag has no effect. Accepted silently. | inert |
| `--with-smoke-test` | Execute the smoke test commands instead of only printing them | print-only |
| `-h`, `--help`, `help` | Print this help and stop. No API calls. | — |

## Options (passed through to `lib/setup.sh`)

| Option | Description | Default |
|---|---|---|
| `--owner <login>` | GitHub user or org | auto from `gh repo view` |
| `--repo <name>` | Repository name | auto |
| `--title <board-title>` | Project title | repo name |
| `--auto-archive-window <dur>` | Done auto-archive filter | `2d` |
| `--hide-columns` | Add solo-repo hide guidance for `Approved` and `Ready` | off |
| `--dry-run` | Print the plan without mutations | off |
| `--skip-pr-template` | Skip remote PR template creation/check | off |

## Prerequisites

- `gh` CLI installed and authenticated.
- `jq` installed.
- Token has `project` scope. Refresh with:
  `gh auth refresh -h <host> -s project`.

## What the skill does

1. Checks `gh` / `jq` + `project` scope (rc=1 on miss).
2. Resolves target repo (always `origin` — single dotfiles policy).
3. Delegates label bootstrap to `gh-setup:label-bootstrap`, which force-syncs
   the 10 SSOT labels (`feat`, `fix`, `docs`, `refactor`, `test`, `ci`,
   `chore`, `skill`, `TODO`, `reference`) per
   `../label-bootstrap/references/gh-labels.md`
   and renames the 3 alias labels (`bug`->`fix`, `documentation`->`docs`,
   `build`->`chore`) — idempotent.
4. Dry-runs `lib/setup.sh`. Aborts if dry-run fails.
5. Real-runs `lib/setup.sh`. Captures Project URL and number.
6. Prints the host-aware UI checklist with workflow #3 disable
   guidance (per SSOT decision dEitY719/dotfiles#289) and the smoke test commands.

## Re-run safety

If a board with the same title already exists, `lib/setup.sh` exits
cleanly with rc=0 and the existing URL. The skill surfaces this as
"이미 보드가 있어 재셋업을 건너뜁니다".

## Single SSOT note

The script `lib/setup.sh` (relocated from its former scripts/ location
in issue dEitY719/dotfiles#699) lives only inside this skill. Invoke it directly from
non-Claude-Code contexts:
`bash skills/kanban-bootstrap/lib/setup.sh [...]`.

## Related

- SSOT: `docs/.ssot/github-project-board.md` (a `dEitY719/dotfiles`-internal document — not shipped with this plugin)
- Label SSOT: `../label-bootstrap/references/gh-labels.md` (delegated to `gh-setup:label-bootstrap`)
- Playbook: `docs/guide/playbooks/kanban-board-setup.md`
- Decision: dEitY719/dotfiles#289 (3-stage issue lifecycle, workflow #3 disabled)
