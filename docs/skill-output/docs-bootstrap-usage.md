# docs-bootstrap 사용 결과

> **한 줄 요약** — 대상 디렉터리 경로를 받아 8개 리프로 이루어진 `docs/` 트리와
> 정책 README 를 생성합니다.

```
디렉터리 경로  ──▶  /gh-setup:docs-bootstrap  ──▶  docs/ 트리 (8 리프 + README.md)
```

## 1. 실행한 명령

범용 형식:

```
/gh-setup:docs-bootstrap [path] [--check|--apply|--dry-run] [--force]
```

이번 예시에 실제로 쓴 명령 (네 스킬 중 유일하게 진짜 쓰기까지 실행):

```
bash skills/docs-bootstrap/lib/scaffold.sh <scratch>/demo-repo --apply
```

## 2. 입력

- 대상 경로: 스크래치패드의 빈 디렉터리 `demo-repo/` (실제 repo 를 건드리지
  않으려고 임시 디렉터리를 썼습니다)
- 레이아웃 SSOT: `skills/docs-bootstrap/lib/scaffold.sh`
- README 본문 SSOT: `skills/docs-bootstrap/references/docs-readme-template.md`

## 3. 결과

```
[INFO] Scaffolding <scratch>/demo-repo/docs/ (kind-split layout)
  create adr/.gitkeep
  create product/.gitkeep
  create design/.gitkeep
  create architecture/system/.gitkeep
  create architecture/features/.gitkeep
  create testing/.gitkeep
  create guides/.gitkeep
  create public/.gitkeep
  create README.md
[OK] docs/ scaffolded. Empty folders are tracked via .gitkeep.
```

`find docs -print` 로 확인한 실제 산출물은 디렉터리 10개(`docs/` +
`architecture/` 중간 노드 포함)와 파일 9개(`.gitkeep` 8개 + `README.md` 1개)
였습니다. 같은 명령을 한 번 더 돌리자 아홉 줄이 전부 `skip ... (exists)` 로
바뀌고 `README.md` 만 `(exists — use --force to overwrite)` 를 덧붙였습니다.
