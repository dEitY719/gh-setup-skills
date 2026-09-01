# gh-setup — skill index

Four one-time repo-initialization skills. Each lives in this extension's
`skills/` directory. They are explicitly invoked, never ambient: load the one
that matches the request by reading its `SKILL.md`, then follow it. Do not load
all four.

| Skill | Read | Use when |
|-------|------|----------|
| `label-bootstrap` | `@./skills/label-bootstrap/SKILL.md` | Syncing a repo's labels to the 10-label SSOT. Labels only — the board is `kanban-bootstrap`. |
| `kanban-bootstrap` | `@./skills/kanban-bootstrap/SKILL.md` | Standing up the Projects v2 kanban board for a repo. Also runs the label step by delegating to `label-bootstrap`. |
| `docs-bootstrap` | `@./skills/docs-bootstrap/SKILL.md` | Scaffolding the standard kind-split `docs/` tree into an empty or new repo. Never for migrating a populated `docs/`. |
| `add-ai-metrics` | `@./skills/add-ai-metrics/SKILL.md` | Backfilling the ai-metrics footer onto Issues/PRs that predate automatic capture. New cards get it automatically — this is the gap-filler only. |

Each skill's `references/` directory holds the detail it loads on demand, and
three of the four keep their deterministic steps in `lib/*.sh`. `SKILL.md` says
which file to read and which script to run, and when. Do not read `references/`
up front, and do not reimplement `lib/` in prose.

## What each skill needs

- **`label-bootstrap`, `add-ai-metrics`** — an authenticated `gh` CLI with write
  access to the target repo. `label-bootstrap` resolves the repo from `--repo`
  or `gh repo view`; `add-ai-metrics` resolves it from the git remote and stops
  if there is none, rather than falling back silently.
- **`kanban-bootstrap`** — `gh` with the `project` token scope
  (`gh auth refresh -h <host> -s project`) and `jq`. It always targets `origin`,
  derives `$HOST` from that remote's URL, and carries `GH_HOST` on every call:
  `--repo` alone names no server.
- **`docs-bootstrap`** — nothing but a shell and a writable directory. No
  network, no `gh`. Its `--help` path does not touch the filesystem at all.

## Tool mapping for Gemini CLI

The skills speak in actions. On Gemini CLI these resolve to:

- "Read a file" -> `read_file` / `read_many_files`
- "Create a file" / "edit a file" -> `write_file`, `replace`
- "Run a shell command" -> `run_shell_command` (this is how every `lib/*.sh`
  helper and every `gh` call is made)
- "Search file contents" -> `grep_search`
- "Find files by name" -> `glob`
- "Create a todo" -> `write_todos`
- "Ask the user" -> `ask_user`
- "Dispatch a subagent" -> `invoke_agent` with `agent_name: "generalist"`

The full mapping, including every capability gap and its workaround, lives in
the sibling repo: `https://github.com/dEitY719/harness-skills/blob/main/references/gemini-tools.md`.
This repo owns no copy. Read it when a skill names a tool you do not recognise.
On Antigravity read `antigravity-tools.md` in that same directory instead —
`agy` shares `~/.gemini` but not Gemini CLI's tool names.

## Capability gaps on Gemini CLI

- There are none of the usual ones. No skill here uses Claude Code's `Skill()`,
  `WebFetch`, or `AskUserQuestion`. `kanban-bootstrap` reaches its sibling by
  running `skills/label-bootstrap/lib/label-bootstrap.sh` through
  `run_shell_command` — a plain shell call, not a skill invocation.
- The `lib/*.sh` helpers are plain bash with no external UX library and run
  unchanged under `run_shell_command`. Pass their `[OK]` / `[FAIL]` lines and
  their dry-run plans through verbatim rather than summarising them.
- Two steps need a real answer from the user: `kanban-bootstrap`'s hide-columns
  question and `add-ai-metrics`'s `Continue with N cards? [y/N]:`. Use
  `ask_user`. On Antigravity `ask_user` does not exist — ask in the conversation
  and wait for a real reply. An auto-approve session setting is not the user's
  answer.

## Safety rules

- `label-bootstrap` **never deletes a label unless `--prune` was passed.**
  Without it the prune step is skipped entirely. Alias renames go through
  `PATCH new_name=`, never delete-then-recreate, so issues keep their labels.
  `--dry-run` makes zero mutating API calls. The SSOT is
  `skills/label-bootstrap/references/gh-labels.md` and nowhere else.
- `kanban-bootstrap` targets `origin` only — never prompt for a remote, never
  fall back to another one. Never print a token, a collaborator list, or a
  project ID. Ask before hiding columns on a personal-looking repo instead of
  inferring it from the collaborator count. Never run the smoke test without an
  explicit `--with-smoke-test`.
- `docs-bootstrap` is `--dry-run` by default and writes only on `--apply`. It
  never migrates a populated `docs/`, never authors document bodies beyond
  `docs/README.md`, and never overwrites that README without `--force`.
- `add-ai-metrics` is idempotent: skip any card already carrying an
  `<!-- ai-metrics -->` block, and leave every byte outside that block
  untouched. Always pass `--repo`. A per-card failure is logged and the loop
  continues; `--limit` and `--budget` stop it early and print a resume hint.
