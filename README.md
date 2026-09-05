# gh-setup-skills

Four skills for one-time GitHub repo initialization — the ones you run once,
when standing up a new repo, rather than on every commit. Sync its labels to the
10-label SSOT, create and wire the Projects v2 kanban board, scaffold the
standard `docs/` tree, and backfill the ai-metrics footer onto cards that
predate automatic capture. Packaged as a single plugin named `gh-setup`,
installable on six coding-agent harnesses.

Unlike its sibling [`harness-skills`](https://github.com/dEitY719/harness-skills),
this repo owns no shared assets — it links out for the
[per-harness tool mappings and the CI workflow](#shared-assets).

## Skills

| Skill | Invoke | What it does |
|-------|--------|--------------|
| `label-bootstrap` | `/gh-setup:label-bootstrap [--repo <owner/repo>] [--dry-run] [--prune]` | Force-syncs the 10-label SSOT's colors and descriptions onto a repo, renames the 3 alias labels (`bug`->`fix`, `documentation`->`docs`, `build`->`chore`) in place so existing issues keep them, and provisions the 2 pipeline-state labels. Deletes nothing unless `--prune`. |
| `kanban-bootstrap` | `/gh-setup:kanban-bootstrap [--owner <login>] [--repo <name>] [options]` | Creates the Projects v2 board, links the repo, replaces the Status options with the 6-column workflow, sets the auto-archive window, and prints the remaining UI checklist. Delegates its label step to `label-bootstrap`. |
| `docs-bootstrap` | `/gh-setup:docs-bootstrap [path] [--check\|--apply\|--dry-run] [--force]` | Scaffolds the 8-leaf kind-split `docs/` tree (`adr`, `product`, `design`, `architecture/{system,features}`, `testing`, `guides`, `public`), a `.gitkeep` per leaf, and one policy `docs/README.md`. Dry-run by default. |
| `add-ai-metrics` | `/gh-setup:add-ai-metrics [<targets>] [--type issue\|PR] [--date <d>] [--pace] [--limit] [--budget] [--dry-run]` | Retrofits the `tokens · human-h · ai-min` footer onto Issues/PRs created before capture was automatic. Idempotent — a card that already has the block is skipped, and bytes outside it are never touched. |

`kanban-bootstrap` and `label-bootstrap` are a pair: the board skill runs the
label skill's `lib/label-bootstrap.sh` in Step 5 rather than carrying its own
inline label logic, so there is one label SSOT and one force-sync policy.
`--no-bootstrap-labels` skips that step.

`add-ai-metrics` is the odd one out in tempo: it is a backfill, run once against
a repo's history, not part of standing a repo up. It is here because it is the
same kind of job — a one-shot pass over a repo, not a per-commit habit.

### Visual guides and worked examples (GitHub Pages)

- `label-bootstrap` — [visual guide](https://deity719.github.io/gh-setup-skills/skill-guides/label-bootstrap.html) · [usage example](https://deity719.github.io/gh-setup-skills/skill-output/label-bootstrap-usage.html) (label SSOT to synced repo labels)
- `kanban-bootstrap` — [visual guide](https://deity719.github.io/gh-setup-skills/skill-guides/kanban-bootstrap.html) · [usage example](https://deity719.github.io/gh-setup-skills/skill-output/kanban-bootstrap-usage.html) (repo coordinates to a Projects v2 board)
- `docs-bootstrap` — [visual guide](https://deity719.github.io/gh-setup-skills/skill-guides/docs-bootstrap.html) · [usage example](https://deity719.github.io/gh-setup-skills/skill-output/docs-bootstrap-usage.html) (a directory path to a scaffolded docs/ tree)
- `add-ai-metrics` — [visual guide](https://deity719.github.io/gh-setup-skills/skill-guides/add-ai-metrics.html) · [usage example](https://deity719.github.io/gh-setup-skills/skill-output/add-ai-metrics-usage.html) (issue/PR numbers to metrics footers)

Each page is generated from a Markdown source under
[`docs/skill-guides/`](docs/skill-guides) and [`docs/skill-output/`](docs/skill-output).

## Requirements

| Skill | Needs |
|-------|-------|
| `label-bootstrap` | An authenticated `gh` CLI with write access to the target repo. Repo resolves from `--repo`, else `gh repo view`. Missing write permission warns per label and continues rather than aborting. |
| `kanban-bootstrap` | `gh` CLI with the **`project` token scope** (`gh auth refresh -h <host> -s project`) plus `jq`. Always targets `origin`; `$HOST` is derived from `origin`'s URL and carried on every call as `GH_HOST`, because `--repo` alone names no server. |
| `docs-bootstrap` | Nothing but a shell and a writable target directory. No network, no `gh`. `--help` does not even touch the filesystem. |
| `add-ai-metrics` | An authenticated `gh` CLI with write access. Resolves the target repo from the git remote; a missing remote is a stop, never a silent fallback. |

## Install

### Claude Code

```
/plugin marketplace add dEitY719/gh-setup-skills
/plugin install gh-setup@gh-setup-skills
```

### Codex

```
codex plugin install dEitY719/gh-setup-skills
```

### Kimi CLI

```
kimi plugin install dEitY719/gh-setup-skills
```

### Hermes Agent

```
hermes plugins install dEitY719/gh-setup-skills
```

### OpenCode

See [`.opencode/INSTALL.md`](.opencode/INSTALL.md).

### Gemini CLI / Antigravity

```
gemini extensions install https://github.com/dEitY719/gh-setup-skills
```

Antigravity (`agy`) shares `~/.gemini`, so it inherits the install.

## Harness support

These skills are `gh` CLI calls, `lib/*.sh` scripts, and file writes, so they
port cleanly. **None of them uses Claude Code's `Skill()`, `WebFetch`, or
`AskUserQuestion`** — `kanban-bootstrap` reaches its sibling by running
`skills/label-bootstrap/lib/label-bootstrap.sh` directly, which is a plain shell
call, not a skill invocation. Every gap and its workaround is documented per
harness in
[`harness-skills/references/`](https://github.com/dEitY719/harness-skills/tree/main/references);
read the one file for the harness you are on.

| Skill | Claude Code | Codex | Kimi | Gemini / Antigravity | Hermes | OpenCode |
|-------|:-----------:|:-----:|:----:|:--------------------:|:------:|:--------:|
| `label-bootstrap` | full | full | full | full | full | full |
| `kanban-bootstrap` | full | full, confirm in chat | full | full on Gemini, confirm in chat on Antigravity | full, confirm in chat | full, confirm in chat |
| `docs-bootstrap` | full | full | full | full | full | full |
| `add-ai-metrics` | full | full, confirm in chat | full | full on Gemini, confirm in chat on Antigravity | full, confirm in chat | full, confirm in chat |

*confirm in chat* — two steps ask a question before proceeding:
`kanban-bootstrap` asks once whether to hide the reserved columns when the repo
looks personal (it must never infer this from the collaborator count — that is
the privacy rule NF-3), and `add-ai-metrics` asks `Continue with N cards? [y/N]:`
before touching more than 100 cards. Kimi (`AskUserQuestion`) and Gemini CLI
(`ask_user`) have a structured question tool; Codex, Hermes, Antigravity, and
OpenCode do not, so ask in the conversation and wait for a real reply. An
auto-approve session setting is not the user's answer.

The `lib/*.sh` helpers under `label-bootstrap`, `kanban-bootstrap`, and
`docs-bootstrap` are plain bash with no external UX library, and run identically
on every harness. Call them; do not reimplement them. `scaffold.sh` is
deliberately copy-paste safe — it can be run straight from a checkout without
the plugin installed at all:

```
bash skills/docs-bootstrap/lib/scaffold.sh ~/code/my-new-service --apply
bash skills/label-bootstrap/lib/label-bootstrap.sh --repo owner/repo --dry-run
```

## Shared assets

This repo owns none — deliberately.

- **Per-harness tool mappings** live in
  [`harness-skills/references/`](https://github.com/dEitY719/harness-skills/tree/main/references)
  (`{codex,kimi,gemini,antigravity,hermes,opencode}-tools.md`). That repo is
  their sole owner; the other fourteen `*-skills` repos link there rather than
  carrying copies, so one tool rename is one edit, not fifteen
  (dEitY719/dotfiles#1410 F-5 / NF-2). The only condensed mirror here is
  `.kimi-plugin/plugin.json`'s `skillInstructions`, because Kimi CLI cannot read
  a reference file at load time — it points back to the canonical file.
- **The reusable CI workflow** is
  [`harness-skills/.github/workflows/skill-check.yml`](https://github.com/dEitY719/harness-skills/blob/main/.github/workflows/skill-check.yml)
  (dEitY719/dotfiles#1410 D-10). See [CI](#ci).

## Layout

Manifests live at the repo root and all point at one flat `skills/` directory:

```
.
├── skills/{label-bootstrap,kanban-bootstrap,docs-bootstrap,add-ai-metrics}/
│   ├── SKILL.md
│   ├── references/
│   └── lib/                                     (add-ai-metrics has none)
├── .claude-plugin/{marketplace,plugin}.json     Claude Code
├── .codex-plugin/plugin.json                    Codex
├── .kimi-plugin/plugin.json                     Kimi CLI
├── .hermes-plugin/{plugin.yaml,__init__.py}     Hermes Agent
├── .opencode/plugins/gh-setup.js + INSTALL.md   OpenCode
├── .agents/plugins/marketplace.json             Antigravity
├── gemini-extension.json + GEMINI.md            Gemini CLI
├── package.json
├── CLAUDE.md · AGENTS.md -> CLAUDE.md
└── LICENSE
```

Only Claude Code understands a nested `plugins/<name>/skills/` layout. The other
five harnesses resolve manifests at the repo root and a skills tree at
`./skills/`, so this repo keeps everything flat. See [`CLAUDE.md`](CLAUDE.md) for
the full rationale and contribution rules.

Skill directory names dropped their old `gh-` / `devx-` prefixes in the
migration: `/gh-setup:gh-label-bootstrap` stutters, and the plugin namespace
already carries the meaning the prefix used to (dEitY719/dotfiles#1410 F-4). Unlike the
`obsidian-` / `karakeep-` prefixes that `pkm-skills` kept, these named one
service, not two.

The `.kimi-plugin/` manifest is pre-provisioned: Kimi CLI is not installed on the
maintainer's machines yet, and shipping the manifest now costs nothing and saves
a migration later.

## CI

[`.github/workflows/validate.yml`](.github/workflows/validate.yml) calls the
reusable workflow owned by `harness-skills`:

```yaml
jobs:
  validate:
    uses: dEitY719/harness-skills/.github/workflows/skill-check.yml@main
    with:
      plugin-name: gh-setup
      allow-emoji-paths: skills/add-ai-metrics/
```

It validates manifests, skill frontmatter (the `name:` must be bare and match
the directory), progressive-disclosure line limits, the Codex description
budget, version agreement across all seven manifests, shell scripts, and the
no-emoji rule. There is no local copy to keep in sync; a check added upstream
applies here on the next run.

The one `allow-emoji-paths` exemption is `add-ai-metrics`: that skill exists to
write the ai-metrics footer, whose design intentionally uses the chart / person
/ robot glyphs (dEitY719/dotfiles#317 F-2, PR dEitY719/dotfiles#320), and its references quote the footer
verbatim. Stripping them would break the format the skill is defined by. Nothing
else in the repo may carry an emoji.

## Provenance

These skills were extracted from
[`dEitY719/dotfiles`](https://github.com/dEitY719/dotfiles)
(`claude/skills/{gh-label-bootstrap,gh-kanban-bootstrap,gh-add-ai-metrics,devx-docs-bootstrap}`)
as a content snapshot at source commit
`b5f7fd1347e56c9a70e9b67ba15e7c5b7f1cf9ac` — no history rewriting. That
`claude/skills/` path is a historical citation only: the dotfiles copies were
deleted in Phase 4-1 of that repo's migration (commit `ad0d33d5`,
dEitY719/dotfiles#1410 NF-1 / NF-3). Behaviour is unchanged from the snapshot; only the
namespace moved, from `gh:` / `devx:` to `gh-setup:`, and the directory names
lost their now-redundant prefixes.

This is Phase 2 of the dEitY719/dotfiles#1410 migration. `packaging-skills` was Phase 0,
and `harness-skills` was Phase 1 and is the sibling that owns the shared assets
this repo links to.

## License

MIT. See [LICENSE](LICENSE).
