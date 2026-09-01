# label-bootstrap 사용 결과

> **한 줄 요약** — 라벨 SSOT 정의(`references/gh-labels.md`)를 받아 대상 repo 의
> GitHub 라벨 집합을 생성합니다.

```
라벨 SSOT (.md)  ──▶  /gh-setup:label-bootstrap  ──▶  repo 라벨 12종
```

## 1. 실행한 명령

범용 형식:

```
/gh-setup:label-bootstrap [--repo <owner/repo>] [--dry-run] [--prune]
```

이번 예시에 실제로 쓴 명령 (드라이런 — 변경 API 호출 0회):

```
bash skills/label-bootstrap/lib/label-bootstrap.sh --repo dEitY719/gh-setup-skills --dry-run
```

## 2. 입력

- `skills/label-bootstrap/references/gh-labels.md` — 10개 분류 라벨, 3개 별칭
  매핑, 2개 파이프라인 상태 라벨의 단일 정의처
- 대상 repo: `dEitY719/gh-setup-skills` — 라벨이 GitHub 기본값뿐인 새 repo

## 3. 결과

```
Target repo: dEitY719/gh-setup-skills (dry-run)
[dry-run] rename label 'bug' -> 'fix' (sync color/desc)
[dry-run] rename label 'documentation' -> 'docs' (sync color/desc)
[dry-run] POST label 'feat' (color=fbca04)
[dry-run] POST label 'refactor' (color=8250df)
[dry-run] POST label 'test' (color=2da44e)
[dry-run] POST label 'ci' (color=1d76db)
[dry-run] POST label 'chore' (color=bfbfbf)
[dry-run] POST label 'skill' (color=d97757)
[dry-run] POST label 'TODO' (color=d33cb5)
[dry-run] POST label 'reference' (color=0e8a8a)
[dry-run] POST label 'review-blocked' (color=b60205)
[dry-run] POST label 'review-passed' (color=0e8a16)
Prune skipped (--prune not set) — no labels deleted.
```

별칭 2건은 rename, 신규 10건은 POST 로 계획되었습니다. `build` 는 이 repo 에
없어 별칭 대상에서 빠졌고, `--prune` 을 주지 않았으므로 삭제 후보는 조회조차
하지 않았습니다.
