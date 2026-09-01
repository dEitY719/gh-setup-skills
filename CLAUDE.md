# gh-setup-skills — Contributor Guidelines

This file is the AI context document for this repo. `AGENTS.md` is a symlink to
it, so Claude Code, Codex, Gemini CLI, and every other harness read the same
text. Edit `CLAUDE.md`; never replace the symlink with a second copy.

## What this repo is

A single-plugin skill marketplace. The plugin is named `gh-setup` and it bundles
the four skills you run **once, when a repo is new** — not on every commit:

| Skill | Artifact it creates | Role |
|-------|---------------------|------|
| `label-bootstrap` | GitHub labels | Force-syncs the 10-label SSOT, renames the 3 alias labels in place, provisions the 2 pipeline-state labels. |
| `kanban-bootstrap` | Projects v2 board | Creates the board, links the repo, replaces the Status options with the 6-column workflow, delegates its label step to `label-bootstrap`. |
| `docs-bootstrap` | `docs/` tree | Scaffolds the 8-leaf kind-split tree plus one policy `README.md`. Empty folders only. |
| `add-ai-metrics` | Issue/PR bodies | Backfills the `tokens · human-h · ai-min` footer onto cards created before capture was automatic. |

Three of the four write to a live GitHub repo that already has issues, PRs, and
labels attached to them. That is why every safety contract below is a hard rule
rather than a preference: a bad label prune or a rewritten issue body is not
something the user can undo from the CLI.

The skills were extracted from `dEitY719/dotfiles`
(`claude/skills/{gh-label-bootstrap,gh-kanban-bootstrap,gh-add-ai-metrics,devx-docs-bootstrap}`)
as a content snapshot at source commit
`b5f7fd1347e56c9a70e9b67ba15e7c5b7f1cf9ac` — no history rewriting. The dotfiles
copies remain in place; they are removed in Phase 4 of that repo's migration
plan (#1410 NF-1 / NF-3). This is Phase 2 of dotfiles #1410; `packaging-skills`
was Phase 0 and `harness-skills` was Phase 1 and owns the shared assets.

## Layout: root manifests, one flat `skills/`

This repo deliberately does **not** use the nested `plugins/<name>/skills/`
"mono" layout. Every harness manifest sits at the repo root and points at a
single flat `./skills/` directory:

```
.claude-plugin/{marketplace,plugin}.json   Claude Code
.codex-plugin/plugin.json                  Codex
.kimi-plugin/plugin.json                   Kimi CLI
.hermes-plugin/{plugin.yaml,__init__.py}   Hermes Agent
.opencode/plugins/gh-setup.js              OpenCode
.agents/plugins/marketplace.json           Antigravity
gemini-extension.json + GEMINI.md          Gemini CLI
skills/<name>/SKILL.md                     the skills themselves
```

Only Claude Code understands the nested mono layout. The other five harnesses
resolve manifests at the repo root and a skills tree at `./skills/`, so nesting
would silently cut this plugin down to Claude-Code-only. **Do not move the
manifests under a `plugins/` directory.**

## Shared assets live elsewhere — link, never copy

This repo owns none. Both belong to `dEitY719/harness-skills`:

**1. Per-harness tool mappings** (`references/*-tools.md` there, dotfiles #1410
F-5). Do not create a `references/` directory at this repo's root. If a doc here
needs a mapping, link to
`https://github.com/dEitY719/harness-skills/blob/main/references/<harness>-tools.md`.
One tool rename must stay one edit, not fifteen (NF-2). The single sanctioned
mirror is the condensed summary inside `.kimi-plugin/plugin.json`'s
`skillInstructions`, because Kimi CLI cannot read a reference file at load time;
keep it short and keep it pointing upstream.

**2. The reusable CI workflow** (`.github/workflows/skill-check.yml` there,
D-10). This repo's `validate.yml` calls it with `plugin-name: gh-setup` and one
`allow-emoji-paths` exemption. Do not fork it into a standalone workflow — a
check added upstream should apply here on the next run, which is the whole
point.

## Rules for changing skills

- **Skill directory name is the identity.** `skills/<name>/` must match the
  `name:` field in that skill's `SKILL.md` frontmatter, and that field is the
  **bare** name (`label-bootstrap`), never namespaced (`gh-setup:label-bootstrap`).
  CI fails on a `:` in the name. The harness supplies the `gh-setup:` prefix at
  invocation time.
- **The old `gh-` / `devx-` prefixes are gone and stay gone.** They stuttered
  against the namespace (`/gh-setup:gh-label-bootstrap`), so the migration
  dropped them (#1410 F-4). Do not reintroduce them, and do not shorten the
  remaining names further — `label-bootstrap`, not `labels`.
- **Invocation form in prose is namespaced.** Body text referring to a skill as
  a command writes `/gh-setup:label-bootstrap`. The old dash-form aliases
  (`/gh-label-bootstrap`, `/devx-docs-bootstrap`) were dropped in the migration
  — do not reintroduce them.
- **Cross-repo references keep their own namespace.** `gh:issue-create`,
  `gh:pr`, `gh:issue-implement`, `gh:pr-merge-train`, and `devx:pr-review-all`
  live in other repos of this family. Leave them exactly as written; only the
  four siblings inside `skills/` take the `gh-setup:` prefix. The same goes for
  the `<!-- ai-metrics:gh-pr -->` / `<!-- ai-metrics:gh-add-ai-metrics -->`
  footer markers — those are an interop wire format shared with the `gh:` skills
  that write cards in the first place, not invocation forms, and renaming one
  would break detection of every card already in the wild.
- **Progressive disclosure.** `SKILL.md` stays under 100 lines (CI enforces it)
  and names which `references/` file to read and when. Detail lives in
  `references/`; executable steps live in `lib/`. Do not inline either back into
  `SKILL.md` — `kanban-bootstrap` is one line under the limit and
  `add-ai-metrics` two.
- **Description budget.** CI sums every skill description and fails past 5,440
  characters — Codex's context budget. The current total is 881. Keep new
  descriptions tight anyway.
- **`lib/*.sh` is the contract, not a suggestion.** `label-bootstrap.sh`,
  `setup.sh`, and `scaffold.sh` hold the deterministic half of three of these
  skills. Wrap them, do not rewrite them: surface their `[OK]` / `[FAIL]` lines
  and their dry-run plans verbatim, and never swallow a warning to keep an exit
  code clean. CI shellchecks them at `--severity=warning`.

## Safety contracts

These are acceptance criteria carried over from dotfiles, not advice:

- **`label-bootstrap` never deletes without `--prune`.** Without that flag the
  prune step is skipped entirely — no listing, no deletes. With it, only labels
  outside (SSOT 10 ∪ pipeline 2 ∪ alias targets ∪ the GitHub default allowlist)
  go, and the set is computed **after** the renames so an alias source like
  `bug` is never a false positive. Alias renames use `PATCH new_name=`, never
  delete-then-recreate, so every issue already carrying the label keeps it.
  `--dry-run` makes zero mutating API calls. The label SSOT lives only in
  `skills/label-bootstrap/references/gh-labels.md`; never hardcode a second copy.
- **`kanban-bootstrap` targets `origin` only.** Never prompt for remote
  selection and never silently fall back to a different remote. Never echo a
  token, a collaborator list, or a project ID to stdout (NF-3). Ask once before
  hiding columns on what looks like a personal repo rather than inferring it
  from the collaborator count — that inference is the privacy leak the rule
  exists to prevent. Never run the smoke test without an explicit
  `--with-smoke-test`. Every `gh` call carries `GH_HOST`, because `--repo` alone
  names no server (#1403 / #1407).
- **`docs-bootstrap` defaults to `--dry-run`** and writes only on `--apply`. It
  scaffolds; it never migrates a populated `docs/`, never authors document
  bodies beyond `docs/README.md`, and never overwrites that README without
  `--force`.
- **`add-ai-metrics` is a backfill and must stay idempotent.** A card already
  carrying an `<!-- ai-metrics -->` block is skipped, and bytes outside that
  block are never modified. Always pass `--repo`. `--force` recomputes the
  block, it does not blindly overwrite the body. Per-card failures are logged
  and the loop continues; `--limit` and `--budget` stop it early with a resume
  hint, since the run is idempotent.

## Harness portability

These four are unusually portable: they are `gh` CLI calls, `lib/*.sh` scripts,
and file writes. None of them uses Claude Code's `Skill()`, `WebFetch`, or
`AskUserQuestion` — `kanban-bootstrap` reaches its sibling by running
`skills/label-bootstrap/lib/label-bootstrap.sh` directly, which is a plain shell
call. The only harness-shaped gap is the two confirmation prompts
(`kanban-bootstrap`'s hide-columns question and `add-ai-metrics`'s
`Continue with N cards?`): harnesses without a structured question tool must ask
in the conversation and wait for a real reply. If you add a step that depends on
a Claude-Code-only capability, say so in `README.md`'s harness-support matrix and
open an issue against `harness-skills` so its `references/*-tools.md` gain the
fallback.

## Version bumps

The version appears in seven manifests: `.claude-plugin/marketplace.json`,
`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`,
`.kimi-plugin/plugin.json`, `.hermes-plugin/plugin.yaml`,
`gemini-extension.json`, and `package.json`. CI checks that they agree — bump
all of them together. Versioning is independent per repo (#1410 D-9); this repo
does not move in lockstep with its siblings.

## No emojis

Anywhere in this repo, with exactly one exemption: `skills/add-ai-metrics/`.
That skill exists to write the ai-metrics footer, whose design intentionally
uses the chart / person / robot glyphs (dotfiles #317 F-2, PR #320), and its
references quote the footer verbatim. `validate.yml` declares that subtree via
`allow-emoji-paths`; do not widen the exemption, and do not strip the glyphs
from the footer format to avoid it.
