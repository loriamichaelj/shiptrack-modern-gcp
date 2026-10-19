#!/usr/bin/env bash
# Deletes every shipment and its proof-of-delivery files, and optionally seeds five demo shipments, by running
# deploy/reset-data/job.yaml in the cluster from the image the api runs (ADR-0036). ops-reset-data runs it.
# Usage: scripts/reset-data.sh <delete-all-shipments> <yes|no>
#
# Stop the live traffic and let the events queue drain first: an event for a shipment that is gone fails to
# apply, is retried, and ends in the dead-letter subscription, which alerts.
#
# Environment: GCP_PROJECT_ID and GCP_PROOF_OF_DELIVERY_BUCKET (required). Needs kubectl with credentials for
# the cluster, and envsubst. Prints the Job's RESET_DATA and SEEDED lines, and its last lines with any host
# withheld when it fails.
set -euo pipefail

confirm=${1:?usage: reset-data.sh <delete-all-shipments> <yes|no>}
seed=${2:?usage: reset-data.sh <delete-all-shipments> <yes|no>}
[[ "$confirm" == delete-all-shipments ]] || { echo "refused: the first argument must be delete-all-shipments" >&2; exit 1; }
[[ "$seed" == yes || "$seed" == no ]] || { echo "the second argument must be yes or no" >&2; exit 1; }
: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
: "${GCP_PROOF_OF_DELIVERY_BUCKET:?GCP_PROOF_OF_DELIVERY_BUCKET is required}"

namespace=shiptrack
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
configmap="shiptrack-reset-data-$(date -u +%Y%m%d%H%M%S)"

image=$(kubectl -n "$namespace" get deployment shiptrack-api -o jsonpath='{.spec.template.spec.containers[0].image}')
[[ -n "$image" ]] || { echo "the api Deployment was not found; deploy the application first" >&2; exit 1; }

kubectl -n "$namespace" create configmap "$configmap" \
  --from-file=reset_data.py="$here/deploy/reset-data/reset_data.py" >/dev/null
trap 'kubectl -n "$namespace" delete configmap "$configmap" --ignore-not-found >/dev/null' EXIT

# shellcheck disable=SC2016 # envsubst reads these names; the shell must not expand them
job=$(IMAGE="$image" RESET_CONFIGMAP="$configmap" RESET_SEED="$seed" \
  envsubst '${IMAGE} ${GCP_PROJECT_ID} ${RESET_CONFIGMAP} ${RESET_SEED} ${GCP_PROOF_OF_DELIVERY_BUCKET}' \
  <"$here/deploy/reset-data/job.yaml" | kubectl create -f - -o name)
echo "created ${job}"

# The deadline is the Job's activeDeadlineSeconds (600 s), plus time for a Spot node to come up.
succeeded="" failed=""
for _ in $(seq 1 80); do
  succeeded=$(kubectl -n "$namespace" get "$job" -o jsonpath='{.status.succeeded}')
  failed=$(kubectl -n "$namespace" get "$job" -o jsonpath='{.status.failed}')
  [[ "$succeeded" == 1 || "${failed:-0}" -ge 1 ]] && break
  sleep 10
done

logs=$(kubectl -n "$namespace" logs "$job" --all-containers --tail=60 2>&1 || true)
if [[ "$succeeded" == 1 ]]; then
  grep -E '^(RESET_DATA |SEEDED )' <<<"$logs" || true
  exit 0
fi

echo "::error::the reset did not finish (succeeded=${succeeded:-0} failed=${failed:-0})"
# What the database part reported, if it got that far, then the end of the log with any address withheld.
grep -E '^(RESET_DATA |SEEDED )' <<<"$logs" || true
sed -E -e 's/("host": ")[^"]*/\1<HOST>/g' -e 's/(host=)[^ ]+/\1<HOST>/g' \
  -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<ADDRESS>/g' <<<"$logs" | tail -20
exit 1
