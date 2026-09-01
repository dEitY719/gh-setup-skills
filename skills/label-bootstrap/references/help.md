# gh-setup:label-bootstrap — Help

Sync a GitHub repo's labels to the dotfiles 10-label SSOT
(`references/gh-labels.md`). Generic and reusable on any repo. Wraps the
single SSOT script at `lib/label-bootstrap.sh`.

## Usage

```
/gh-setup:label-bootstrap [--repo <owner/repo>] [--dry-run] [--prune]
```

## Options

| Option | Description | Default |
|---|---|---|
| `--repo <owner/repo>` | Target repository | auto from `gh repo view` |
| `--dry-run` | Print the plan (rename/PATCH/POST/prune) without mutations | off |
| `--prune` | DELETE labels outside SSOT ∪ pipeline ∪ alias-targets ∪ allowlist | off (never deletes) |
| `-h`, `--help`, `help` | Show this help | — |

## What the skill does

1. Parses the plain-feed blocks in `references/gh-labels.md` (10 labels +
   3 alias renames + 2 `pipeline|`-prefixed labels) — the one physical SSOT
   feed. No second hardcoded copy.
2. **Alias renames first**: for `bug->fix`, `documentation->docs`,
   `build->chore`, if the old name exists it is renamed via
   `PATCH .../labels/{old} new_name={new}` (color/description synced in the
   same call). Renaming preserves the label on every issue/PR already
   carrying it — delete+recreate would drop it. If the old name is absent,
   the rename is skipped and the new name is created directly (not an error).
3. **SSOT 10 + pipeline apply**: each of `feat`, `fix`, `docs`, `refactor`,
   `test`, `ci`, `chore`, `skill`, `TODO`, `reference` is PATCHed (color +
   description synced) if it exists, or POSTed if it does not. The two
   pipeline-state labels `review-blocked` / `review-passed` (#1564) join the
   same loop, with their `pipeline|` prefix stripped.
4. **Prune** (only with `--prune`): labels outside
   (SSOT 10) ∪ (pipeline 2) ∪ (alias targets `fix`/`docs`/`chore`) ∪
   (GitHub default allowlist) are DELETEd. Evaluated AFTER renames, so an alias source like
   `bug` is never a false-positive candidate. Without `--prune` this step
   is skipped entirely — no listing, no deletes.

## Behavior difference from the old kanban inline logic

`gh-setup:kanban-bootstrap`'s former inline label step skipped an already-existing
label unless `--force-label-sync` was passed. **This skill always
force-syncs** existing SSOT labels' color and description — there is no
"skip unless forced" mode. If you do not want colors changed, do not run
this skill. This is an intentional, documented change (F-3 of issue #1226).

## Safety

- `--prune` defaults OFF — the tool never deletes a label unless you ask.
- Missing write permission (fork, readonly token) → per-label stderr
  warning, then continue. A single label's failure never aborts the run.
- `--dry-run` makes zero mutating API calls.

## Prune allowlist (always preserved)

`enhancement`, `duplicate`, `good first issue`, `help wanted`, `invalid`,
`question`, `wontfix`.

## Related

- SSOT: `references/gh-labels.md` (labels, aliases, allowlist, prune rule)
- Consumers: `.gh-issue-defaults.yml`, `gh:issue-implement`
  (`GH_ISSUE_BLOCK_LABELS` includes `reference`), `gh:pr` (commit-type map)
- Sibling: `gh-setup:kanban-bootstrap` (delegates its label step to this skill)
- Design: issue #1226
