---
name: docs-bootstrap
description: >-
  Scaffold the standard kind-split docs/ tree into an empty or new repo. Use
  for /gh-setup:docs-bootstrap, "빈 repo에 docs 폴더 골격
  스캐폴딩", "scaffold docs structure". Creates empty folders only — never
  migrates a populated docs/.
allowed-tools: Bash, Read
license: MIT
metadata:
  model_recommendation:
    tier: haiku
    reason: "Deterministic scaffolder — all logic lives in lib/scaffold.sh; the skill only dispatches and reports"
    claude: prefer
    non_claude: advisory-only
---

# gh-setup:docs-bootstrap — scaffold a kind-split docs/ tree

All real work lives in `lib/scaffold.sh` (self-contained, copy-paste safe).
The skill's job is to dispatch the right mode and relay the result.

Policy: **folder = document kind, feature = filename**. The tree is
`docs/{adr,product,design,architecture/{system,features},testing,guides,public}`
— 8 leaf directories, each carrying a `.gitkeep` so git tracks the empty
folder, plus one `docs/README.md` stating the documentation policy and the
three Docs-as-Code rules (status front-matter, ADR cross-linking, filename
linter). Layout SSOT: `lib/scaffold.sh`; README body SSOT:
`references/docs-readme-template.md`.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. **No filesystem access.**

## Step 1: Parse Args

Positional `[path]` (target repo root, default `.`). Flags: `--dry-run`
(default), `--check`, `--apply`, `--force`. Full table in `references/help.md`.
Mode priority: `--help` > `--check` > `--apply` > `--dry-run`.

Do not re-implement the layout — `lib/scaffold.sh` is the SSOT for the
8 leaf directories and the `docs/README.md` body
(`references/docs-readme-template.md`).

## Step 2: Run the scaffolder

Invoke the script with the parsed args, from the skill's own directory so the
relative template path resolves:

```bash
bash "$(dirname "$0")/lib/scaffold.sh" <path> [--check|--apply|--dry-run] [--force]
```

(When invoked as a skill, pass the user's args through verbatim; the script
parses them itself.)

- **`--dry-run` (default)** — prints the create/skip plan, writes nothing,
  always exits 0.
- **`--check`** — read-only audit; exits 0 if `docs/` already has all 8 leaf
  dirs + `.gitkeep` + `README.md`, non-zero otherwise (use as a CI gate).
- **`--apply`** — `mkdir -p` the tree, `touch` a `.gitkeep` per leaf, write
  `docs/README.md` (skipped if present unless `--force`).

The script is idempotent: existing paths are skipped with a `skip` line.

## Step 3: Report

Relay the script's `[OK]`/`[FAIL]` verdict and the create/skip plan. On
`--apply` success, remind the user the empty folders are tracked via
`.gitkeep` and can be deleted once real docs land. End with a `Next:` hint
(e.g. `git add docs/ && git commit`, or `/gh-setup:kanban-bootstrap` for the board).

## Constraints

- Never author document bodies beyond `docs/README.md` — folders stay empty
  (just `.gitkeep`). Populating PRD/TRD/ADR content is out of scope.
- Never migrate an existing populated `docs/` — this skill only scaffolds.
- Never overwrite `docs/README.md` without `--force`.
- Default to `--dry-run`; only write on explicit `--apply`.

## Related Skills

Same new-repo setup slot, different artifact — `gh-setup:kanban-bootstrap` (Projects v2
board) · `gh-setup:label-bootstrap` (label SSOT sync).
