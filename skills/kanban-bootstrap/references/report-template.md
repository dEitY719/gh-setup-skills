# Step 7 — appended output

Pass through the script's `print_final_report` verbatim (host-aware URLs,
`[OK]`/`[FAIL]` line, and the workflow #3 `DISABLE` instruction), then append
the smoke-test command block (host-corrected; do not execute unless
`--with-smoke-test`) and a compact closing report in this literal shape:

```
[OK] Kanban board ready — <OWNER>/<REPO>
  Labels:  <n> created, <m> synced, <k> skipped
  Elapsed: <mm>m<ss>s
Next: apply the UI workflow settings above, then run the smoke test.
```

Board URL and project number are already in `print_final_report`'s own
"Project" section moments earlier — do not repeat them here.

`Elapsed` is `$(date +%s) - START_TS` (Step 1), formatted `<mm>m<ss>s`. Omit
the `Labels:` line entirely when `--no-bootstrap-labels` was passed. On the
idempotent "already exists" re-run (Step 6), skip this block — the script's
own `[OK] ... already exists ...` line and existing-project URLs are the
whole report.
