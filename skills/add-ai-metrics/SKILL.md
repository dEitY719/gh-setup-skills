---
name: add-ai-metrics
description: >-
  Retrofit the ai-metrics footer onto GitHub Issues/PRs that predate
  automatic capture. Use for /gh-setup:add-ai-metrics,
  "기존 이슈/PR 에 메트릭 소급 부착", "backfill ai-metrics". Backfill only —
  new cards get the footer automatically.
allowed-tools: Bash, Read, Grep
license: MIT
metadata:
  model_recommendation:
    tier: haiku
    reason: "metadata backfill; wraps lib/ai-metrics.sh, bounded output, low reasoning"
    claude: prefer
    non_claude: advisory-only
---

# gh-setup:add-ai-metrics — Retrofit ai-metrics footer onto past Issues/PRs

Backfills the `tokens · human-h · ai-min` footer onto cards created before
issue dEitY719/dotfiles#317 / PR dEitY719/dotfiles#320 made capture automatic. Idempotent — a card already
carrying an `<!-- ai-metrics -->` block is skipped, and bytes outside that
block are never modified. Full flag / call-pattern table: `references/help.md`.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Step 1: Resolve Skill Dir

Everything executable lives at `${SKILL_DIR}/lib/ai-metrics.sh` — date
parsing, footer detection, the metric estimates, pacing and the per-card
loop. Wrap it; do not re-derive its logic here. It reads the Human Time
Lookup Table from `${SKILL_DIR}/references/metrics-baseline.md` as a
sibling of `lib/`, so the skill stays self-contained.

## Step 2: Build the Argument List

Pass the user's flags through unchanged. The script owns validation and
prints the error itself (`--type` values, `--date` forms, duration shapes,
the `--date`/positional mutex, an unresolvable `--remote`).

The one thing the script cannot do is read the conversation. When the user
gave neither positional cards nor `--date`, resolve targets first:

- Scan recent turns for `#NNN` paired with an `issue`/`PR`/`pr` cue — bare
  numbers are ignored. Pass what you find as `issue#N` / `pr#M`.
- Nothing found → stop with
  `Error: no issue/PR references in conversation; pass them explicitly.`

## Step 3: Dry-run First

```
bash "${SKILL_DIR}/lib/ai-metrics.sh" --dry-run <user-flags>
```

Print the classification rows (`· will-write` / `· will-force-replace` /
`· will-skip`) and the `DRY RUN:` summary block verbatim. Zero `gh edit`
calls happen here. Non-zero exit → abort and quote the script's first
stderr line; never proceed to the real run after a failed dry-run.

If the run stops on the 100-card threshold, relay
`Continue with N cards?` to the user and re-invoke with `--confirm-large`
only after they actually answer yes.

## Step 4: Real Run + Report

```
bash "${SKILL_DIR}/lib/ai-metrics.sh" <user-flags>
```

Surface every per-card line (`[OK]` / `[REPLACED]` / `[SKIP]` / `[FAIL]`)
and the closing report verbatim: the `Summary:` counters, the
`[ai-metrics:...]` context line, and — when `--limit` or `--budget` fired —
the `Stopped early: …; Re-run to resume (idempotent).` line. A per-card
failure never aborts the loop, so do not stop on one.

## Constraints

Operating invariants live in
[`references/constraints.md`](references/constraints.md); `lib/ai-metrics.sh`
enforces them. Two rules bind this wrapper:

- Never mutate the script's behavior — wrap, don't rewrite, and never
  swallow a `[FAIL]` line to keep an exit code clean.
- `lib/ai-metrics.sh` is the sole entry point; invoke it directly from
  non-Claude contexts:
  `bash skills/add-ai-metrics/lib/ai-metrics.sh [...]`.

## Related Skills

`gh-issue:create` / `gh-pr:create` write the same footer at creation time — this skill only fills the gap for cards that predate them.
