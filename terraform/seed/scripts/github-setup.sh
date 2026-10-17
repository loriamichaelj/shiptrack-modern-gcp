#!/usr/bin/env bash
# One-time GitHub settings for the ShipTrack GCP repository (the same settings as the platform
# repository, so the two approve and protect alike). Run by a human with admin rights; needs an
# authenticated `gh`. Safe to re-run.
#
#   - environments `dev`, `ci`, and (with --seed-env) `seed`: you are the required reviewer.
#     Only the `dev` branch may deploy to `dev` and `seed`; `ci` runs pull request checks, so
#     it has approval and no branch rule
#   - branch protection on `dev`: no direct push, for administrators too; changes arrive by pull
#     request, with no force push or deletion
#   - Actions: read-only default token, approval required for every outside contributor
#   - secret scanning and push protection on
#
# Usage: github-setup.sh [--dry-run] [--seed-env] [--check NAME]... <owner>/<repo>
set -euo pipefail

dry_run=false
seed_env=false
checks=()
repo=""
branch=dev

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry_run=true ;;
    --seed-env) seed_env=true ;;
    --check) shift; checks+=("${1:?--check needs a name}") ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) repo=$1 ;;
  esac
  shift
done
[[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || { echo "usage: $0 [--dry-run] [--seed-env] [--check NAME]... <owner>/<repo>" >&2; exit 2; }

failed=0
api() { # api <method> <path> <json-body>
  local method=$1 path=$2 body=$3
  if $dry_run; then
    printf 'gh api -X %s %s\n  %s\n' "$method" "$path" "$body"
    return 0
  fi
  if gh api -X "$method" "$path" --input - <<<"$body" >/dev/null; then
    echo "ok      $method $path"
  else
    echo "FAILED  $method $path" >&2
    failed=$((failed + 1))
  fi
}

user_id=$(gh api user --jq .id)

setup_environment() { # setup_environment <name> <only-dev-branch: true|false>
  local name=$1 branch_rule=$2 policy=null
  $branch_rule && policy='{"protected_branches":false,"custom_branch_policies":true}'
  api PUT "repos/$repo/environments/$name" "$(jq -nc --argjson id "$user_id" --argjson policy "$policy" '{
    wait_timer: 0,
    prevent_self_review: false,
    reviewers: [{type: "User", id: $id}],
    deployment_branch_policy: $policy
  }')"
  if $branch_rule; then
    api POST "repos/$repo/environments/$name/deployment-branch-policies" \
      "$(jq -nc --arg b "$branch" '{name: $b, type: "branch"}')"
  fi
}

setup_environment dev true
# Pull request checks run in `ci`. A pull request run uses a pull request ref, not `dev`, so this
# environment has approval but no branch rule (ADR-0025).
setup_environment ci false
$seed_env && setup_environment seed true

if [[ ${#checks[@]} -gt 0 ]]; then
  status_checks=$(printf '%s\n' "${checks[@]}" | jq -R . | jq -sc '{strict: false, contexts: .}')
else
  status_checks=null
fi
api PUT "repos/$repo/branches/$branch/protection" "$(jq -nc --argjson checks "$status_checks" '{
  required_status_checks: $checks,
  enforce_admins: true,
  required_pull_request_reviews: {required_approving_review_count: 0, dismiss_stale_reviews: true},
  restrictions: null,
  allow_force_pushes: false,
  allow_deletions: false,
  required_conversation_resolution: true
}')"

api PUT "repos/$repo/actions/permissions/workflow" \
  '{"default_workflow_permissions":"read","can_approve_pull_request_reviews":false}'
api PUT "repos/$repo/actions/permissions/fork-pr-contributor-approval" \
  '{"approval_policy":"all_external_contributors"}'
api PATCH "repos/$repo" \
  '{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}'

if [[ $failed -gt 0 ]]; then
  echo "$failed call(s) failed" >&2
  exit 1
fi
