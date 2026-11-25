# gh-setup:adr-bootstrap — help

Sets up and maintains Architecture Decision Records in `<path>/docs/adr/`.
Every writing mode is a dry-run unless `--apply` is passed.

## Usage

```
/gh-setup:adr-bootstrap [path] [scaffold] [--apply] [--force] [--lang ko|en]
/gh-setup:adr-bootstrap [path] new "<title>" [--slug <kebab>] [--apply] [--lang ko|en]
/gh-setup:adr-bootstrap [path] supersede <number|path> "<title>" [--slug <kebab>] [--apply] [--lang ko|en]
/gh-setup:adr-bootstrap [path] --check
```

## Modes

| Mode | Writes (with `--apply`) | Notes |
|------|-------------------------|-------|
| `scaffold` (default) | `docs/adr/`, `docs/adr/README.md`, `docs/adr/NNNN-template.md` | Existing files are skipped. Re-running skips everything. |
| `new "<title>"` | `docs/adr/NNNN-<slug>.md` | Number = highest existing `NNNN-` + 1, starting at `0001`. Needs `docs/adr/` (run `scaffold` first). |
| `supersede <ref> "<title>"` | the new ADR, plus one line in the old ADR | `<ref>` is a number (`30` or `0030`) or a file path. Not found or ambiguous: stops, lists candidates, writes nothing. |
| `--check` | nothing | Exit 0 clean, 1 with findings. `--check` wins over any other mode. |

## Flags

| Flag | Default | Meaning |
|------|---------|---------|
| `path` | `.` | Repo root. Must be an existing directory. Give it before the mode word. |
| `--apply` | off | Write. Without it, print the plan and every planned file in full. |
| `--dry-run` | on | Explicit no-op; the default. |
| `--force` | off | `scaffold` only: overwrite an existing `README.md` / `NNNN-template.md`. |
| `--lang ko\|en` | `ko` | `ko`: Korean declarative-title form (상태 / 결정 / 이유 / 기각한 안 / 결과). `en`: MADR (Status / Context / Decision / Considered Options / Consequences). |
| `--slug <kebab>` | from title | File-name slug, `[a-z0-9-]`. Required when the title is not ASCII. |
| `-h`, `--help` | | This help. |

## Status lines written

| Where | `ko` | `en` |
|-------|------|------|
| New ADR | `Accepted — YYYY-MM-DD.` | same |
| New ADR, via supersede | `Accepted — YYYY-MM-DD. 0030 을 대체한다.` | `Accepted — YYYY-MM-DD. Supersedes 0030.` |
| Old ADR, appended once | `0031 로 대체됨 — YYYY-MM-DD.` | `Superseded by 0031 — YYYY-MM-DD.` |

The old ADR's line follows the old file's own status heading (`## 상태` or
`## Status`), not `--lang`. It goes after the last non-blank line of that
section. Nothing else in the old file changes.

## --check findings

1. Duplicate number (two files share an `NNNN-` prefix).
2. A `.md` file whose name does not match `NNNN-<slug>.md` (`README.md` and
   `NNNN-template.md` excepted). It is excluded from numbering, never deleted.
3. No status section, or a status section without `Accepted`.
4. A `대체됨` / `Superseded by` line whose number has no matching file.

## Testing

`sh skills/adr-bootstrap/lib/adr.sh --self-test` runs every mode against
temporary fixtures. `tests/run.sh` calls it.
