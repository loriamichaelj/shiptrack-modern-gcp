#!/usr/bin/env bash
# Take down one resource group of one Terraform root, or the whole root (ADR-0027, ADR-0039). Run by the
# destroy-* workflows as shiptrack-apply, in the dev environment, in two jobs that each need an approval.
# Usage: .github/scripts/terraform-destroy.sh <root> plan|destroy <name> [<target>...]
#
# plan     shows the addresses and actions a destroy of the targets would make, including the
#          dependents Terraform adds to a targeted destroy. With no target it is the whole root.
# destroy  makes a fresh plan and applies that plan in the same run; no plan file leaves the runner.
#
# Both modes fail unless the CONFIRM environment variable equals <name>. As in terraform-ci.sh, only
# addresses and actions are printed.
#
# A protected resource (Cloud SQL) cannot be destroyed while its protection is on, and the provider
# reads the stored value when it deletes. When UNPROTECT_VAR names Terraform variables, `destroy`
# first applies the targets with those variables set to false, then destroys them with them still false.
# The next normal apply sets the protection back for anything that remains (ADR-0027). A run with no
# target destroys a whole root, so UNPROTECT_TARGETS names what the first step applies: a plan without
# a target would apply every pending change of the root.
#
# Environment:
#   CONFIRM              the value the person typed; must equal <name> (required)
#   UNPROTECT_VAR        optional; boolean variables, separated by spaces, that protect the targets while true
#   UNPROTECT_TARGETS    addresses, separated by spaces, that the unprotecting step applies; defaults to the
#                        targets and is required when there are none
#   DESTROY_ATTEMPTS     how many times `destroy` plans and applies again after a failure (default 1). Google
#                        releases the private services connection some minutes after Cloud SQL is gone, so a
#                        first try at the network can fail and a later one pass
#   RETRY_WAIT_SECONDS   wait between attempts (default 300)
#   GCP_PROJECT_ID       project that holds the resources (required)
#   GCP_PROJECT_NUMBER   its number; part of the state bucket's name (required)
#   GCP_REGION           region (default us-central1)
#   GCP_ALERT_EMAIL      address for the monitoring alerts (required for the data root, whose plan needs it)
set -euo pipefail

root=${1:?usage: terraform-destroy.sh <root> plan|destroy <name> [<target>...]}
mode=${2:?usage: terraform-destroy.sh <root> plan|destroy <name> [<target>...]}
name=${3:?usage: terraform-destroy.sh <root> plan|destroy <name> [<target>...]}
shift 3
[[ "$root" =~ ^(data|cluster|addons)$ ]] || { echo "unknown root: $root" >&2; exit 2; }
[[ "$mode" == plan || "$mode" == destroy ]] || { echo "unknown mode: $mode" >&2; exit 2; }
: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
: "${GCP_PROJECT_NUMBER:?GCP_PROJECT_NUMBER is required}"

if [[ "${CONFIRM:-}" != "$name" ]]; then
  echo "::error::The confirmation does not match. Type ${name} to take it down."
  exit 1
fi

if [[ "$root" == data ]]; then
  : "${GCP_ALERT_EMAIL:?GCP_ALERT_EMAIL is required for the data root}"
  export TF_VAR_alert_email=$GCP_ALERT_EMAIL
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
    printf '## destroy %s, %s root: %s (%s)\n\n%s\n' "$name" "$root" "$step" "$mode" "$text" >>"$GITHUB_STEP_SUMMARY"
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
read -ra unprotect_vars <<<"${UNPROTECT_VAR:-}"
for var in ${unprotect_vars[@]+"${unprotect_vars[@]}"}; do
  [[ "$var" =~ ^[a-z_]+$ ]] || { echo "bad UNPROTECT_VAR" >&2; exit 2; }
  unprotect+=(-var "${var}=false")
done

unprotect_targets=("${targets[@]+"${targets[@]}"}")
if [[ -n "${UNPROTECT_TARGETS:-}" ]]; then
  unprotect_targets=()
  for address in $UNPROTECT_TARGETS; do unprotect_targets+=("-target=${address}"); done
fi
if [[ ${#unprotect[@]} -gt 0 && ${#unprotect_targets[@]} -eq 0 ]]; then
  echo "UNPROTECT_TARGETS is required when there are no targets" >&2
  exit 2
fi

attempts=${DESTROY_ATTEMPTS:-1}
retry_wait=${RETRY_WAIT_SECONDS:-300}
[[ "$attempts" =~ ^[1-9][0-9]?$ && "$retry_wait" =~ ^[0-9]+$ ]] || { echo "bad DESTROY_ATTEMPTS or RETRY_WAIT_SECONDS" >&2; exit 2; }

quietly terraform init -input=false

if [[ "$mode" == destroy && ${#unprotect[@]} -gt 0 ]]; then
  log "Lowering the protection (${UNPROTECT_VAR}) on the targets."
  quietly terraform plan -input=false -lock-timeout=120s "${unprotect_targets[@]}" "${unprotect[@]}" -out=unprotect.tfplan
  summarize unprotect.tfplan "lower the protection"
  quietly terraform apply -input=false -lock-timeout=120s unprotect.tfplan
fi

attempt=1
while true; do
  quietly terraform plan -destroy -input=false -lock-timeout=120s ${targets[@]+"${targets[@]}"} ${unprotect[@]+"${unprotect[@]}"} -out=tfplan
  summarize tfplan "destroy"
  [[ "$mode" == destroy ]] || break
  if quietly terraform apply -input=false -lock-timeout=120s tfplan; then
    log "Destroy complete."
    break
  fi
  if ((attempt >= attempts)); then
    echo "::error::The destroy failed after ${attempt} attempt(s)."
    exit 1
  fi
  log "Attempt ${attempt} of ${attempts} failed; planning again in ${retry_wait} s."
  sleep "$retry_wait"
  attempt=$((attempt + 1))
done
