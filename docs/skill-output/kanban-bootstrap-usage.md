# kanban-bootstrap 사용 결과

> **한 줄 요약** — repo 좌표(owner/name)를 받아 Projects v2 칸반 보드와 6컬럼
> Status 필드를 생성합니다.

```
repo 좌표  ──▶  /gh-setup:kanban-bootstrap  ──▶  Projects v2 보드 + 6컬럼 Status
```

## 1. 실행한 명령

범용 형식:

```
/gh-setup:kanban-bootstrap [--owner <login>] [--repo <name>] [options]
```

이번 예시에 실제로 쓴 명령 (드라이런 — 프로젝트/링크/필드/파일 변경 0건):

```
bash skills/kanban-bootstrap/lib/setup.sh --owner dEitY719 --repo gh-setup-skills --dry-run
```

## 2. 입력

- 대상 repo: `dEitY719/gh-setup-skills` (보드가 아직 없는 새 repo)
- 인증: `project` 스코프를 가진 `gh` CLI + `jq`

## 3. 결과

8단계 중 스크립트가 담당하는 7단계까지의 실제 출력 (ANSI 색상 제거,
UI 체크리스트 8줄은 지면상 생략):

```
[1] Validating repository access
  Repository found: https://github.com/dEitY719/gh-setup-skills
[2] Checking for an existing project titled 'gh-setup-skills'
[3] Creating the project
  [dry-run] Would create project 'gh-setup-skills' under dEitY719
[4] Linking the repository
  [dry-run] Would link dEitY719/gh-setup-skills to project 'gh-setup-skills'
[5] Replacing the Status options
  [dry-run] Would replace Status options with the 6-option dotfiles workflow
[6] Ensuring the pull request template
  [dry-run] Would create .github/pull_request_template.md on main
[7] Printing the remaining UI checklist

Mode
  Dry-run only: no project, link, field, or file mutations were sent.
```

프로젝트 번호가 `#0` 으로 나온 것은 드라이런이라 실제 보드가 만들어지지 않아
번호를 배정받지 못했기 때문입니다. 7단계가 출력한 UI 체크리스트에는 사람이
직접 켜야 할 워크플로 8건이 호스트별 링크와 함께 들어 있고, 그중
"Pull request linked to issue" 는 활성화가 아니라 **비활성화**가 지시입니다.
