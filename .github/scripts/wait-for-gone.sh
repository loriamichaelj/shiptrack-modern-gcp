#!/usr/bin/env bash
# Wait until no resource of the given Compute kinds is left in the project, for up to 15 minutes (ADR-0039).
# Usage: GCP_PROJECT_ID=<id> .github/scripts/wait-for-gone.sh "<what is waited for>" <kind>...
# A kind is a `gcloud compute` collection such as forwarding-rules. Fails if the project still has any of them
# after the deadline, or if a kind cannot be listed. Names are never printed, only counts.
set -euo pipefail

what=${1:?usage: wait-for-gone.sh "<what>" <kind>...}
shift
(($# > 0)) || { echo "usage: wait-for-gone.sh \"<what>\" <kind>..." >&2; exit 2; }
: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
echo "::add-mask::$GCP_PROJECT_ID"

deadline=$((SECONDS + 900))
while true; do
  left=0
  for kind in "$@"; do
    if ! names=$(gcloud compute "$kind" list --project "$GCP_PROJECT_ID" --format='value(name)' 2>/dev/null); then
      echo "::error::Could not list $kind."
      exit 1
    fi
    count=$(grep -c . <<<"$names" || true)
    ((count == 0)) || echo "$kind: $count left"
    left=$((left + count))
  done
  ((left == 0)) && break
  ((SECONDS < deadline)) || { echo "::error::${what} still there after 15 minutes. The steps after this one did not run."; exit 1; }
  sleep 15
done
echo "${what} gone."
