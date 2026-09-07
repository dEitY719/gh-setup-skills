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
real run if the dry-run failed. Ends with a `Summary:` line and an
`[OK]`/`[FAIL]` verdict (see Step 4 for the shape) — a dry-run always
verdicts `[OK]` since it never mutates.

## Step 4: Real Run

```
bash "${SKILL_DIR}/lib/label-bootstrap.sh" <user-flags>
```

Surface each applied action. Per-label API failures warn on stderr and
continue — a single label's failure never aborts the run, but each one
counts toward `failed=` in the closing summary, which verdicts `[FAIL]`
(non-zero exit) whenever `failed > 0`:

```
Target repo: dEitY719/example
rename label 'bug' -> 'fix' (sync color/desc)
POST label 'skill' (color=d97757)
Prune skipped (--prune not set) — no labels deleted.
Summary: renamed=1 created=1 synced=8 pruned=0 failed=0
[OK] Labels synced to SSOT for dEitY719/example
```

End with a `Next:` line: after a dry-run, `Next: re-run without --dry-run
to apply.`; after a real run, `Next: gh label list --repo <owner/repo>` to
verify, or `/gh-setup:kanban-bootstrap` to set up the board.

Force-sync semantics (every existing SSOT label is PATCHed unconditionally,
no skip mode), the 3 alias renames, the `--prune` set algebra, and the 2
pipeline-state labels are documented in `references/help.md`; the label
feed itself is `references/gh-labels.md`.

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
