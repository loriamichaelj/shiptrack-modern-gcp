#!/usr/bin/env bash
# Plan or apply one Terraform root (data, cluster, addons, or finops) against the state bucket the seed
# root created. Run by ci-terraform.yml (plan, as shiptrack-plan) and apply-terraform.yml (apply, as
# shiptrack-apply).
# Usage: .github/scripts/terraform-ci.sh <root> plan|apply
#
# plan   never locks or writes state (-lock=false), so the read-only plan account can run it. The
#        addons root is planned with -refresh=false: refreshing its Kubernetes objects needs the
#        cluster's RBAC, which the plan account does not have. A root
#        that has never been applied has no state object, and `terraform init` would have to write
#        an empty one, which the plan account may not do; such a root is planned against empty local
#        state, which shows every resource as a create.
# apply  makes a fresh plan and applies that plan in the same run; no plan file leaves the runner.
#
# The repository is public, so output is limited to resource addresses and actions: plan attribute
# values are never printed, uploaded, or commented.
#
# Environment:
#   GCP_PROJECT_ID       project that holds the resources (required)
#   GCP_PROJECT_NUMBER   its number; part of the state bucket's name (required)
#   GCP_REGION           region (default us-central1)
#   GCP_BILLING_ACCOUNT_ID  billing account of the project (required for finops)
#   GCP_ALERT_EMAIL         address for budget alerts (required for finops)
#   SUMMARY_FILE         optional; the summary is also appended here, for the pull request comment
set -euo pipefail

root=${1:?usage: terraform-ci.sh <root> plan|apply}
mode=${2:?usage: terraform-ci.sh <root> plan|apply}
[[ "$root" =~ ^(data|cluster|addons|finops)$ ]] || { echo "unknown root: $root" >&2; exit 2; }
[[ "$mode" == plan || "$mode" == apply ]] || { echo "unknown mode: $mode" >&2; exit 2; }
: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
: "${GCP_PROJECT_NUMBER:?GCP_PROJECT_NUMBER is required}"

if [[ "$root" == finops ]]; then
  : "${GCP_BILLING_ACCOUNT_ID:?GCP_BILLING_ACCOUNT_ID is required for finops}"
  : "${GCP_ALERT_EMAIL:?GCP_ALERT_EMAIL is required for finops}"
  export TF_VAR_billing_account_id=$GCP_BILLING_ACCOUNT_ID
  export TF_VAR_alert_email=$GCP_ALERT_EMAIL
  echo "::add-mask::$GCP_BILLING_ACCOUNT_ID"
  echo "::add-mask::$GCP_ALERT_EMAIL"
fi
export TF_VAR_project_id=$GCP_PROJECT_ID
export TF_VAR_project_number=$GCP_PROJECT_NUMBER
export TF_VAR_region=${GCP_REGION:-us-central1}
export CLOUDSDK_CORE_PROJECT=$GCP_PROJECT_ID
export TF_IN_AUTOMATION=1 TF_INPUT=0

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source-path=SCRIPTDIR source=redact.sh
source "$here/redact.sh"

cd "$here/../../terraform/${root}"

bucket="shiptrack-tfstate-${GCP_PROJECT_NUMBER}"
echo "::add-mask::$GCP_PROJECT_ID"
echo "::add-mask::$GCP_PROJECT_NUMBER"
echo "::add-mask::$bucket"

log() { printf '%s\n' "$*"; }

# Run a terraform command quietly; show its output (redacted) only if it fails.
quietly() {
  local out
  out=$(mktemp)
  if ! "$@" >"$out" 2>&1; then
    print_failure "$out"
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
    printf '## %s %s\n\n%s\n' "$root" "$mode" "$text" >>"$GITHUB_STEP_SUMMARY"
  fi
  if [[ -n "${SUMMARY_FILE:-}" ]]; then
    printf '### %s\n\n%s\n' "$root" "$text" >>"$SUMMARY_FILE"
  fi
}

# Prints "exists" or "missing"; fails on anything else (for example access denied).
state_object_state() {
  local output
  if output=$(gcloud storage objects describe "gs://${bucket}/gcp/${root}/default.tfstate" --format='value(name)' 2>&1); then
    echo exists
  elif grep -qE '404|does not exist|not found|NOT_FOUND' <<<"$output"; then
    echo missing
  else
    local failure
    failure=$(mktemp)
    printf '%s\n' "$output" >"$failure"
    echo "state check failed:" >&2
    print_failure "$failure"
    rm -f "$failure"
    return 1
  fi
}

# The backend names the state bucket, so it is written here and never committed (ADR-0016).
write_backend() {
  cat >backend.tf <<BACKEND
terraform {
  backend "gcs" {
    bucket = "${bucket}"
    prefix = "gcp/${root}"
  }
}
BACKEND
}

if [[ "$mode" == apply ]]; then
  write_backend
else
  state=$(state_object_state)
  log "state of ${root}: ${state}"
  if [[ "$state" == exists ]]; then
    write_backend
  else
    log "Never applied: planning against empty local state."
  fi
fi

quietly terraform init -input=false

if [[ "$mode" == plan ]]; then
  plan_flags=()
  [[ "$root" == addons ]] && plan_flags+=(-refresh=false)
  quietly terraform plan -input=false -lock=false ${plan_flags[@]+"${plan_flags[@]}"} -out=tfplan
  summarize tfplan
  exit 0
fi

quietly terraform plan -input=false -lock-timeout=120s -out=tfplan
summarize tfplan
quietly terraform apply -input=false -lock-timeout=120s tfplan
log "Apply complete."
