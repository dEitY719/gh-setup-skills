---
name: label-bootstrap
description: >-
  Sync a GitHub repo's labels to the standard 10-label SSOT. Use for
  /gh-setup:label-bootstrap, "라벨 동기화", "SSOT 라벨 적용",
  "sync repo labels". Labels only — the Projects v2 board is
  gh-setup:kanban-bootstrap.
allowed-tools: Bash, Read, Grep
license: MIT
compatibility:
  network: required
metadata:
  model_recommendation:
    tier: haiku
    reason: "structured, deterministic label sync; wraps lib/label-bootstrap.sh, bounded output, low reasoning"
    claude: prefer
    non_claude: advisory-only
---

# gh-setup:label-bootstrap — GitHub Label SSOT Sync

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Step 1: Resolve Skill Dir

The script lives at `${SKILL_DIR}/lib/label-bootstrap.sh`. The label SSOT
it parses is `${SKILL_DIR}/references/gh-labels.md`, co-located inside this
skill (the script resolves this as a sibling of `lib/`) — this keeps the
skill self-contained for standalone distribution.

## Step 2: Target Repo

Pass `--repo <owner/repo>` through if the user gave one. Otherwise the
script auto-resolves via `gh repo view` (single-repo policy — never prompt
for remote selection).

## Step 3: Dry-run First

```
bash "${SKILL_DIR}/lib/label-bootstrap.sh" --dry-run <user-flags>
```

Print the plan (rename / PATCH / POST / prune candidates). On non-zero
exit → abort (quote the script's first stderr line). Never proceed to the
real run if the dry-run failed.

## Step 4: Real Run

```
bash "${SKILL_DIR}/lib/label-bootstrap.sh" <user-flags>
```

Surface each applied action. Per-label API failures warn on stderr and
continue — a single label's failure never aborts the run.

## Behavior notes

- **Force-sync, no skip mode**: every existing SSOT label is PATCHed to
  the canonical color/description unconditionally. This is an intentional
  change from the old `gh-setup:kanban-bootstrap` inline logic (which skipped
  existing labels unless `--force-label-sync`); see F-3 of issue dEitY719/dotfiles#1226.
- **3 alias renames preserve links**: `bug`->`fix`,
  `documentation`->`docs`, `build`->`chore` are renamed via
  `PATCH new_name=`, never delete+recreate, so issues/PRs keep the label.
- **`--prune` is opt-in**: without it, no label is ever deleted. With it,
  only labels outside (SSOT ∪ pipeline ∪ alias-targets ∪ allowlist) are
  deleted, computed AFTER renames (NF-1 in dEitY719/dotfiles#1226).
- **2 pipeline-state labels** (`review-blocked` / `review-passed`, dEitY719/dotfiles#1564)
  come from a separate `pipeline|name|color|description` feed in the same
  SSOT file. They are provisioned like the base 10 and preserved by
  `--prune`, but stay out of the 10-label set: they are pipeline state, not
  issue classification, and have no aliases. Without them
  `gh-verify:review-all` cannot issue a verdict and `gh-pr:merge-train` skips
  every PR.

## Constraints

- Never mutate the script's behavior — wrap, don't rewrite.
- `--dry-run` must make zero POST/PATCH/DELETE API calls.
- Never delete a label unless `--prune` was explicitly passed.
- The 10-label + alias + pipeline SSOT lives only in
  `references/gh-labels.md` — do not hardcode a second copy here or in the
  script.
- `lib/label-bootstrap.sh` is the sole entry point; invoke it directly
  from non-Claude contexts:
  `bash skills/label-bootstrap/lib/label-bootstrap.sh [...]`.

## Related Skills

Same new-repo setup slot, different artifact — `gh-setup:kanban-bootstrap` (Projects v2
board; delegates its label step here) · `gh-setup:docs-bootstrap` (docs/ tree).
