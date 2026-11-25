# ADR conventions — why the skill works this way

Load this when a user asks why a rule exists, or when a case is not covered by
`help.md`.

## Source practice

The default `ko` form comes from a production repo with 42 ADRs in
`docs/adr/NNNN-<slug>.md`. Each title is a present-tense declarative sentence,
and each body has the same five sections: 상태, 결정, 이유, 기각한 안, 결과. When
a new ADR replaced an old one, the old ADR's status section recorded it (0030
to 0031, 0034 to 0040). The `en` form maps the same slots onto MADR.

## What an ADR is for

- An ADR records a **decision** and its reasons. It is not a rule book and not
  a contribution log.
- Write one at the moment a decision is made that would be expensive to
  reverse. No decision, no ADR.
- To change established behavior, update the ADR first.
- A project that adopts ADRs late does not backfill old decisions. It starts
  with the next one. That is why `scaffold` works on any repo state and `new`
  simply continues from the highest number present.

## Why numbering is automated

That repo had three duplicate-number accidents: 0002, 0019 and 0034 each
appeared twice. Parallel branches each picked "the next number" by hand and
then merged. Nothing checked for it. So:

- `new` and `supersede` always use highest existing + 1, so nobody picks a
  number by hand.
- That alone does not stop two branches from each taking the same next
  number. Run `--check` before merging an ADR branch (or in CI): finding 1
  catches the collision while it is still cheap to renumber.
- `--check` finding 1 reports duplicates. The self-test pins this with a
  synthetic duplicate fixture.
- Fixing a duplicate is a human decision (which one renumbers, which links to
  update), so `--check` only reports it.

## Why English slugs

File names stay ASCII so they are safe in URLs, shells and every tool's path
handling. The body can be any language. For a Korean title, the agent proposes
an English slug, and the dry-run shows it before anything is written.

## Why supersede touches the old file at all

Decision records are immutable: the reasoning was true when it was written.
But a reader who lands on the old ADR must learn it is no longer current. One
appended status line does that without rewriting history. Editing the old body
stays a human choice.

## Relationship to docs-bootstrap

`gh-setup:docs-bootstrap` creates `docs/adr/.gitkeep` and nothing else; its
contract is empty folders only. This skill adds the living system on top:
rules, template, numbering, supersession, audit. It never removes the
`.gitkeep`.
