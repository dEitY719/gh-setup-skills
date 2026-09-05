# gh-setup:add-ai-metrics — Repo + host resolution

Detailed procedure for Step 1's `TARGET_REPO` resolution — remote validation and
owner/repo **plus host** extraction. `SKILL.md` keeps only the workflow; this
file holds the substeps and error-message shape.

Vendored copy. The shared flow originates in `gh-issue:create`
(`references/repo-resolution.md` there) and each skill owns a tailored copy —
this plugin ships no cross-plugin dependency mechanism, so the file has to live
here for a standalone `gh-setup` install to work. Keep the two in sync by hand
when the shared flow changes.

## Substeps

1. `git rev-parse --show-toplevel` — confirm we're in a git repo.

2. Determine the target remote:
   - If the user passed an argument, use it as remote name.
   - Otherwise default to `origin`.

3. Validate the remote and resolve owner/repo:

   ```bash
   git remote get-url <remote-name>
   ```

   If this fails, list available remotes (`git remote -v`) and stop with
   an error like:

   ```
   Error: remote '<remote-name>' not found. Available remotes:
   origin  https://github.com/user/repo.git (fetch)
   upstream  https://github.com/org/repo.git (fetch)
   ```

4. Extract `owner/repo` **and the host** from the remote URL returned in
   step 3. Both come from that one URL — never from two sources:

   ```bash
   REMOTE_URL=$(git remote get-url <remote-name>) || exit 1
   _SSOT="${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common/functions/gh_host.sh"
   if [ -r "$_SSOT" ]; then
       . "$_SSOT"
       TARGET_REPO=$(_gh_parse_owner_repo_url "$REMOTE_URL") || exit 1
       TARGET_HOST=$(_gh_host_from_url "$REMOTE_URL") || TARGET_HOST=$(_gh_resolve_host)
   else
       # Standalone install — no dotfiles checkout. Strip scheme, credentials
       # and the `.git` suffix, then split on the first `:` or `/`.
       _u=${REMOTE_URL%.git}; _u=${_u#*://}; _u=${_u#*@}
       TARGET_HOST=${_u%%[:/]*}
       TARGET_REPO=${_u#*[:/]}
   fi
   [ -n "$TARGET_HOST" ] && [ -n "$TARGET_REPO" ] || exit 1
   export GH_HOST="$TARGET_HOST"
   export TARGET_REPO TARGET_HOST
   ```

   - `https://github.com/<owner>/<repo>.git` → `github.com` + `<owner>/<repo>`
   - `git@github.samsungds.net:<owner>/<repo>.git` → `github.samsungds.net`
     + `<owner>/<repo>`

   `gh_host.sh` 가 있으면 그것이 host/URL 매핑의 SSOT 다 — 정규식이나 도메인
   목록을 여기에 복제하지 않는다. `_gh_resolve_host` (setup-mode → host) 는
   파싱할 remote URL 이 없을 때만 쓰는 fallback 이다. `gh-setup` 을 dotfiles
   없이 단독 설치한 환경에는 그 파일이 없으므로, 위의 `else` 분기가 같은 두
   값을 remote URL 하나에서 직접 뽑는다 — 이 스킬은 Step 1 에서 `TARGET_REPO`
   를 못 구하면 진행할 수 없기 때문에, 여기서 fallback 이 없으면 vendoring
   자체가 무의미해진다.

Store the results as `TARGET_REPO` and `TARGET_HOST` — every later step of this
skill reads them.

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
