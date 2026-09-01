# Constraints — gh-setup:add-ai-metrics operating rules

Operational invariants for the backfill loop. The SKILL.md body points
here instead of restating them inline.

- Always pass `--repo "$TARGET_REPO"` — no implicit repo detection.
- Body byte-identical outside the footer: stripping the new footer must
  yield the original body verbatim. No rewrap, no language change.
- `--force` is **recompute → replace**, never blind overwrite or
  duplicate-append. If no footer exists, `--force` degrades to plain append.
- Continue-on-error: a single card failure never stops the loop.
- Skip path is API-silent — no `gh edit` call, no body diff, **no sleep**.
- Conversation-infer mode rejects bare numbers (`123` without `#`).
- > 100 hits require explicit `y` confirmation; no `--yes` flag.
- `--pace` sleeps **after** each successful modify, **never before**, and
  **never after the last card** — no trailing wait.
- `--dry-run` makes zero `gh edit` calls. `gh view` is still allowed
  (needed to classify will-write vs will-skip vs will-force-replace).
- `--limit` counts only cards that took the modify path (skipped cards
  do not advance the counter — this makes "process N new backfills"
  deterministic across re-runs).
- `--limit` and `--budget` compose with **OR semantics** — whichever
  fires first stops the loop. Stop reason is reported in the summary.
