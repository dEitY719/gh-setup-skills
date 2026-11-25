---
name: adr-bootstrap
description: >-
  Install and run an ADR system in docs/adr/: rules README, template,
  numbering, supersede, hygiene check. Use for /gh-setup:adr-bootstrap,
  "ADR 체계 깔아줘", "새 ADR 만들어", "add an ADR". Dry-run unless --apply.
allowed-tools: Bash, Read
license: MIT
metadata:
  model_recommendation:
    tier: haiku
    reason: "Deterministic numbering and file writes live in lib/adr.sh; the skill dispatches, proposes a slug, and reports"
    claude: prefer
    non_claude: advisory-only
---

# gh-setup:adr-bootstrap — ADR records in docs/adr/

All real work lives in `lib/adr.sh` (POSIX sh, `--self-test` built in). The
skill dispatches a mode, proposes an English slug for a non-ASCII title, and
relays the result. It fills the empty `docs/adr/` that
`gh-setup:docs-bootstrap` creates, and works the same with no `docs/adr/` or
an already populated one.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. **No filesystem access.**

## Step 1: Parse Args

Modes: `[path] [scaffold]` (default), `[path] new "<title>"`,
`[path] supersede <number|path> "<title>"`, `[path] --check`. Flags:
`--apply`, `--force` (scaffold only), `--lang ko|en` (default `ko`),
`--slug <kebab>`. Full table: `references/help.md`.

Never add `--apply` on your own. Without it every writing mode is a dry-run.

## Step 2: Slug for a non-ASCII title (new / supersede only)

File names stay English, the body keeps the original title. When the title is
not ASCII, translate its meaning into a short English kebab-case slug
(`[a-z0-9-]`, about 3 to 6 words) and pass it as `--slug`. The script refuses a
non-ASCII title without `--slug`; do not work around that refusal. The
dry-run report shows the proposed slug, so the user confirms it before
`--apply`. Why: `references/conventions.md`.

## Step 3: Run the script

`SKILL_DIR` is this file's directory. Pass the user's args through:

```bash
sh "${SKILL_DIR}/lib/adr.sh" [path] [scaffold|new "<title>"|supersede <ref> "<title>"|--check] [--apply] [--force] [--lang ko|en] [--slug <kebab>]
```

On non-zero exit, stop and quote the script's `[FAIL]` line and any candidate
list it printed. Do not retry, and do not guess another supersede target.
`--check` exits 1 when it finds anything; that is a verdict, not a crash.

## Step 4: Report

Relay the script output verbatim: the `create` / `skip` / `modify` plan, every
file body it printed on a dry-run, `[warn]` findings, and the `[OK]` /
`[FAIL]` line. Example:

```
[INFO] Next number: 0043 (highest existing + 1), slug: api-uses-rest
  create docs/adr/0043-api-uses-rest.md
  ... full file body ...
  modify docs/adr/0031-use-grpc.md (+1 line after line 4, nothing else): 0043 로 대체됨 — 2026-11-25.
[OK] Dry-run complete. Re-run with --apply to write.
```

After a dry-run, end with the exact `--apply` command to run. After
`--apply`, end with `Next:` (`git add docs/adr && git commit`). Never run git
yourself.

## Constraints

- Default to dry-run. Write only on explicit `--apply`.
- Never author ADR bodies. `new` and `supersede` write the template skeleton
  with the title and status line only.
- `supersede` adds exactly one line to the old ADR's status section and
  touches nothing else in that file.
- Never overwrite `docs/adr/README.md` or `NNNN-template.md` without `--force`.
- Never pick an ADR number by hand. The script uses highest existing + 1.
- `--check` is read-only. It never renames or deletes a file.
- No git commands, no network, no `gh`.

## Related Skills

`gh-setup:docs-bootstrap` creates the empty `docs/adr/` this skill fills. Same
new-repo setup slot: `gh-setup:label-bootstrap`, `gh-setup:kanban-bootstrap`.
