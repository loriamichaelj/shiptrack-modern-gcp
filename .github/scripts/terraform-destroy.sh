#!/usr/bin/env bash
# Take down one resource group of one Terraform root (ADR-0027). Run by the destroy-* workflows as
# shiptrack-apply, in the dev environment, in two jobs that each need an approval.
# Usage: .github/scripts/terraform-destroy.sh <root> plan|destroy <name> <target>...
#
# plan     shows the addresses and actions a destroy of the targets would make, including the
#          dependents Terraform adds to a targeted destroy.
# destroy  makes a fresh plan and applies that plan in the same run; no plan file leaves the runner.
#
# Both modes fail unless the CONFIRM environment variable equals <name>. As in terraform-ci.sh, only
# addresses and actions are printed.
#
# A protected resource (Cloud SQL) cannot be destroyed while its protection is on, and the provider
# reads the stored value when it deletes. When UNPROTECT_VAR names a Terraform variable, `destroy`
# first applies the targets with that variable set to false, then destroys them with it still false.
# The next normal apply sets the protection back for anything that remains (ADR-0027).
#
# Environment:
#   CONFIRM              the value the person typed; must equal <name> (required)
#   UNPROTECT_VAR        optional; a boolean variable that protects the targets while it is true
#   GCP_PROJECT_ID       project that holds the resources (required)
#   GCP_PROJECT_NUMBER   its number; part of the state bucket's name (required)
#   GCP_REGION           region (default us-central1)
set -euo pipefail

root=${1:?usage: terraform-destroy.sh <root> plan|destroy <name> <target>...}
mode=${2:?usage: terraform-destroy.sh <root> plan|destroy <name> <target>...}
name=${3:?usage: terraform-destroy.sh <root> plan|destroy <name> <target>...}
shift 3
(($# > 0)) || { echo "no targets given" >&2; exit 2; }
[[ "$root" =~ ^(data|cluster|addons)$ ]] || { echo "unknown root: $root" >&2; exit 2; }
[[ "$mode" == plan || "$mode" == destroy ]] || { echo "unknown mode: $mode" >&2; exit 2; }
: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
: "${GCP_PROJECT_NUMBER:?GCP_PROJECT_NUMBER is required}"

if [[ "${CONFIRM:-}" != "$name" ]]; then
  echo "::error::The confirmation does not match. Type ${name} to take it down."
  exit 1
fi

export TF_VAR_project_id=$GCP_PROJECT_ID
export TF_VAR_project_number=$GCP_PROJECT_NUMBER
export TF_VAR_region=${GCP_REGION:-us-central1}
export CLOUDSDK_CORE_PROJECT=$GCP_PROJECT_ID
export TF_IN_AUTOMATION=1 TF_INPUT=0

cd "$(dirname "${BASH_SOURCE[0]}")/../../terraform/${root}"

bucket="shiptrack-tfstate-${GCP_PROJECT_NUMBER}"
echo "::add-mask::$GCP_PROJECT_ID"
echo "::add-mask::$GCP_PROJECT_NUMBER"
echo "::add-mask::$bucket"

log() { printf '%s\n' "$*"; }

redact() { sed -e "s/${GCP_PROJECT_ID}/***/g" -e "s/${GCP_PROJECT_NUMBER}/***/g"; }

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

# summarize <plan> <step>: the addresses and actions of a saved plan, never values.
summarize() {
  local plan=$1 step=$2 text
  text=$(terraform show -json "$plan" | jq -r '
    [.resource_changes[]? | select(.change.actions != ["no-op"] and .change.actions != ["read"])] as $changes
    | (if ($changes | length) == 0 then "Nothing to change."
       else ($changes | map("- `\(.change.actions | join("+"))` \(.address)") | join("\n")) end)
      + "\n\n\($changes | length) resource change(s).\n"')
  log "$text"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf '## destroy %s: %s (%s)\n\n%s\n' "$name" "$step" "$mode" "$text" >>"$GITHUB_STEP_SUMMARY"
  fi
}

cat >backend.tf <<BACKEND
terraform {
  backend "gcs" {
    bucket = "${bucket}"
    prefix = "gcp/${root}"
  }
}
BACKEND

targets=()
for address in "$@"; do targets+=("-target=${address}"); done

unprotect=()
if [[ -n "${UNPROTECT_VAR:-}" ]]; then
  [[ "$UNPROTECT_VAR" =~ ^[a-z_]+$ ]] || { echo "bad UNPROTECT_VAR" >&2; exit 2; }
  unprotect=(-var "${UNPROTECT_VAR}=false")
fi

quietly terraform init -input=false

if [[ "$mode" == destroy && ${#unprotect[@]} -gt 0 ]]; then
  log "Lowering the protection (${UNPROTECT_VAR}) on the targets."
  quietly terraform plan -input=false -lock-timeout=120s "${targets[@]}" "${unprotect[@]}" -out=unprotect.tfplan
  summarize unprotect.tfplan "lower the protection"
  quietly terraform apply -input=false -lock-timeout=120s unprotect.tfplan
fi

quietly terraform plan -destroy -input=false -lock-timeout=120s "${targets[@]}" "${unprotect[@]}" -out=tfplan
summarize tfplan "destroy"

if [[ "$mode" == destroy ]]; then
  quietly terraform apply -input=false -lock-timeout=120s tfplan
  log "Destroy complete."
fi
