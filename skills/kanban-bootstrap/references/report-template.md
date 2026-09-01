# Step 8 — appended output

Pass through the script's `print_final_report` (host-aware URLs + the
workflow #3 `DISABLE` instruction), then append:

- **Smoke test command block** — host-corrected; do not execute unless
  `--with-smoke-test`.
- **Compact closing report** — project URL, project number, label
  bootstrap summary (`<n> created, <m> skipped, <k> synced`), elapsed time.
