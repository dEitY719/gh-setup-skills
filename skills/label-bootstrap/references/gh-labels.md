# GitHub 라벨 SSOT

## 목표

dotfiles 저장소를 포함한 임의의 GitHub repo 에 적용할 **10개 핵심
라벨**의 name/color/description 을 확정한다. 이 문서는 dotfiles 라벨
체계의 SSOT 이며, `gh-setup:label-bootstrap` 스킬이 이 문서의 **plain feed**
블록을 직접 읽어 대상 repo 의 라벨을 동기화한다. 라벨 이름/색상/설명을
바꿔야 하면 이 문서만 고치면 되고, 스킬은 두 번째 하드코딩 사본을 두지
않는다.

## 적용 범위

- 대상: 이 저장소 및 다른 프로젝트(재사용형) — origin/upstream 양쪽.
- 소비자: `gh-setup:label-bootstrap` (동기화 실행), `gh-setup:kanban-bootstrap`
  (보드 셋업 중 라벨 부트스트랩 위임), `gh-issue:create`
  (`.gh-issue-defaults.yml` 매핑), `gh-issue:implement`
  (`reference` 라벨 차단), `gh-pr:create` (커밋타입 → 라벨 매핑).
- 범위 밖: `CI fail`(`gh-resolve:ci-fail`), `conflict`
  (`gh-resolve:conflict`) 등 별개 라벨 체계는 건드리지 않는다.
- 예외: **파이프라인 상태 라벨**은 10-label SSOT 에 편입하지 않되, 이 문서의
  별도 `pipeline|` feed 로 **프로비저닝만** 한다 (아래 "파이프라인 라벨" 절).

차용 근거 / 설계 논의: issue dEitY719/dotfiles#1226.

## 확정 10개 라벨

| name | color | description |
|---|---|---|
| `feat` | `fbca04` | 신규 기능 또는 개선 (perf 흡수) |
| `fix` | `d73a4a` | 버그 수정 (구 `bug` 대체) |
| `docs` | `0075ca` | 문서 변경 (구 `documentation` 대체) |
| `refactor` | `8250df` | 동작 보존하며 구조 정리 |
| `test` | `2da44e` | 테스트 갭/추가/변경 (TDD red-green-blue의 green) |
| `ci` | `1d76db` | CI / GitHub Actions |
| `chore` | `bfbfbf` | 빌드·도구·deps·스타일 (구 `build` 대체) |
| `skill` | `d97757` | 스킬/플러그인 변경 (Claude 브랜드 컬러) |
| `TODO` | `d33cb5` | 처리 대기 항목 |
| `reference` | `0e8a8a` | 구현 불필요/참고용 — `gh-issue:implement`가 구현을 시작하지 않는 트리거 |

색상은 `#` 없이 6자리 hex 로 적는다 — GitHub label API (`POST`/`PATCH
/repos/{repo}/labels`) 가 `#` 없는 형식을 받고, 아래 plain feed 도 같은
형식을 쓴다.

## 파이프라인 라벨 (별도 feed, dEitY719/dotfiles#1564)

`review-blocked` / `review-passed` 는 **이슈 분류가 아니라 파이프라인 상태**다.
`gh-verify:review-all` 이 리뷰어 판정을 집계해 붙이고, `gh-pr:merge-train` 이
머지 하드 게이트로 읽는다 (SSOT:
`gh-verify:review-all` 의 `references/review-verdict-label.md`,
`gh-pr:merge-train` 의 `references/review-verdict-gate.md`).

| name | color | description |
|---|---|---|
| `review-blocked` | `b60205` | at least one reviewer lane returned a blocking verdict |
| `review-passed` | `0e8a16` | every reviewer lane that ran returned a non-blocking verdict, and at least one lane ran |

10개 SSOT 에 넣지 **않는** 이유: 이슈 분류 축이 아니고 alias 도 없으며,
`gh-issue:create` 자동 라벨링·`gh-pr:create` 커밋타입 매핑 어느 소비자도 이 두 개를
쓰지 않는다. 그런데도 이 문서가 프로비저닝을 맡는 이유는 `_gh_pr_edit_safe_label`
이 **없는 라벨을 자동 생성하지 않기** 때문이다 (rc 3, dEitY719/dotfiles#326) — 프로비저닝 경로가
없으면 판정 라벨이 영영 안 붙고, 부재를 차단으로 보는 게이트가 모든 PR 을
영구 skip 시킨다.

색상은 기존 팔레트와 충돌하지 않게 골랐다: `b60205` 는 `fix` 의 `d73a4a` 보다
어두운 빨강, `0e8a16` 은 `test` 의 `2da44e` 보다 어두운 초록이라 카드 목록에서
분류 라벨과 상태 라벨이 한눈에 갈린다.

## Alias 매핑 (rename 대상)

기존 이름이 대상 repo 에 존재하면 **삭제·재생성이 아니라 rename**
(`PATCH /repos/{repo}/labels/{old} -f new_name={new}`) 으로 처리한다 —
delete+recreate 는 이미 그 라벨을 달고 있는 모든 issue/PR 에서 라벨이
떨어져 나가므로 채택하지 않는다. rename 시 color/description 도 같은
호출에서 신규 SSOT 값으로 동기화한다.

| 기존 이름 (old) | 신규 이름 (new) |
|---|---|
| `bug` | `fix` |
| `documentation` | `docs` |
| `build` | `chore` |

기존 이름이 대상 repo 에 **없으면** rename 을 건너뛰고 신규 이름을 그냥
POST 한다 (에러 아님). 신규 이름이 이미 있으면 다른 SSOT 라벨과
동일하게 PATCH 로 동기화한다 (멱등).

## Prune allowlist (항상 보존)

GitHub 기본 제공 라벨은 삭제 후보에서 제외한다:

`enhancement`, `duplicate`, `good first issue`, `help wanted`,
`invalid`, `question`, `wontfix`

(alias 로 사라지는 `bug`/`documentation`/`build` 는 rename 후 자연히
없어지므로 allowlist 에 넣을 필요가 없다.)

## Prune 판정 원칙

- `--prune` 는 **기본 off** — 지정하지 않으면 어떤 라벨도 삭제되지
  않는다 (후보 나열 같은 부수효과도 없다). 라벨 삭제는 항상 opt-in 이다.
- `--prune` 지정 시, 다음 합집합에 **없는** 라벨만 삭제 후보다:
  (SSOT 10개) ∪ (**파이프라인 feed 2개**) ∪ (alias 신규 이름
  `fix`/`docs`/`chore`) ∪ (prune allowlist 7종).
- 파이프라인 라벨은 `--prune` 에서 **항상 보존**된다. 여기서 지워지면
  `gh-verify:review-all` 이 판정을 못 붙이고 (rc 3), 머지 트레인이 모든 PR 을
  "미검증"으로 읽어 파이프라인이 통째로 멈춘다 (dEitY719/dotfiles#1564).
- 판정은 **alias rename 을 먼저 적용한 뒤의 최종 label 셋 기준**으로
  한다. 그래야 `bug` 같은 rename 대상이 (이미 `fix` 가 된 상태라)
  삭제 후보로 오판되지 않는다.

## 권한 부족 처리

대상 repo 에 write 권한이 없으면 (fork, readonly token 등) 해당 라벨
작업만 per-label stderr 경고를 남기고 다음 라벨로 계속한다 — 라벨 하나의
실패가 전체 실행을 중단시키지 않는다.

## Plain feed (스킬이 직접 파싱)

`gh-setup:label-bootstrap` 의 `lib/label-bootstrap.sh` 가 아래 **세 블록**을
정규식으로 뽑아 쓴다. 표(위)와 값이 어긋나면 안 되므로 이 블록이 유일한
기계 판독 소스다.

세 feed 는 서로 다른 정규식으로 잡히고 겹치지 않는다 — 10-label feed 는
`name|<6hex>|`, alias feed 는 `old|new` (소문자 두 단어), 파이프라인 feed 는
`pipeline|` 접두어. 접두어는 파싱 직후 벗겨져 10-label feed 와 **같은
POST/PATCH 루프**에 합류하고, `--prune` 의 keep 집합에도 함께 들어간다.

### 10개 라벨 (`name|color|description`)

```
feat|fbca04|신규 기능 또는 개선 (perf 흡수)
fix|d73a4a|버그 수정 (구 bug 대체)
docs|0075ca|문서 변경 (구 documentation 대체)
refactor|8250df|동작 보존하며 구조 정리
test|2da44e|테스트 갭/추가/변경 (TDD red-green-blue의 green)
ci|1d76db|CI / GitHub Actions
chore|bfbfbf|빌드·도구·deps·스타일 (구 build 대체)
skill|d97757|스킬/플러그인 변경 (Claude 브랜드 컬러)
TODO|d33cb5|처리 대기 항목
reference|0e8a8a|구현 불필요/참고용 — gh-issue:implement가 구현을 시작하지 않는 트리거
```

### Alias 매핑 (`old|new`)

```
bug|fix
documentation|docs
build|chore
```

### 파이프라인 라벨 (`pipeline|name|color|description`)

```
pipeline|review-blocked|b60205|at least one reviewer lane returned a blocking verdict
pipeline|review-passed|0e8a16|every reviewer lane that ran returned a non-blocking verdict, and at least one lane ran
```

## Related

- 스킬: `skills/label-bootstrap/SKILL.md`
- 보드 SSOT: `docs/.ssot/github-project-board.md` (dEitY719/dotfiles 내부 문서 — 이 repo 밖)
- 소비 설정: `.gh-issue-defaults.yml`
- 소비 스킬: `gh-issue:implement` 의 `references/claim.md`
  (`GH_ISSUE_BLOCK_LABELS` 에 `reference` 포함),
  `gh-pr:create` 의 `references/pr-body-template.md` (커밋타입 매핑)
- 파이프라인 feed 소비: `gh-verify:review-all` 의 `references/review-verdict-label.md`
  (생산자), `gh-pr:merge-train` 의 `references/review-verdict-gate.md`
  (소비자)
- 설계 논의: issue dEitY719/dotfiles#1226 · 파이프라인 feed: issue dEitY719/dotfiles#1564 (상위 dEitY719/dotfiles#1527)
