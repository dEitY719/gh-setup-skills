# gh-setup:add-ai-metrics — Repo + host resolution

Contract for `TARGET_REPO` / `TARGET_HOST` resolution -- remote validation,
owner/repo **plus host** extraction, and the `--repo` override. Implemented as
`resolve_repo` in [`lib/ai-metrics.sh`](../lib/ai-metrics.sh); this file says
what it guarantees, not how, so there is one copy of the logic to keep correct.

## Two paths

**`--repo <owner/repo>` given** -- `TARGET_REPO` is that value verbatim. The
host is **not** inferred from `$REMOTE`'s URL: `--repo` may name a repo on a
completely different host than this checkout's own remote, and borrowing that
remote's host anyway is exactly how a `--repo` invocation used to land on the
wrong GitHub server with no error. Host resolution instead prefers an
already-exported `GH_HOST`, then the `_gh_resolve_host` setup-mode mapping,
then `github.com`.

**No `--repo`** -- resolve both `TARGET_REPO` and `TARGET_HOST` from one and
the same `$REMOTE` URL, never from two sources:

```bash
git remote get-url <remote-name>
```

If this fails, list available remotes (`git remote -v`) and stop with an
error like:

```
Error: remote '<remote-name>' not found. Available remotes:
origin  https://github.com/user/repo.git (fetch)
upstream  https://github.com/org/repo.git (fetch)
```

`gh_host.sh`, when present (`${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common/functions/gh_host.sh`),
is the SSOT for host/URL mapping -- its `_gh_parse_owner_repo_url` /
`_gh_host_from_url` do the parsing, with `_gh_resolve_host` (setup-mode →
host) as the fallback when the URL itself doesn't resolve to a known host.
Its absence (a standalone `gh-setup` install with no dotfiles checkout)
degrades to a plain strip-scheme-and-split parse of the same URL, so the two
values still come from the one string either way:

- `https://github.com/<owner>/<repo>.git` → `github.com` + `<owner>/<repo>`
- `git@github.samsungds.net:<owner>/<repo>.git` → `github.samsungds.net`
  + `<owner>/<repo>`

Both paths converge on the same guarantee: `TARGET_HOST` is never empty when
`resolve_repo` returns (an empty `GH_HOST` is exactly the silent
wrong-host state of dEitY719/dotfiles#1403), and both are exported for every later step.

## Host targeting rule (dEitY719/dotfiles#1403)

이 스킬의 **모든** `gh` 호출 — 카드 조회 (`gh issue list` / `gh pr list`),
본문 읽기 (`gh api`), 푸터 쓰기 (`gh issue edit` / `gh pr edit`) — 은 host 와
repo 를 명시한다:

```bash
GH_HOST="$TARGET_HOST" gh <sub-command> ... --repo "$TARGET_REPO"
```

`--repo` 없는 `gh` 는 git 의 `origin` 이 아니라 gh CLI 자신의
`gh repo set-default` 를 따른다. github.com 과 GHES 에 동시에 로그인한
상태에서 둘이 어긋나면 **에러 없이 조용히 다른 host 에 붙는다**. 카드 본문을
고쳐 쓰는 이 스킬에서는 그 결과가 "엉뚱한 repo 의 이슈/PR 본문이 수정됨"
이고, 되돌리려면 사람이 직접 복구해야 한다 (dEitY719/dotfiles#1403).

## Failure rule

If the user-specified remote does not exist, fail immediately with the
list of available remotes. **Do not** fall back to `origin` silently —
that masks typos and rewrites card bodies in the wrong repo.

`TARGET_HOST` 가 빈 채로 다음 단계에 진입하지 않는다 — 빈 `GH_HOST` 는 정확히
dEitY719/dotfiles#1403 의 조용한 오작동 상태다.
