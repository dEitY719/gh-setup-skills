# Post-hoc Metric Estimation

When `gh-setup:add-ai-metrics` retrofits a card that was created before the
auto-capture pipeline (dEitY719/dotfiles#317 / dEitY719/dotfiles#320) existed, the original Claude session
is gone. The values written to the footer are therefore estimates derived
from the card's static content. This document defines those rules so they
stay deterministic across re-runs.

## Inputs (per card)

- `title` — first line of `gh {issue,pr} view --json title`
- `body` — `--json body`, raw from the API. May or may not contain a
  prior `<!-- ai-metrics -->` footer; the strip step below is always
  applied first so downstream computations see only the user-authored
  portion.

## Always-strip step (must precede TOKENS)

The TOKENS character count must come from the body **without** any
existing footer; otherwise a `--force` re-run inflates the count by the
length of the previous footer (~150 chars), feeding back into a slowly
growing token estimate. The strip is also a no-op when no footer
exists, so it is safe to run unconditionally.

Implemented as `strip_footer` in [`lib/ai-metrics.sh`](../lib/ai-metrics.sh).

Regex notes:

- `\n+---\n` matches one or more leading newlines + the `---` separator
  on its own line. Tolerates both append conventions in the wild —
  PR dEitY719/dotfiles#320's `\n---\n` (single) and `gh-issue-create`'s `\n\n---\n`
  (double) — without leaving a stray newline behind in either case.
- `(?:<details>\n<summary>[^\n]*</summary>\n\n)?` optionally matches the
  new `<details>` wrapper prefix introduced in issue dEitY719/dotfiles#367.
- `<!-- ai-metrics(?::[A-Za-z0-9_-]+)? -->` matches both the colonless
  form and the suffixed form (`<!-- ai-metrics:gh-pr -->`).
- `.*?` non-greedy + the `s` flag scopes the match to the nearest
  closing marker.
- `(?:\n\n</details>)?` optionally matches the closing `</details>` tag.

## TOKENS

```
TOKENS = max(1000, round_to_500((len(title) + len(stripped)) / 4))
```

- Character count (not byte count); `wc -m` for safety on multibyte
  Korean text.
- Round to nearest 500 to match `references/metrics-baseline.md`
  Token Estimation rules.
- Floor at 1000 — anything smaller is noise.

Bash (consumes `$stripped` from the always-strip step above):

Implemented as `estimate_tokens` in [`lib/ai-metrics.sh`](../lib/ai-metrics.sh).

It consumes the stripped body from `strip_footer`.

## HUMAN_H

Lookup by conventional-commit prefix in the title. The prefix is the
first `[a-z]+` group before an optional `(scope)` and a literal `:`.

Implemented as `title_prefix` in [`lib/ai-metrics.sh`](../lib/ai-metrics.sh).

An absent or unparseable prefix falls back to `misc`.

Mapping — the SSOT is the "Human Time Lookup Table" in
[`references/metrics-baseline.md`](metrics-baseline.md). Do not duplicate it
here; load that file and read the row for `prefix`, falling back to `misc`
(2 h) when the prefix is absent or unlisted.

For `feat`, sizing requires conversation context that is unavailable
post-hoc. Default to **medium** (8 h) unconditionally. Users who want a
sharper number can pass `--force` after manually editing the card title
(out of scope for this skill).

## ELAPSED

```
ELAPSED = max(1, round(HUMAN_H * 0.05 * 60)) / 60   # in hours, but printed as min
```

Equivalently, in minutes:

Implemented as `human_hours` / `estimate_elapsed` in [`lib/ai-metrics.sh`](../lib/ai-metrics.sh).

`human_hours` parses the lookup table out of
[`references/metrics-baseline.md`](metrics-baseline.md) at run time rather than
carrying a second copy of it.

The 5% factor reflects the observed ratio in dEitY719/dotfiles#320's own footer
(`👤 ~8 h · 🤖 ~15 min` ≈ 3.1%, rounded up for safety) and is intentionally
conservative — better to over-report AI cost than under-report.

## Determinism

Given the same `(title, body)` and the same lookup table, all three
metrics are pure functions of the inputs. This makes `--force` runs
idempotent at the value level: re-running without changing the card
content produces the same numbers, so the resulting body diff is empty.

## Why not call the Claude API directly?

The skill description explicitly excludes live API queries (Non-Goal
in issue dEitY719/dotfiles#324). Reasons:

1. The original conversation is unrecoverable — no API can answer
   "how many tokens did Claude use to draft this card on date X."
2. Token-counter access requires an API key + per-skill billing config,
   which is out of scope for a footer-backfill utility.
3. Heuristic estimates are more honest than fabricated precision.
