# gh-setup:docs-bootstrap — Help

## Usage

```
/gh-setup:docs-bootstrap [path] [flags]
/gh-setup:docs-bootstrap                 # dry-run plan for ./docs (default)
/gh-setup:docs-bootstrap . --apply       # scaffold ./docs
/gh-setup:docs-bootstrap ~/new-repo --apply
/gh-setup:docs-bootstrap --check         # read-only conformance audit
/gh-setup:docs-bootstrap -h              # show this help
/gh-setup:docs-bootstrap --help          # show this help
/gh-setup:docs-bootstrap help            # show this help
```

## Arguments

| # | Name | Required | Description |
|---|------|----------|-------------|
| 1 | `[path]` | no | Target repo root. `docs/` is created under it. Defaults to `.` (cwd). |

## Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--dry-run` | **on** | Default. Prints the creation plan; writes nothing. Always exits 0. |
| `--check` | off | Read-only audit — reports whether `docs/` already conforms (8 leaf dirs + `.gitkeep` + `README.md`). Exits 0 if complete, non-zero if anything is missing (CI-friendly). |
| `--apply` | off | Creates the directories, a `.gitkeep` in every leaf, and `docs/README.md`. |
| `--force` | off | With `--apply`, overwrite an existing `docs/README.md` (otherwise skipped). |
| `-h` / `--help` / `help` | — | Print this help and exit. No filesystem access. |

**Mode priority**: `--help` > `--check` > `--apply` > `--dry-run`. If more than
one mode flag is passed, the higher-priority one wins and a `[WARN]` is printed.

## What it creates

```
docs/
├─ adr/                     # 아키텍처 의사결정 (불변 로그)
├─ product/                 # PRD·수용기준·유즈케이스·기능 목록
├─ design/                  # 기능 설계 스펙·UX 설계·디자인 시스템
├─ architecture/
│  ├─ system/               # 시스템 전체 아키텍처 (현재 상태 SSOT)
│  └─ features/             # 개별 기능 TRD·마이그레이션 계획
├─ testing/                 # 테스트 전략·E2E 시나리오·품질 지표
├─ guides/                  # 내부 운영 방법론·온보딩
├─ public/                  # 외부 공개 문서
└─ README.md                # 문서 관리 정책 (위 표 + Docs-as-Code 규칙 3종)
```

Each leaf directory gets a `.gitkeep` so git tracks the empty folder. The
policy body of `README.md` is the single SSOT at
`references/docs-readme-template.md`.

## Idempotency

Re-running is safe: existing directories, `.gitkeep` files, and `README.md`
are skipped (a `skip` line is printed for each). `docs/README.md` is only
overwritten with `--force`.

## Examples

```
# 1. Preview what would be created in the current repo (no writes):
/gh-setup:docs-bootstrap

# 2. Scaffold a brand-new repo:
/gh-setup:docs-bootstrap ~/code/my-new-service --apply

# 3. CI gate — fail the build if docs/ drifted from the standard layout:
/gh-setup:docs-bootstrap --check
```
