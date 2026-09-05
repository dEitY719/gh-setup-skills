# AI Metrics Baseline

Maps conventional-commit issue types to estimated junior-developer hours.
It is the SSOT this skill reads when it has to infer `HUMAN_H` for a card that
was created before capture was automatic.

Vendored copy. The table originates in `gh-issue:create`
(`references/metrics-baseline.md` there), which is what writes the footer at
creation time; each skill owns a tailored copy because this plugin ships no
cross-plugin dependency mechanism. Keep the two in sync by hand when the
baseline changes.

## Human Time Lookup Table

| Issue Type      | Human Time  |
|-----------------|-------------|
| `feat` (small)  | 4 h         |
| `feat` (medium) | 8 h (1 d)   |
| `feat` (large)  | 24 h (3 d)  |
| `fix`           | 2 h         |
| `refactor`      | 4 h         |
| `docs`          | 1 h         |
| `chore`         | 0.5 h       |
| `perf`          | 3 h         |
| `test`          | 2 h         |
| `misc`          | 2 h         |

## Size Heuristic for `feat`

Tier is decided by **components × architectural footprint**, with diff weight
as a secondary check. **File count alone never escalates a tier** — see the
pattern-repetition carveout below.

### Signals

| Signal                  | How to measure                                                |
|-------------------------|---------------------------------------------------------------|
| Components touched      | Distinct top-level dirs from `git diff --name-only`. For changes inside a skills tree, count each skill directory (`skills/<skill>/`) as its own component, so a 9-skill cross-cut counts as 9, not 1. |
| Architectural footprint | Explicit NF reqs, cross-system contracts, new public APIs     |
| Diff weight             | `additions + deletions` from `git diff --stat`                |

### Tier rules

- **Large (24 h)** — *all three*: ≥ 3 components, explicit NF or architectural
  decision, total diff > 500 lines.
- **Small (4 h)** — single component, ≤ 2 files, no NF, total diff < 100 lines.
- **Medium (8 h)** — anything else (default for non-trivial `feat`).

### Carveouts

- **Pattern repetition** (same edit replicated across N files): bump down one
  tier (floor at **Small** — never goes lower). Example: PR
  dEitY719/dotfiles#321 changed 11 files to add the same
  `<!-- ai-metrics:* -->` block — **Large** by raw file count, but actually
  **Medium** because the work was one edit ×11.
- **Single component, many files** (≥ 6 files in one top-level dir): stays
  **Medium**. File count alone does not move it to **Large**.

When unsure, default to **medium** (8 h).

### Decision log — KISS over 4-factor scoring (2026-05-05, issue dEitY719/dotfiles#322)

Issue dEitY719/dotfiles#322 proposed a 4-factor weighted score
(file_count × 25% + diff_lines × 25% + components × 25% + ai_judgment × 25%)
with thresholds `< 1.5 → small`, `< 2.5 → medium`, `≥ 2.5 → large`.

**Retroactive comparison on the 5 most recent `feat` PRs**
(dEitY719/dotfiles#325, dEitY719/dotfiles#321, dEitY719/dotfiles#320,
dEitY719/dotfiles#314, dEitY719/dotfiles#301) at issue authorship time:

| PR  | files | diff  | components | 4-factor score | 4-factor tier | Strict-heuristic tier | Match |
|-----|-------|-------|------------|----------------|---------------|-----------------------|-------|
| 325 | 4     | 477   | 1          | 2.00           | medium        | medium                | OK    |
| 321 | 11    | 319   | 1          | 1.75           | medium        | medium                | OK    |
| 320 | 3     | 107   | 1          | 1.75           | medium        | medium                | OK    |
| 314 | 13    | 720   | 1          | 2.25           | medium        | medium                | OK    |
| 301 | 4     | 350   | 3          | 2.25           | medium        | medium (borderline)   | OK    |

Match rate **5/5 = 100 %**, well above the issue's 80 % KISS threshold.
Therefore: **simple boundary clarification adopted, 4-factor scoring not
implemented.** The two real defects in the original heuristic were vagueness
(when do file count and component count disagree?) and missing carveouts
(pattern repetition). Both are addressed by the rules above.

## Token Estimation

Priority order — first available wins:

1. Explicit `--tokens <N>` override passed to the skill
2. Sum character counts of (issue body draft + title + key context), divide by 4, round to nearest 500. Minimum 1 000.
3. Fallback: 5 000

## Block Format

Append after a `---` horizontal rule at the end of the body:

    ---
    <details>
    <summary>🤖 AI Metrics · 📊 ~X tokens · 👤 ~M h · 🤖 ~L min</summary>

    <!-- ai-metrics -->
    📊 ~X tokens · 👤 ~M h · 🤖 ~L min
    <!-- /ai-metrics -->

    </details>

- `X` — estimated tokens (see Token Estimation above)
- `M` — human hours from the lookup table (e.g. `4 h`, `8 h`, `~1 d`)
- `L` — elapsed minutes from skill entry to issue/PR creation
- The `<details>` wrapper collapses the block by default on GitHub,
  keeping the body readable while making metrics accessible on click.
  The HTML comment markers inside are hidden by GitHub's renderer.
