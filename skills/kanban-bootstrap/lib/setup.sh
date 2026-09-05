#!/bin/bash

set -euo pipefail

# -----------------------------------------------------------------------------
# Self-contained UX helpers — no external library required.
# This script is a single-file SSOT meant to be copy-pasted into other repos
# to bootstrap a GitHub Projects v2 kanban board, so it cannot depend on the
# parent dotfiles tree.
# -----------------------------------------------------------------------------
if [ -n "${NO_COLOR:-}" ] || [ "${TERM:-}" = "dumb" ] || ! command -v tput >/dev/null 2>&1; then
    UX_BOLD=""
    UX_RESET=""
    UX_PRIMARY=""
    UX_SUCCESS=""
    UX_WARNING=""
    UX_ERROR=""
    UX_INFO=""
    UX_MUTED=""
else
    UX_BOLD="$(tput bold 2>/dev/null || echo '')"
    UX_RESET="$(tput sgr0 2>/dev/null || echo '')"
    UX_PRIMARY="$(tput setaf 4 2>/dev/null || echo '')"
    UX_SUCCESS="$(tput setaf 2 2>/dev/null || echo '')"
    UX_WARNING="$(tput setaf 3 2>/dev/null || echo '')"
    UX_ERROR="$(tput setaf 1 2>/dev/null || echo '')"
    UX_INFO="$(tput setaf 6 2>/dev/null || echo '')"
    UX_MUTED="$(tput setaf 8 2>/dev/null || echo '')"
fi

ux_header() {
    local text="$1"
    echo ""
    printf "%s%s╔══════════════════════════════════════════════════════════════╗%s\n" "${UX_BOLD}" "${UX_PRIMARY}" "${UX_RESET}"
    printf "%s%s║%s %-58s %s%s║%s\n" "${UX_BOLD}" "${UX_PRIMARY}" "${UX_RESET}" "$text" "${UX_BOLD}" "${UX_PRIMARY}" "${UX_RESET}"
    printf "%s%s╚══════════════════════════════════════════════════════════════╝%s\n" "${UX_BOLD}" "${UX_PRIMARY}" "${UX_RESET}"
    echo ""
}

ux_section() {
    local title="$1"
    local underline
    underline="$(printf '─%.0s' $(seq 1 ${#title}))"
    echo ""
    printf "%s%s%s%s\n" "${UX_BOLD}" "${UX_PRIMARY}" "$title" "${UX_RESET}"
    printf "%s%s%s%s\n" "${UX_BOLD}" "${UX_PRIMARY}" "$underline" "${UX_RESET}"
}

ux_usage() {
    local cmd_name="$1"
    local args="$2"
    local description="${3:-}"
    ux_section "Usage"
    echo "  ${UX_SUCCESS}${cmd_name}${UX_RESET} ${UX_MUTED}${args}${UX_RESET}"
    if [ -n "$description" ]; then
        echo ""
        echo "  $description"
    fi
    echo ""
}

ux_success() { printf "%s%s✅%s %s\n" "${UX_BOLD}" "${UX_SUCCESS}" "${UX_RESET}" "$1"; }
ux_error()   { printf "%s%s❌%s %s\n" "${UX_BOLD}" "${UX_ERROR}"   "${UX_RESET}" "$1" >&2; }
ux_warning() { printf "%s%s⚠%s  %s\n" "${UX_BOLD}" "${UX_WARNING}" "${UX_RESET}" "$1"; }
ux_info()    { printf "%s%sℹ%s  %s\n" "${UX_BOLD}" "${UX_INFO}"    "${UX_RESET}" "$1"; }
ux_step()    { printf "%s%s[%s]%s %s\n" "${UX_BOLD}" "${UX_PRIMARY}" "$1" "${UX_RESET}" "$2"; }
ux_bullet()     { printf "  ${UX_PRIMARY}◆${UX_RESET} %s\n" "$1"; }
ux_bullet_sub() { printf "    ${UX_INFO}•${UX_RESET} %s\n" "$1"; }

OWNER=""
REPO=""
TITLE=""
AUTO_ARCHIVE_WINDOW="2d"
HIDE_COLUMNS=false
DRY_RUN=false
SKIP_PR_TEMPLATE=false

OWNER_TYPE=""
OWNER_ID=""
REPO_ID=""
REPO_URL=""
DEFAULT_BRANCH=""
PROJECT_ID=""
PROJECT_NUMBER=""
PROJECT_URL=""
WORKFLOWS_URL=""
HOST="github.com"

PR_TEMPLATE_PATH=".github/pull_request_template.md"
PR_TEMPLATE_COMMIT_MESSAGE="Chore: add pull request template for kanban board setup"

log_info() { ux_info "$1"; }
log_success() { ux_success "$1"; }
log_warning() { ux_warning "$1"; }
log_error() { ux_error "$1"; }
log_step() { ux_step "$1" "$2"; }

die() {
    log_error "$1"
    exit 1
}

print_help() {
    ux_header "Kanban Board Setup"
    ux_usage "bash skills/kanban-bootstrap/lib/setup.sh" "[--owner <login>] [--repo <name>] [options]" \
        "Create a GitHub Projects v2 board, link the repo, sync the Status field, and print the remaining UI checklist."

    ux_section "Options"
    ux_bullet "--owner <login>              GitHub user or org (default: current repo's owner via gh repo view)"
    ux_bullet "--repo <name>                Repository name (default: current repo's name via gh repo view)"
    ux_bullet "--title <board-title>        Project title (default: repo name)"
    ux_bullet "--auto-archive-window <dur>  Filter suffix for Done auto-archive (default: 2d)"
    ux_bullet "--hide-columns               Add solo-repo hide guidance for Approved and Ready"
    ux_bullet "--dry-run                    Print the plan without mutations"
    ux_bullet "--skip-pr-template           Skip remote PR template creation/check"
    ux_bullet "-h, --help                   Show this help"
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --owner)
            [ "${2-}" ] || die "--owner requires a value"
            OWNER="$2"
            shift 2
            ;;
        --repo)
            [ "${2-}" ] || die "--repo requires a value"
            REPO="$2"
            shift 2
            ;;
        --title)
            [ "${2-}" ] || die "--title requires a value"
            TITLE="$2"
            shift 2
            ;;
        --auto-archive-window)
            [ "${2-}" ] || die "--auto-archive-window requires a value"
            AUTO_ARCHIVE_WINDOW="$2"
            shift 2
            ;;
        --hide-columns)
            HIDE_COLUMNS=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-pr-template)
            SKIP_PR_TEMPLATE=true
            shift
            ;;
        -h | --help)
            print_help
            exit 0
            ;;
        *)
            die "Unknown option: $1"
            ;;
        esac
    done

    detect_repo_defaults

    [ -n "$OWNER" ] || die "--owner is required (auto-detect failed; pass --owner or run inside a GitHub-linked git repo)"
    [ -n "$REPO" ] || die "--repo is required (auto-detect failed; pass --repo or run inside a GitHub-linked git repo)"

    if [ -z "$TITLE" ]; then
        TITLE="$REPO"
    fi

    if [[ ! "$AUTO_ARCHIVE_WINDOW" =~ ^[0-9]+[dwmy]$ ]]; then
        die "--auto-archive-window must look like 2d, 1w, or 3m"
    fi
}

require_command() {
    local name="$1"
    local install_hint="${2:-Install $1 first.}"

    if ! command -v "$name" >/dev/null 2>&1; then
        die "${name} is required. ${install_hint}"
    fi
}

detect_repo_defaults() {
    if [ -n "$OWNER" ] && [ -n "$REPO" ]; then
        return 0
    fi

    local detected_info detected_owner detected_repo
    detected_info="$(gh repo view --json owner,name -q '(.owner.login? // empty) + " " + (.name? // empty)' 2>/dev/null || true)"
    [ -n "$detected_info" ] || return 0

    read -r detected_owner detected_repo <<<"$detected_info"
    if [ -z "$OWNER" ] && [ -n "${detected_owner-}" ]; then
        OWNER="$detected_owner"
    fi
    if [ -z "$REPO" ] && [ -n "${detected_repo-}" ]; then
        REPO="$detected_repo"
    fi
}

# Detect current GitHub host (github.com or GHE) from origin remote.
# Falls back to github.com when remote parsing fails. Sets HOST.
detect_host() {
    local remote_url host=""
    remote_url="$(git remote get-url origin 2>/dev/null || true)"
    if [ -n "$remote_url" ]; then
        case "$remote_url" in
            git@*) host="${remote_url#git@}"; host="${host%%:*}" ;;
            https://*) host="${remote_url#https://}"; host="${host%%/*}" ;;
            ssh://*) host="${remote_url#ssh://}"; host="${host%%/*}"; host="${host#*@}"; host="${host%%:*}" ;;
        esac
    fi
    HOST="${host:-github.com}"
}

auth_scopes_csv() {
    local scopes host_args=()

    # Use --hostname when HOST is non-default so GHE tokens are checked
    # against the actual instance (PR dEitY719/dotfiles#702 review feedback).
    if [ -n "${HOST:-}" ] && [ "$HOST" != "github.com" ]; then
        host_args=(--hostname "$HOST")
    fi

    scopes="$(gh api "${host_args[@]}" user -i 2>/dev/null | awk '
        {
            line = $0
            sub(/\r$/, "", line)
            if (line == "") {
                exit
            }
            if (index(tolower(line), "x-oauth-scopes:") == 1) {
                sub(/^[^:]*:[[:space:]]*/, "", line)
                print line
                exit
            }
        }
    ')"

    if [ -z "$scopes" ]; then
        return 1
    fi

    printf "%s" "$scopes" | tr -d ' '
}

require_project_scope() {
    local scopes_csv need_scope

    if ! scopes_csv="$(auth_scopes_csv)"; then
        die "gh api user could not read token scopes. Run: gh auth login --scopes \"project\""
    fi

    need_scope="project"
    if $DRY_RUN; then
        case ",${scopes_csv}," in
        *,project,* | *,read:project,*)
            return 0
            ;;
        esac
        die "Your gh token is missing project access. Run: gh auth refresh -s project"
    fi

    case ",${scopes_csv}," in
    *,${need_scope},*)
        return 0
        ;;
    esac

    die "Your gh token is missing the project scope required for mutations. Run: gh auth refresh -s project"
}

# Every GraphQL round-trip (reads AND the project/field mutations) goes
# through here, so this is where the host pin has to live (dEitY719/dotfiles#1407). `HOST`
# is the origin-derived host: it defaults to github.com at declaration and
# `detect_host` overwrites it in `main` before the first `gh_graphql` call,
# so it is always in scope even under `set -u`. `--hostname` is `gh api`'s
# host flag (`-h` is its help flag) and matches `auth_scopes_csv` above;
# without it a GHES checkout would silently read and mutate github.com.
gh_graphql() {
    local query="$1"
    shift
    gh api --hostname "${HOST:-github.com}" graphql -f query="$query" "$@"
}

load_repo_context() {
    local repo_json

    # GraphQL variables are passed via -f flags below; single quotes are intentional.
    # shellcheck disable=SC2016
    repo_json="$(gh_graphql '
        query RepoContext($owner: String!, $repo: String!) {
          repository(owner: $owner, name: $repo) {
            id
            name
            url
            owner {
              __typename
              login
              id
            }
            defaultBranchRef {
              name
            }
          }
        }
    ' -f owner="$OWNER" -f repo="$REPO")" || die "Failed to query repository ${OWNER}/${REPO}"

    if [ "$(printf '%s' "$repo_json" | jq -r '.data?.repository? == null')" = "true" ]; then
        die "Repository ${OWNER}/${REPO} was not found or is not accessible."
    fi

    OWNER_TYPE="$(printf '%s' "$repo_json" | jq -r '.data.repository.owner.__typename')"
    OWNER_ID="$(printf '%s' "$repo_json" | jq -r '.data.repository.owner.id')"
    REPO_ID="$(printf '%s' "$repo_json" | jq -r '.data.repository.id')"
    REPO_URL="$(printf '%s' "$repo_json" | jq -r '.data.repository.url')"
    DEFAULT_BRANCH="$(printf '%s' "$repo_json" | jq -r '.data.repository.defaultBranchRef.name // empty')"

    if [ "$OWNER_TYPE" != "User" ] && [ "$OWNER_TYPE" != "Organization" ]; then
        die "Unsupported repository owner type: ${OWNER_TYPE}"
    fi
}

find_existing_project() {
    local projects_json match

    # GraphQL variables are passed via -f flags below; single quotes are intentional.
    # shellcheck disable=SC2016
    projects_json="$(gh_graphql '
        query ExistingProjects($owner: String!) {
          repositoryOwner(login: $owner) {
            __typename
            ... on User {
              projectsV2(first: 100) {
                nodes {
                  id
                  number
                  title
                  url
                }
              }
            }
            ... on Organization {
              projectsV2(first: 100) {
                nodes {
                  id
                  number
                  title
                  url
                }
              }
            }
          }
        }
    ' -f owner="$OWNER")" || die "Failed to list existing projects for ${OWNER}"

    match="$(printf '%s' "$projects_json" | jq -r --arg title "$TITLE" '
        .data.repositoryOwner?.projectsV2?.nodes?[]?
        | select(.title == $title)
        | [.id, (.number | tostring), .url]
        | @tsv
    ' | head -n1)"

    if [ -n "$match" ]; then
        IFS=$'\t' read -r PROJECT_ID PROJECT_NUMBER PROJECT_URL <<<"$match"
        return 0
    fi

    return 1
}

create_project() {
    local create_json

    if $DRY_RUN; then
        log_info "[dry-run] Would create project '${TITLE}' under ${OWNER}"
        PROJECT_ID="PVT_DRY_RUN"
        PROJECT_NUMBER="0"
        PROJECT_URL="$(project_url_from_owner_type)"
        return 0
    fi

    # GraphQL variables are passed via -f flags below; single quotes are intentional.
    # shellcheck disable=SC2016
    create_json="$(gh_graphql '
        mutation CreateProject($ownerId: ID!, $title: String!) {
          createProjectV2(input: {
            ownerId: $ownerId
            title: $title
          }) {
            projectV2 {
              id
              number
              title
              url
            }
          }
        }
    ' -f ownerId="$OWNER_ID" -f title="$TITLE")" || die "Failed to create project '${TITLE}'"

    PROJECT_ID="$(printf '%s' "$create_json" | jq -r '.data.createProjectV2.projectV2.id')"
    PROJECT_NUMBER="$(printf '%s' "$create_json" | jq -r '.data.createProjectV2.projectV2.number')"
    PROJECT_URL="$(printf '%s' "$create_json" | jq -r '.data.createProjectV2.projectV2.url')"

    if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "null" ]; then
        die "Project creation returned no project ID"
    fi
}

link_repository_to_project() {
    if $DRY_RUN; then
        log_info "[dry-run] Would link ${OWNER}/${REPO} to project '${TITLE}'"
        return 0
    fi

    # GraphQL variables are passed via -f flags below; single quotes are intentional.
    # shellcheck disable=SC2016
    gh_graphql '
        mutation LinkProject($projectId: ID!, $repositoryId: ID!) {
          linkProjectV2ToRepository(input: {
            projectId: $projectId
            repositoryId: $repositoryId
          }) {
            repository {
              id
            }
          }
        }
    ' -f projectId="$PROJECT_ID" -f repositoryId="$REPO_ID" >/dev/null ||
        die "Failed to link ${OWNER}/${REPO} to project #${PROJECT_NUMBER}"
}

fetch_status_field_id() {
    local field_json

    # GraphQL variables are passed via -f flags below; single quotes are intentional.
    # shellcheck disable=SC2016
    field_json="$(gh_graphql '
        query StatusField($projectId: ID!) {
          node(id: $projectId) {
            ... on ProjectV2 {
              fields(first: 20) {
                nodes {
                  ... on ProjectV2SingleSelectField {
                    id
                    name
                  }
                }
              }
            }
          }
        }
    ' -f projectId="$PROJECT_ID")" || die "Failed to fetch Status field for project #${PROJECT_NUMBER}"

    printf '%s' "$field_json" | jq -r '
        .data.node?.fields?.nodes?[]?
        | select(.name == "Status")
        | .id
    ' | head -n1
}

update_status_field() {
    local status_field_id="$1"

    if [ -z "$status_field_id" ] || [ "$status_field_id" = "null" ]; then
        die "Could not locate the Status field for project #${PROJECT_NUMBER}"
    fi

    if $DRY_RUN; then
        log_info "[dry-run] Would replace Status options with the 6-option dotfiles workflow"
        return 0
    fi

    # GraphQL variables are passed via -f flags below; single quotes are intentional.
    # shellcheck disable=SC2016
    gh_graphql '
        mutation UpdateStatusField($fieldId: ID!) {
          updateProjectV2Field(input: {
            fieldId: $fieldId
            singleSelectOptions: [
              {name: "Backlog",     color: GRAY,   description: "Idea or request only"}
              {name: "Ready",       color: BLUE,   description: "Reserved — unused in normal flow"}
              {name: "In progress", color: YELLOW, description: "Issue: coding / PR: Changes requested loop"}
              {name: "In review",   color: ORANGE, description: "Awaiting review or merge decision"}
              {name: "Approved",    color: PURPLE, description: "PR only — review approved, awaiting merge"}
              {name: "Done",        color: GREEN,  description: "Merged and closed"}
            ]
          }) {
            projectV2Field {
              ... on ProjectV2SingleSelectField {
                id
              }
            }
          }
        }
    ' -f fieldId="$status_field_id" >/dev/null ||
        die "Failed to update the Status field for project #${PROJECT_NUMBER}"
}

pr_template_body() {
    cat <<'EOF'
<!--
Closes #<N> 키워드가 반드시 포함되어야 Project 보드의 Done 자동 전환이
동작합니다. 이슈를 완전히 해결하지 않는 PR은 Closes 대신 Refs 를 사용하세요.
-->

## Summary
-

## Changes
-

## Test plan
- [ ]

## Related
Closes #<N>
EOF
}

fetch_existing_pr_template() {
    if [ -z "$DEFAULT_BRANCH" ]; then
        printf ""
        return 0
    fi

    # GraphQL variables are passed via -f flags below; single quotes are intentional.
    # shellcheck disable=SC2016
    gh_graphql '
        query PullRequestTemplate($owner: String!, $repo: String!, $expr: String!) {
          repository(owner: $owner, name: $repo) {
            object(expression: $expr) {
              __typename
              ... on Blob {
                text
              }
            }
          }
        }
    ' -f owner="$OWNER" -f repo="$REPO" -f expr="${DEFAULT_BRANCH}:${PR_TEMPLATE_PATH}" |
        jq -r '.data.repository?.object?.text? // empty'
}

ensure_pr_template() {
    local existing_template encoded_content

    if $SKIP_PR_TEMPLATE; then
        log_info "Skipped PR template handling (--skip-pr-template)"
        return 0
    fi

    if [ -z "$DEFAULT_BRANCH" ]; then
        die "Repository ${OWNER}/${REPO} has no default branch. Create an initial commit first, or re-run with --skip-pr-template."
    fi

    existing_template="$(fetch_existing_pr_template)"
    if [ -n "$existing_template" ]; then
        if [[ "$existing_template" == *"Closes #"* ]]; then
            log_info "PR template already exists and contains 'Closes #'"
        else
            log_warning "PR template already exists but does not contain 'Closes #'. It was left untouched."
        fi
        return 0
    fi

    if $DRY_RUN; then
        log_info "[dry-run] Would create ${PR_TEMPLATE_PATH} on ${DEFAULT_BRANCH}"
        return 0
    fi

    encoded_content="$(pr_template_body | base64 | tr -d '\n')"
    gh api \
        --hostname "${HOST:-github.com}" \
        --method PUT \
        -H "Accept: application/vnd.github+json" \
        "repos/${OWNER}/${REPO}/contents/${PR_TEMPLATE_PATH}" \
        -f message="${PR_TEMPLATE_COMMIT_MESSAGE}" \
        -f content="${encoded_content}" \
        -f branch="${DEFAULT_BRANCH}" >/dev/null ||
        die "Failed to create ${PR_TEMPLATE_PATH} in ${OWNER}/${REPO}"

    log_success "Created ${PR_TEMPLATE_PATH} on ${DEFAULT_BRANCH}"
}

project_url_from_owner_type() {
    local prefix="users"
    if [ "$OWNER_TYPE" = "Organization" ]; then
        prefix="orgs"
    fi
    printf "https://%s/%s/%s/projects/%s" "$HOST" "$prefix" "$OWNER" "$PROJECT_NUMBER"
}

workflows_url_from_owner_type() {
    local prefix="users"
    if [ "$OWNER_TYPE" = "Organization" ]; then
        prefix="orgs"
    fi
    printf "https://%s/%s/%s/projects/%s/workflows" "$HOST" "$prefix" "$OWNER" "$PROJECT_NUMBER"
}

workflow_deep_link() {
    local type="$1"
    local base_url
    base_url="$(workflows_url_from_owner_type)"

    case "$type" in
        "auto-add") echo "${base_url}/auto_add_items" ;;
        "item-added") echo "${base_url}/item_added_to_project" ;;
        "pr-linked") echo "${base_url}/pull_request_linked_to_issue" ;;
        "review-approved") echo "${base_url}/review_approved" ;;
        "changes-requested") echo "${base_url}/review_changes_requested" ;;
        "pr-merged") echo "${base_url}/pull_request_merged" ;;
        "item-closed") echo "${base_url}/item_closed" ;;
        "auto-archive") echo "${base_url}/auto_archive" ;;
        *) echo "${base_url}" ;;
    esac
}

print_final_report() {
    local auto_archive_filter="is:issue,pr is:closed updated:<@today-${AUTO_ARCHIVE_WINDOW}"
    local y="${UX_WARNING}"
    local r="${UX_RESET}"

    WORKFLOWS_URL="$(workflows_url_from_owner_type)"
    if [ -z "$PROJECT_URL" ] || [ "$PROJECT_URL" = "null" ]; then
        PROJECT_URL="$(project_url_from_owner_type)"
    fi

    ux_header "Kanban Board Ready"
    log_success "Project board setup finished for ${OWNER}/${REPO}"
    ux_section "Project"
    ux_bullet "Board: ${PROJECT_URL}"
    ux_bullet "Workflows: ${WORKFLOWS_URL}"
    ux_bullet "Project number: ${PROJECT_NUMBER}"

    ux_section "UI Checklist"
    ux_bullet "Auto-add to project: choose ${OWNER}/${REPO} and set filter to 'is:issue,pr is:open' so new open issues and PRs land on the board."
    ux_bullet_sub "Link: $(workflow_deep_link "auto-add")"
    ux_bullet "Item added to project: set Status to ${y}'Backlog'${r} so every new card starts in the intake column."
    ux_bullet_sub "Link: $(workflow_deep_link "item-added")"
    ux_bullet "Pull request linked to issue: ${y}DISABLE this workflow${r} per SSOT decision dEitY719/dotfiles#289. Issues do not visit 'In review' — the column is PR-only. Leaving this enabled wrongly moves Issue cards into review when a PR links them."
    ux_bullet_sub "Link: $(workflow_deep_link "pr-linked")"
    ux_bullet "Code review approved: set Status to ${y}'Approved'${r} so PR cards reflect the pre-merge state."
    ux_bullet_sub "Link: $(workflow_deep_link "review-approved")"
    ux_bullet "Code changes requested: set Status to ${y}'In progress'${r} so PR cards loop back during review feedback."
    ux_bullet_sub "Link: $(workflow_deep_link "changes-requested")"
    ux_bullet "Pull request merged: set Status to ${y}'Done'${r} so merged PR cards exit the active flow."
    ux_bullet_sub "Link: $(workflow_deep_link "pr-merged")"
    ux_bullet "Item closed: set Status to ${y}'Done'${r} so closed issues and PRs finish cleanly."
    ux_bullet_sub "Link: $(workflow_deep_link "item-closed")"
    ux_bullet "Auto-archive items: enable it with '${auto_archive_filter}' so stale Done cards leave the board automatically."
    ux_bullet_sub "Link: $(workflow_deep_link "auto-archive")"

    if $HIDE_COLUMNS; then
        ux_bullet "Board view: hide ${y}'Approved'${r} and ${y}'Ready'${r} if this is a solo repo and you want to reduce dead columns."
    fi

    ux_section "Smoke Test"
    # Printed verbatim for the user to paste, and mirrored in
    # references/ui-checklist.md — keep both host-pinned and identical.
    # `--repo` names a repo but no host, so without the prefix this write
    # follows `gh repo set-default` to whichever server that points at
    # (dEitY719/dotfiles#1403/dEitY719/dotfiles#1407). This runs after detect_host, so HOST is resolved.
    ux_bullet "GH_HOST=\"${HOST}\" gh issue create --repo ${OWNER}/${REPO} --title \"[Test] kanban smoke\" --body \"ignore\""

    if $DRY_RUN; then
        ux_section "Mode"
        ux_bullet "Dry-run only: no project, link, field, or file mutations were sent."
    fi
}

main() {
    parse_args "$@"
    require_command gh "Install GitHub CLI: https://cli.github.com/"
    require_command jq "Install jq to parse GitHub API responses."
    # detect_host MUST precede require_project_scope so GHE token scopes
    # are validated against the correct host (PR dEitY719/dotfiles#702 review feedback).
    detect_host
    require_project_scope

    ux_header "Kanban Board Setup"
    log_step 1 "Validating repository access"
    load_repo_context
    log_info "Repository found: ${REPO_URL}"

    log_step 2 "Checking for an existing project titled '${TITLE}'"
    if find_existing_project; then
        PROJECT_URL="${PROJECT_URL:-$(project_url_from_owner_type)}"
        log_warning "A project titled '${TITLE}' already exists (#${PROJECT_NUMBER}). Delete it first if you need a fresh install."
        ux_section "Existing Project"
        ux_bullet "Board: ${PROJECT_URL}"
        ux_bullet "Workflows: $(workflows_url_from_owner_type)"
        exit 0
    fi

    log_step 3 "Creating the project"
    create_project
    log_success "Project prepared: ${TITLE} (#${PROJECT_NUMBER})"

    log_step 4 "Linking the repository"
    link_repository_to_project
    log_success "Linked ${OWNER}/${REPO}"

    log_step 5 "Replacing the Status options"
    if $DRY_RUN; then
        log_info "[dry-run] Would replace Status options with the 6-option dotfiles workflow"
    else
        update_status_field "$(fetch_status_field_id)"
    fi
    log_success "Status field synced to the 6-option workflow"

    log_step 6 "Ensuring the pull request template"
    ensure_pr_template

    log_step 7 "Printing the remaining UI checklist"
    print_final_report
}

main "$@"
