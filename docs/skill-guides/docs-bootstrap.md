# docs-bootstrap — 스킬 설명서

> **한 줄 요약** — 빈 repo 에 **kind-split `docs/` 디렉터리 트리**를 만든다.
> 8개 리프 폴더와 각각의 `.gitkeep`, 그리고 정책 문서 `docs/README.md` 가 산출물이다.

## 무엇을 만들어 내는가

```
docs/
├── adr/.gitkeep
├── product/.gitkeep
├── design/.gitkeep
├── architecture/system/.gitkeep
├── architecture/features/.gitkeep
├── testing/.gitkeep
├── guides/.gitkeep
├── public/.gitkeep
└── README.md
```

정책은 **폴더 = 문서 종류, 기능 = 파일 이름**이다. 폴더는 비어 있고, git 이
빈 폴더를 추적하도록 리프마다 `.gitkeep` 이 들어간다.

## 언제 쓰고 언제 안 쓰는가

| 상황 | 이 스킬 | 대신 쓸 것 |
|---|---|---|
| 새 repo 에 문서 골격을 깐다 | 예 | — |
| 이미 문서가 들어 있는 `docs/` 를 재배치한다 | 아니오 | 수동 마이그레이션 (이 스킬은 스캐폴드 전용) |
| PRD / TRD / ADR 본문을 쓴다 | 아니오 | 별도 문서 작성 스킬 |
| 라벨이나 보드가 필요하다 | 아니오 | `label-bootstrap`, `kanban-bootstrap` |

네 스킬 중 유일하게 네트워크도 `gh` 도 필요 없다. 셸과 쓰기 가능한 디렉터리만
있으면 된다.

## 호출 형식

```
/gh-setup:docs-bootstrap [path] [--check|--apply|--dry-run] [--force]
```

셸에서 직접:

```
bash skills/docs-bootstrap/lib/scaffold.sh [path] [--check|--apply|--dry-run] [--force]
```

| 인자 | 의미 |
|---|---|
| `path` | 대상 repo 루트. 기본은 현재 디렉터리. 그 아래에 `docs/` 를 만든다. |
| `--dry-run` | **기본값.** 생성 계획만 출력하고 아무것도 쓰지 않는다. 항상 0 으로 종료. |
| `--check` | 읽기 전용 감사. 완비면 0, 하나라도 빠지면 0 이 아닌 값으로 종료 — CI 게이트용. |
| `--apply` | 디렉터리, `.gitkeep`, `docs/README.md` 를 실제로 만든다. |
| `--force` | `--apply` 와 함께 쓸 때만 유효. 기존 `docs/README.md` 를 덮어쓴다. |
| `-h`, `--help` | 도움말 출력 후 종료. **파일 시스템에 접근하지 않는다.** |

모드 우선순위는 `--help` > `--check` > `--apply` > `--dry-run` 이다.

## 동작 단계

1. 인자를 파싱해 대상 경로와 모드를 정한다.
2. `lib/scaffold.sh` 를 실행한다. 레이아웃 SSOT 는 이 스크립트,
   README 본문 SSOT 는 `references/docs-readme-template.md` 다.
3. 스크립트의 `[OK]` / `[FAIL]` 판정과 create/skip 계획을 그대로 전달하고,
   다음 단계 힌트로 마무리한다.

## 주의사항 / 제약

- **기본이 `--dry-run` 이다.** `--apply` 를 명시해야만 파일이 생긴다.
- **`docs/README.md` 를 `--force` 없이 덮어쓰지 않는다.**
- **문서 본문을 쓰지 않는다.** `docs/README.md` 하나가 예외이고, 나머지 폴더는
  비어 있는 상태로 남는다.
- **이미 채워진 `docs/` 를 이전하지 않는다.** 기존 경로는 `skip` 줄로 넘어간다.
  즉 여러 번 실행해도 안전하다.
- 빈 폴더를 유지하는 `.gitkeep` 은 실제 문서가 들어오면 지워도 된다.
