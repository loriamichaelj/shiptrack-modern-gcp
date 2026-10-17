#!/usr/bin/env bash
# Opens and closes the browser URL of the application from your machine (ADR-0031).
#
#   scripts/ui-access.sh open      set the allow-list to your current public address, then dispatch ops-ui-port open
#   scripts/ui-access.sh ip        set the allow-list to your current public address, and do nothing else
#   scripts/ui-access.sh close     dispatch ops-ui-port close: admits nobody
#   scripts/ui-access.sh remove    dispatch ops-ui-port remove: deletes the load balancer and stops its charge
#   scripts/ui-access.sh status    dispatch ops-ui-port status
#   scripts/ui-access.sh url       print the URL (needs gcloud and read access to the project)
#
# The address goes into the GCP_UI_ALLOWED_CIDRS secret of the dev environment with your own gh login. It is
# never a workflow input, because inputs are shown on the repository's public run page. Dispatching only
# starts the run: you approve the dev environment in GitHub, and the load balancer takes several minutes.
#
# Environment: REPO (default: the repository of this checkout), GCP_PROJECT_ID (for url; default: the project
# named shiptrack).
set -euo pipefail

command=${1:?usage: ui-access.sh open|ip|close|remove|status|url}
repo=${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}

set_ip() {
  local ip
  ip=$(curl -fsS --max-time 10 https://checkip.amazonaws.com | tr -d '[:space:]')
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "could not read your public IPv4 address" >&2; exit 1; }
  printf '%s/32' "$ip" | gh secret set GCP_UI_ALLOWED_CIDRS --env dev -R "$repo" >/dev/null
  echo "The allow-list is now your current address (${ip}/32)."
}

dispatch() {
  gh workflow run ops-ui-port.yml --ref dev -R "$repo" -f action="$1"
  echo "Dispatched ops-ui-port ${1}. Approve the dev environment in GitHub to run it."
}

case "$command" in
  open) set_ip; dispatch open ;;
  ip) set_ip ;;
  close | remove | status) dispatch "$command" ;;
  url)
    project=${GCP_PROJECT_ID:-$(gcloud projects list --filter="name=shiptrack" --format='value(projectId)')}
    address=$(gcloud compute addresses describe shiptrack-ui --region "${GCP_REGION:-us-central1}" --project "$project" --format='value(address)')
    echo "http://${address}/ui/"
    ;;
  *) echo "unknown command: $command" >&2; exit 2 ;;
esac
