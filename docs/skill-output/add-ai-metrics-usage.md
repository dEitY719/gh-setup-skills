# add-ai-metrics 사용 결과

> **한 줄 요약** — 이슈/PR 번호 목록을 받아 각 카드 본문에 붙일 메트릭 푸터
> 블록을 생성합니다.

```
issue#N / pr#M 목록  ──▶  /gh-setup:add-ai-metrics  ──▶  카드 본문의 ai-metrics 푸터
```

## 1. 실행한 명령

범용 형식:

```
/gh-setup:add-ai-metrics [<targets>] [--type issue|PR] [--date <date>] [--dry-run] [--force]
```

이번 예시에 실제로 쓴 명령 (드라이런 — `gh edit` 호출 0회, view 만 수행):

```
/gh-setup:add-ai-metrics issue#1410 pr#320 issue#317 --dry-run
```

## 2. 입력

- 대상 카드 3건: `dEitY719/dotfiles` 의 issue #1410, PR #320, issue #317
- 이 repo(`gh-setup-skills`)는 아직 이슈도 PR 도 0건이라 백필할 카드가 없어,
  실제 카드가 있는 형제 repo 를 읽기 전용으로 대상 삼았습니다.

## 3. 결과

```
· will-skip  #1410 feat(skills): claude/skills 71종을 6-하네스 지원 15개 마켓플레이스 repo 로 분리
· will-skip  #320 Add AI work-metrics footer to GitHub Issues and PRs
· will-skip  #317 feat(gh-issue-create,gh-issue-flow): GitHub Issue/PR에 AI 작업 메트릭(토큰·시간) 자동 기록 시스템

DRY RUN: 3 cards (0 will-write, 0 will-force-replace, 3 will-skip)
         pace=unset budget=unset limit=unset
         estimated wall-clock: <1m (no pace)
```

세 카드 모두 이미 푸터를 갖고 있어 `will-skip` 으로 분류되었습니다. 이것이
바로 이 스킬의 멱등성 계약이 눈에 보이는 형태입니다 — 백필이 끝난 repo 에
같은 명령을 다시 던져도 쓰기는 한 건도 발생하지 않습니다. 실제로 같은 판정
로직을 #10, #50, #100, #200, #250 에도 돌려봤고 다섯 건 모두 `will-skip`
이었습니다. 푸터를 새로 붙이려면 아직 백필되지 않은 카드가 필요합니다.
