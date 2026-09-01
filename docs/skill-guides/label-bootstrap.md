# label-bootstrap — 스킬 설명서

> **한 줄 요약** — GitHub 저장소의 **라벨 집합**을 10개 SSOT 라벨 + 2개 파이프라인
> 상태 라벨로 강제 동기화하는 산출물을 만든다.

## 무엇을 만들어 내는가

대상 repo 의 Labels 탭이 산출물이다. 실행이 끝나면 그 repo 는 다음을 갖는다.

- 분류용 10개 SSOT 라벨 — `feat`, `fix`, `docs`, `refactor`, `test`, `ci`,
  `chore`, `skill`, `TODO`, `reference`
- 파이프라인 상태 2개 — `review-blocked`, `review-passed`
- 별칭 3개가 **이름 변경**으로 흡수된 상태 — `bug` → `fix`,
  `documentation` → `docs`, `build` → `chore`

## 언제 쓰고 언제 안 쓰는가

| 상황 | 이 스킬 | 대신 쓸 것 |
|---|---|---|
| 새 repo 의 라벨만 정렬하고 싶다 | 예 | — |
| Projects v2 칸반 보드까지 세우고 싶다 | 아니오 | `kanban-bootstrap` (5단계에서 이 스킬을 호출한다) |
| `docs/` 골격이 필요하다 | 아니오 | `docs-bootstrap` |
| 이슈/PR 본문에 메트릭을 붙이고 싶다 | 아니오 | `add-ai-metrics` |

`kanban-bootstrap` 은 자체 라벨 로직을 갖지 않고 이 스킬의
`lib/label-bootstrap.sh` 를 직접 실행한다. 라벨 SSOT 는 한 곳
(`skills/label-bootstrap/references/gh-labels.md`) 에만 존재한다.

## 호출 형식

```
/gh-setup:label-bootstrap [--repo <owner/repo>] [--dry-run] [--prune]
```

셸에서 직접:

```
bash skills/label-bootstrap/lib/label-bootstrap.sh [--repo <owner/repo>] [--dry-run] [--prune]
```

| 인자 | 의미 |
|---|---|
| `--repo <owner/repo>` | 대상 repo. 생략하면 `gh repo view` 로 현재 repo 를 쓴다. 원격 선택을 묻지 않는다. |
| `--dry-run` | 계획만 출력. POST/PATCH/DELETE API 호출을 하나도 보내지 않는다. |
| `--prune` | SSOT 밖 커스텀 라벨을 **삭제**한다. 기본은 꺼져 있다. |
| `-h`, `--help` | `references/help.md` 를 그대로 출력하고 종료. API 호출 없음. |

## 동작 단계

1. 스킬 디렉터리를 찾고 `lib/label-bootstrap.sh` 와 SSOT 파일 위치를 확정한다.
2. 대상 repo 를 결정한다 (`--repo` 우선, 아니면 `gh repo view`).
3. `--dry-run` 으로 먼저 돌려 rename / PATCH / POST / prune 후보 계획을 낸다.
   드라이런이 실패하면 실행하지 않고 중단한다.
4. 실제 실행. 별칭 3개를 `PATCH new_name=` 으로 이름 변경하고, 나머지 SSOT
   라벨을 색/설명까지 강제 동기화하며, 없는 라벨은 새로 만든다.
5. 적용된 동작을 한 줄씩 보고한다.

## 주의사항 / 제약

- **강제 동기화이며 건너뛰기 모드가 없다.** 이미 존재하는 SSOT 라벨도 색과
  설명이 무조건 표준값으로 PATCH 된다.
- **별칭은 삭제 후 재생성이 아니라 이름 변경이다.** 그래야 그 라벨을 이미 달고
  있는 이슈/PR 이 라벨을 잃지 않는다.
- **`--prune` 없이는 아무것도 지우지 않는다.** 목록조차 만들지 않는다.
  `--prune` 을 줬을 때도 삭제 대상 집합은 이름 변경이 **끝난 뒤에** 계산되므로
  `bug` 같은 별칭 원본이 오탐으로 지워지는 일이 없다.
- 라벨 단위 권한 오류는 경고만 내고 다음 라벨로 계속한다. 한 라벨의 실패가
  실행 전체를 중단시키지 않는다.
- 스크립트가 유일한 진입점이다. 감싸서 쓰되 다시 구현하지 않는다.
