# kanban-bootstrap — 스킬 설명서

> **한 줄 요약** — repo 하나에 대해 **GitHub Projects v2 칸반 보드**를 만들고,
> repo 를 연결하고, Status 필드를 6컬럼 워크플로로 교체한 보드를 산출한다.

## 무엇을 만들어 내는가

- Projects v2 보드 1개 (기본 제목 = repo 이름)
- 보드에 링크된 대상 repo
- 6컬럼 Status 필드 — Backlog / In progress / In review / Approved / Ready / Done
- Done 자동 아카이브 창 (기본 `2d`)
- 원격 `.github/pull_request_template.md` (`--skip-pr-template` 로 생략)
- 사람이 UI 에서 직접 켜야 하는 잔여 워크플로 체크리스트 출력

## 언제 쓰고 언제 안 쓰는가

| 상황 | 이 스킬 | 대신 쓸 것 |
|---|---|---|
| 새 repo 에 칸반 보드를 세운다 | 예 | — |
| 라벨만 맞추면 된다 | 아니오 | `label-bootstrap` |
| `docs/` 골격만 필요하다 | 아니오 | `docs-bootstrap` |
| 이미 있는 보드의 컬럼을 손본다 | 아니오 | GitHub UI (이 스킬은 부트스트랩 전용) |

라벨 단계는 자체 구현이 아니라 `label-bootstrap` 의 스크립트를 그대로 호출한다
(`--no-bootstrap-labels` 로 생략 가능).

## 호출 형식

```
/gh-setup:kanban-bootstrap [--owner <login>] [--repo <name>] [options]
```

셸에서 직접:

```
bash skills/kanban-bootstrap/lib/setup.sh [--owner <login>] [--repo <name>] [options]
```

| 인자 | 의미 |
|---|---|
| `--owner <login>` | 사용자 또는 조직. 생략 시 `gh repo view` 로 현재 repo 소유자. |
| `--repo <name>` | 저장소 이름. 생략 시 현재 repo. |
| `--title <board-title>` | 보드 제목. 기본은 repo 이름. |
| `--auto-archive-window <dur>` | Done 자동 아카이브 필터 접미사. 기본 `2d`. |
| `--hide-columns` | 1인 repo 용 Approved / Ready 숨김 안내를 추가한다. |
| `--dry-run` | 변경 없이 계획만 출력. |
| `--skip-pr-template` | 원격 PR 템플릿 생성/확인을 건너뛴다. |
| `--no-bootstrap-labels` | 5단계 라벨 동기화를 건너뛴다. |
| `-h`, `--help` | 도움말 출력 후 종료. API 호출 없음. |

## 동작 단계

1. 스킬 디렉터리를 찾고 `START_TS` 를 기록한다.
2. 사전 조건 점검 — `gh`, `jq`, 호스트, `project` 토큰 스코프. 빠진 게 있으면
   `gh auth refresh -h <host> -s project` 힌트를 내고 중단한다.
3. 대상 repo 결정. 언제나 `origin` 이며 원격 선택을 묻지 않는다.
4. 옵션 파싱. `--hide-columns` 가 없고 개인 repo 로 보이면 한 줄로 한 번만
   물어본다.
5. 라벨 부트스트랩 — 형제 스킬 스크립트에 위임.
6. `--dry-run` 디스패치. 실패하면 실제 실행으로 넘어가지 않는다.
7. 실제 실행 — 프로젝트 생성, repo 링크, Status 필드 교체, PR 템플릿 확인.
8. UI 체크리스트와 최종 보고 출력.

## 주의사항 / 제약

- **`origin` 만 대상으로 한다.** 다른 원격으로 조용히 넘어가지 않는다.
- **개인 repo 판정은 추론하지 않는다.** 협업자 수로 유추하면 그 자체가 정보
  노출이므로, 컬럼 숨김 여부는 반드시 사용자에게 한 번 물어본다.
- **토큰, 협업자 목록, 프로젝트 ID 를 stdout 에 찍지 않는다.**
- **스모크 테스트는 `--with-smoke-test` 없이는 실행하지 않는다.** 도움말 성격의
  명령 문자열만 출력한다.
- 모든 `gh` 호출은 `GH_HOST` 를 함께 넘긴다. `--repo` 만으로는 어느 서버인지
  지정되지 않기 때문이다.
- 워크플로 중 "Pull request linked to issue" 는 **비활성화**가 정답이다. Issue
  카드는 In review 컬럼을 거치지 않는다.
