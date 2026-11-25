# Architecture Decision Records (ADR)

An ADR is not a rule. It is the **record of a decision**: what was decided, and why.

## When to write one

- When you make a decision that is expensive to reverse: structure, dependencies, data formats, public interfaces, operating policy.
- To change established behavior, **update the ADR first**. The code does not change ahead of the record.
- No decision, no ADR. ADRs are not a log of work done.
- Adopting ADRs late in a project is fine. Do not backfill; start with the next decision.

## File names and numbers

- `NNNN-<kebab-slug>.md`. Four-digit numbers, starting at `0001`.
- A new number is **the highest existing number + 1**. Never pick one by hand: parallel branches collide when they merge.
- If two ADRs end up sharing a number after a merge, the later one takes a new number.

## Skeleton

Copy `NNNN-template.md` (MADR layout).

- **Title** — the decision as one declarative, present-tense sentence. Example: "Configuration lives in a single YAML file".
- **Status** — `Accepted — YYYY-MM-DD.` and the decision owner. Supersession is recorded here too.
- **Context** — the forces at play and the issue (#N) that raised the question.
- **Decision** — the decision itself, with links.
- **Considered Options** — the options you rejected, and why, as a table.
- **Consequences** — what becomes easier or harder; related docs and ADRs.

## Superseding a decision

When a decision changes, do not rewrite the old ADR. Write a new one.

- New ADR status: `Accepted — YYYY-MM-DD. Supersedes 0030.`
- Old ADR: add exactly one line at the end of its status section, `Superseded by 0031 — YYYY-MM-DD.` Leave everything else as it is.

## Tooling

This folder was set up with `/gh-setup:adr-bootstrap`. Every writing mode prints a plan unless `--apply` is passed.

- `/gh-setup:adr-bootstrap new "<title>"` — create the next-numbered ADR.
- `/gh-setup:adr-bootstrap supersede <number> "<new title>"` — create a new ADR and record the supersession in the old one.
- `/gh-setup:adr-bootstrap --check` — find duplicate numbers, bad file names, missing status sections and broken supersede references. Read-only.
