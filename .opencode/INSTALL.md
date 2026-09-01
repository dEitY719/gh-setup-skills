# Installing gh-setup for OpenCode

## Prerequisites

- [OpenCode.ai](https://opencode.ai) installed
- An authenticated `gh` CLI with write access to the repo you are bootstrapping
- For `kanban-bootstrap`: the `project` token scope
  (`gh auth refresh -h <host> -s project`) and `jq`
- `docs-bootstrap` needs neither — a shell and a writable directory is enough

## Installation

Add the plugin to the `plugin` array in your `opencode.json` (global or
project-level):

```json
{
  "plugin": ["gh-setup-skills@git+https://github.com/dEitY719/gh-setup-skills.git"]
}
```

Restart OpenCode. The plugin installs through OpenCode's plugin manager and
registers all four skills.

OpenCode uses its own plugin install. If you also use Claude Code, Codex, or
another harness, install this plugin separately for each one.

## Usage

Use OpenCode's native `skill` tool:

```
use skill tool to list skills
use skill tool to load label-bootstrap
```

## Tool mapping

The authoritative OpenCode tool mapping for every `dEitY719/*-skills` repo lives
in the sibling repo `harness-skills`, at
[`references/opencode-tools.md`](https://github.com/dEitY719/harness-skills/blob/main/references/opencode-tools.md).
This repo owns no copy — one tool rename must stay one edit. Read it when a
skill names a tool you do not recognise. Short version:

- "Read a file" -> `read`
- "Create a file" / "edit a file" -> `apply_patch`
- "Run a shell command" -> `bash`
- "Search file contents" / "find files by name" -> `grep`, `glob`
- "Create a todo" -> `todowrite`
- "Dispatch a subagent" -> `task` with `subagent_type: "general"` (or
  `"explore"` for read-only exploration)
- "Invoke a skill" -> OpenCode's native `skill` tool

Two things to know here:

- Everything these skills do is a `gh` CLI call, a `lib/*.sh` script, or a file
  write. None of them uses Claude Code's `Skill()`, `WebFetch`, or
  `AskUserQuestion`, so there is no capability to substitute.
  `kanban-bootstrap` reaches its sibling by running
  `skills/label-bootstrap/lib/label-bootstrap.sh` with `bash` — a plain shell
  call. Run the `lib/*.sh` helpers and pass their `[OK]` / `[FAIL]` lines and
  dry-run plans through verbatim; do not reimplement them.
- OpenCode has no structured question tool. Two steps need a real answer:
  `kanban-bootstrap` asks once whether to hide the reserved columns when the
  repo looks personal, and `add-ai-metrics` asks
  `Continue with N cards? [y/N]:` above 100 cards. Ask in the conversation and
  wait for a reply. An auto-approve session setting is not the user's answer.

## Safety contracts

- `label-bootstrap` never deletes a label unless `--prune` is passed; without it
  the prune step is skipped entirely. `--dry-run` makes zero mutating API calls.
  Alias renames preserve the label on every issue already carrying it.
- `kanban-bootstrap` targets `origin` only, never falls back to another remote,
  and never prints a token, a collaborator list, or a project ID. It does not
  run the smoke test without `--with-smoke-test`.
- `docs-bootstrap` is dry-run by default, writes only on `--apply`, never
  migrates a populated `docs/`, and never overwrites `docs/README.md` without
  `--force`.
- `add-ai-metrics` is idempotent — it skips a card that already has an
  `<!-- ai-metrics -->` block and never modifies bytes outside that block.

## Troubleshooting

### Plugin not loading

1. Check logs: `opencode run --print-logs "hello" 2>&1 | grep -i gh-setup`
2. Verify the plugin line in your `opencode.json`
3. Make sure you are running a recent version of OpenCode

### Skills not found

1. Use the `skill` tool to list what was discovered
2. Check that the plugin is loading (see above)

### kanban-bootstrap aborts on a prereq check

The most common cause is a missing `project` token scope. Run
`gh auth refresh -h <host> -s project` and retry — the skill prints the exact
hint before it aborts. `--repo` alone names no server, so the skill also needs
`origin` to resolve to a host it can reach.

## Getting Help

Report issues: https://github.com/dEitY719/gh-setup-skills/issues
