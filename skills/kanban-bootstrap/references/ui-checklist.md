# UI Checklist — Why workflow #3 is disabled (dEitY719/dotfiles#289)

The 10-item workflow table, the solo-repo hide-columns guidance, and the
smoke-test commands are all printed by `lib/setup.sh`'s `print_final_report` —
that is the single copy; do not reproduce them here. This file exists only for
the one piece of rationale the script's one-line `DISABLE` instruction doesn't
carry.

The issue lifecycle in this SSOT is **3 stages**:
`Backlog → In progress → Done`. Issues do NOT visit `In review` —
that column is exclusively for PRs (`Backlog → In review → Approved
→ Done`).

If workflow #3 (`Pull request linked to issue`) stays enabled, GitHub
auto-moves an Issue card to `In review` the moment a PR links to it (via
`Closes #N`), which contradicts the 3-stage lifecycle. The skill / script
tells the user to **disable** this workflow.

`_gh_project_status_sync` (the board-sync helper this family uses)
includes a correction guard (`--only-from "Backlog,Ready,In review"`)
that re-moves Issue cards from `In review` back to `In progress` even
if workflow #3 was left enabled, but the explicit disable removes the
ambiguity entirely.
