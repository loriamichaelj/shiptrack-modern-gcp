#!/usr/bin/env bash
# Plan or apply the bootstrap configuration. Run by .github/workflows/apply-bootstrap.yml.
# Usage: terraform/bootstrap/scripts/ci.sh plan|apply
#
# State lives in the bucket this configuration creates, so the first run is special:
#   1. create only the state bucket, with local state,
#   2. generate backend.tf and migrate the local state into the bucket,
#   3. plan and apply everything else (APIs, service accounts, trust, permissions) with remote
#      state.
# Keeping step 1 to one resource makes the window in which state could be lost as small as
# possible: a failure after step 2 leaves recoverable remote state instead of a lost local file
# on an ephemeral runner.
#
# Output is limited to resource addresses and actions: the repository is public, so plan
# attribute values are never printed or uploaded.
#
# Environment:
#   GCP_PROJECT_ID              project that holds the bucket and service accounts (required)
#   GCP_PROJECT_NUMBER          its number; part of the bucket name and of every principal (required)
#   GCP_REGION                  region of the state bucket (default us-central1)
#   GCP_WORKLOAD_IDENTITY_POOL  ID of the Workload Identity pool (default github)
#   TF_VAR_github_org           GitHub user or organization (required)
#   TF_VAR_github_owner_id      numeric ID of that owner (required)
#   TF_VAR_github_repo          this repository's name (required)
#   TF_VAR_github_repository_id numeric ID of this repository (required)
set -euo pipefail

mode=${1:?usage: ci.sh plan|apply}
[[ "$mode" == plan || "$mode" == apply ]] || { echo "unknown mode: $mode" >&2; exit 2; }
: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
: "${GCP_PROJECT_NUMBER:?GCP_PROJECT_NUMBER is required}"
: "${TF_VAR_github_org:?TF_VAR_github_org is required}"
: "${TF_VAR_github_owner_id:?TF_VAR_github_owner_id is required}"
: "${TF_VAR_github_repo:?TF_VAR_github_repo is required}"
: "${TF_VAR_github_repository_id:?TF_VAR_github_repository_id is required}"

region=${GCP_REGION:-us-central1}
export TF_VAR_project_id=$GCP_PROJECT_ID
export TF_VAR_project_number=$GCP_PROJECT_NUMBER
export TF_VAR_region=$region
export TF_VAR_workload_identity_pool_id=${GCP_WORKLOAD_IDENTITY_POOL:-github}
export CLOUDSDK_CORE_PROJECT=$GCP_PROJECT_ID
export TF_IN_AUTOMATION=1 TF_INPUT=0

cd "$(dirname "${BASH_SOURCE[0]}")/.."

bucket="shiptrack-tfstate-${GCP_PROJECT_NUMBER}"
state_prefix="gcp/bootstrap"
state_object="${state_prefix}/default.tfstate"

echo "::add-mask::$GCP_PROJECT_ID"
echo "::add-mask::$GCP_PROJECT_NUMBER"
echo "::add-mask::$bucket"

log() { printf '%s\n' "$*"; }

# Hide the project and its number from anything printed on a failure.
redact() { sed -e "s/${GCP_PROJECT_ID}/***/g" -e "s/${GCP_PROJECT_NUMBER}/***/g"; }

# Prints "exists" or "missing"; fails on anything else (for example access denied).
bucket_state() {
  local output
  if output=$(gcloud storage buckets describe "gs://${bucket}" --format='value(name)' 2>&1); then
    echo exists
  elif grep -qE '404|does not exist|NOT_FOUND' <<<"$output"; then
    echo missing
  else
    echo "bucket check failed: $(redact <<<"$output")" >&2
    return 1
  fi
}

write_backend() {
  cat >backend.tf <<BACKEND
terraform {
  backend "gcs" {
    bucket = "${bucket}"
    prefix = "${state_prefix}"
  }
}
BACKEND
}

# Run a terraform command quietly; show its output only if it fails.
quietly() {
  local out
  out=$(mktemp)
  if ! "$@" >"$out" 2>&1; then
    redact <"$out" >&2
    rm -f "$out"
    return 1
  fi
  rm -f "$out"
}

# Print the changes in a saved plan: addresses and actions, never values.
summarize() {
  local plan=$1 text
  text=$(terraform show -json "$plan" | jq -r '
    [.resource_changes[]? | select(.change.actions != ["no-op"] and .change.actions != ["read"])] as $changes
    | (if ($changes | length) == 0 then "No changes."
       else ($changes | map("- `\(.change.actions | join("+"))` \(.address)") | join("\n")) end)
      + "\n\n\($changes | length) resource change(s).\n"')
  log "$text"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '## Bootstrap %s\n\n%s\n' "$mode" "$text" >>"$GITHUB_STEP_SUMMARY"
  fi
}

plan_to() {
  local plan=$1
  shift
  quietly terraform plan -input=false -lock-timeout=120s -out="$plan" "$@"
}

state=$(bucket_state)
log "state bucket: $state"
[[ "$state" == exists ]] && write_backend
quietly terraform init -input=false

if [[ "$mode" == plan ]]; then
  if [[ "$state" == missing ]]; then
    log "First run: the state bucket does not exist yet. Planning the bucket only."
    plan_to tfplan -target=google_storage_bucket.state
  else
    plan_to tfplan
  fi
  summarize tfplan
  exit 0
fi

if [[ "$state" == missing ]]; then
  log "First run: creating the state bucket with local state."
  plan_to seed.tfplan -target=google_storage_bucket.state
  summarize seed.tfplan
  quietly terraform apply -input=false seed.tfplan
  write_backend
  log "Migrating state into the bucket."
  quietly terraform init -migrate-state -force-copy -input=false
  gcloud storage objects describe "gs://${bucket}/${state_object}" >/dev/null
  log "State is now stored remotely."
fi

plan_to tfplan
summarize tfplan
quietly terraform apply -input=false tfplan
log "Apply complete."
