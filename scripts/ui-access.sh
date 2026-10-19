#!/usr/bin/env bash
# Opens the browser URLs of ShipTrack from your machine, and moves the allow-lists to your address when it
# changes (ADR-0031, ADR-0038).
#
#   scripts/ui-access.sh open      set the GCP and AWS allow-lists to your current public address, apply both,
#                                  and print the working URLs of modern, legacy, Grafana, and GCP
#   scripts/ui-access.sh urls      print the four URLs and check them, changing nothing
#   scripts/ui-access.sh ip        set both allow-list secrets to your current address, and do nothing else
#   scripts/ui-access.sh close     dispatch ops-ui-port close: GCP admits nobody
#   scripts/ui-access.sh remove    dispatch ops-ui-port remove: deletes the GCP load balancer and stops its charge
#   scripts/ui-access.sh status    dispatch ops-ui-port status
#   scripts/ui-access.sh url       print the GCP URL (needs gcloud and read access to the project)
#
# Your address goes, with your own gh login, into the GCP_UI_ALLOWED_CIDRS secret of this repository's dev
# environment and into shiptrack-platform's PREVIEW_CIDRS secret, which `open` replaces with your one current
# address. It is never a workflow input, because inputs are shown on the repositories' public run pages. The
# URLs come back from ops-ui-port and the platform's check-ui-urls only as ciphertext, encrypted to a key this
# script makes for the run and deletes when it exits, and are decrypted here.
#
# `open` asks you to approve two runs in GitHub: ops-ui-port (GCP) and the platform's apply-terraform, whose plan
# should update only the preview and Grafana rules, preview["0"] and grafana["0"]. It skips the apply while the
# platform's drift issue is open, because the apply would also apply the drift. `urls` asks you to approve
# ops-ui-port status. check-ui-urls needs no approval.
#
# Environment: REPO (default: the repository of this checkout), PLATFORM_REPO (default: shiptrack-platform of the
# same owner), GCP_PROJECT_ID (for url; default: the project named shiptrack), WAIT_MINUTES (how long to wait for
# each run, default 30), PROBE_MINUTES (how long each URL may take to answer, default 5).
set -euo pipefail

command=${1:?usage: ui-access.sh open|urls|ip|close|remove|status|url}
repo=${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}
platform_repo=${PLATFORM_REPO:-${repo%%/*}/shiptrack-platform}
wait_minutes=${WAIT_MINUTES:-30}
probe_minutes=${PROBE_MINUTES:-5}

my_ip() {
  local ip
  ip=$(curl -fsS --max-time 10 https://checkip.amazonaws.com | tr -d '[:space:]')
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "could not read your public IPv4 address" >&2; exit 1; }
  printf '%s' "$ip"
}

set_ip() {
  local ip
  ip=$(my_ip)
  printf '%s/32' "$ip" | gh secret set GCP_UI_ALLOWED_CIDRS --env dev -R "$repo" >/dev/null
  printf '["%s/32"]' "$ip" | gh secret set PREVIEW_CIDRS -R "$platform_repo" >/dev/null
  echo "Both allow-list secrets are now your current address (${ip}/32)."
}

# A key pair for this run only; the private key never leaves this machine and is deleted on exit.
make_key() {
  openssl version | grep -q '^OpenSSL 3' \
    || { echo "needs OpenSSL 3 for RSA-OAEP with SHA-256 (macOS: brew install openssl@3, and put it first on PATH)" >&2; exit 1; }
  work=$(mktemp -d)
  chmod 700 "$work"
  trap 'rm -rf "$work"' EXIT
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$work/key.pem" 2>/dev/null
  public_key=$(openssl pkey -in "$work/key.pem" -pubout | base64 | tr -d '\n')
}

# dispatch <repo> <workflow> [-f name=value]...: starts the run and prints its id.
dispatch() {
  local target=$1 workflow=$2 out id
  shift 2
  out=$(gh workflow run "$workflow" --ref dev -R "$target" "$@" 2>&1) || { echo "$out" >&2; exit 1; }
  id=$(grep -oE 'runs/[0-9]+' <<<"$out" | head -1 | cut -d/ -f2)
  [[ -n "$id" ]] || { echo "could not find the run of ${workflow} in: $out" >&2; exit 1; }
  printf '%s' "$id"
}

# wait_run <repo> <id> <label>: follows the run to the end; succeeds only if the run did.
wait_run() {
  local target=$1 id=$2 label=$3 state last="" deadline
  deadline=$(($(date +%s) + wait_minutes * 60))
  while :; do
    state=$(gh run view "$id" -R "$target" --json status,conclusion -q '.status + " " + .conclusion')
    if [[ "$state" != "$last" ]]; then
      case "$state" in
        waiting*) echo "  ${label}: waiting for your approval: https://github.com/${target}/actions/runs/${id}" ;;
        completed*) echo "  ${label}: ${state#completed }" ;;
        *) echo "  ${label}: ${state% }" ;;
      esac
      last=$state
    fi
    [[ "$state" == completed* ]] && break
    (($(date +%s) < deadline)) || { echo "  ${label}: still not finished after ${wait_minutes} minutes" >&2; return 1; }
    sleep 10
  done
  [[ "$state" == "completed success" ]]
}

# decrypt <repo> <id>: prints "<name> <url>" for each UI_URL line in the run's log.
decrypt() {
  local name ciphertext
  gh run view "$2" -R "$1" --log 2>/dev/null | grep -oE 'UI_URL [a-z]+ [A-Za-z0-9+/=]+' | sort -u \
    | while read -r _ name ciphertext; do
        printf '%s %s\n' "$name" "$(printf '%s' "$ciphertext" | base64 -d \
          | openssl pkeyutl -decrypt -inkey "$work/key.pem" -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256)"
      done
}

# probe <name> <url>: prints the HTTP status once the page answers 200, or the last status at the deadline.
probe() {
  local name=$1 url=$2 check=$2 code deadline
  [[ "$name" == grafana ]] && check="${url%/}/api/health"
  deadline=$(($(date +%s) + probe_minutes * 60))
  while :; do
    code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$check" || true)
    [[ "$code" == 200 ]] && break
    (($(date +%s) < deadline)) || break
    sleep 10
  done
  printf '  %-8s %-62s %s\n' "$name" "$url" "$([[ "$code" == 200 ]] && echo ok || echo "not answering (HTTP ${code:-none})")"
}

# show_urls <file>: checks each URL in the file and prints the table.
show_urls() {
  local name url
  echo
  echo "ShipTrack in the browser:"
  for name in modern legacy grafana gcp; do
    url=$(awk -v n="$name" '$1 == n { print $2 }' "$1")
    if [[ -n "$url" ]]; then probe "$name" "$url"; else printf '  %-8s %s\n' "$name" "(no URL: its run did not finish)"; fi
  done
}

drift_open() {
  [[ $(gh issue list -R "$platform_repo" --state open --search 'in:title "Drift detected: platform/dev"' \
    --json number -q 'length') -gt 0 ]]
}

open_all() {
  local gcp_run apply_run="" urls_run status=0
  set_ip
  make_key
  gcp_run=$(dispatch "$repo" ops-ui-port.yml -f action=open -f public_key="$public_key")
  if drift_open; then
    echo "The platform's drift issue is open, so apply-terraform is not dispatched: it would apply the drift too."
    echo "Legacy and Grafana keep the old address until the drift is reconciled and apply-terraform runs."
  else
    apply_run=$(dispatch "$platform_repo" apply-terraform.yml)
  fi
  urls_run=$(dispatch "$platform_repo" check-ui-urls.yml -f public_key="$public_key")
  echo "Approve in GitHub: ops-ui-port (GCP)${apply_run:+, and apply-terraform (platform), which should update only preview[\"0\"] and grafana[\"0\"]}."
  wait_run "$platform_repo" "$urls_run" check-ui-urls || status=1
  [[ -n "$apply_run" ]] && { wait_run "$platform_repo" "$apply_run" apply-terraform || status=1; }
  wait_run "$repo" "$gcp_run" ops-ui-port || status=1
  { decrypt "$platform_repo" "$urls_run"; decrypt "$repo" "$gcp_run"; } >"$work/urls"
  show_urls "$work/urls"
  return "$status"
}

show_all() {
  local gcp_run urls_run status=0
  make_key
  gcp_run=$(dispatch "$repo" ops-ui-port.yml -f action=status -f public_key="$public_key")
  urls_run=$(dispatch "$platform_repo" check-ui-urls.yml -f public_key="$public_key")
  echo "Approve ops-ui-port status (GCP) in GitHub."
  wait_run "$platform_repo" "$urls_run" check-ui-urls || status=1
  wait_run "$repo" "$gcp_run" ops-ui-port || status=1
  { decrypt "$platform_repo" "$urls_run"; decrypt "$repo" "$gcp_run"; } >"$work/urls"
  probe_minutes=0 show_urls "$work/urls"
  return "$status"
}

case "$command" in
  open) open_all ;;
  urls) show_all ;;
  ip) set_ip ;;
  close | remove | status)
    gh workflow run ops-ui-port.yml --ref dev -R "$repo" -f action="$command"
    echo "Dispatched ops-ui-port ${command}. Approve the dev environment in GitHub to run it."
    ;;
  url)
    project=${GCP_PROJECT_ID:-$(gcloud projects list --filter="name=shiptrack" --format='value(projectId)')}
    address=$(gcloud compute addresses describe shiptrack-ui --region "${GCP_REGION:-us-central1}" --project "$project" --format='value(address)')
    echo "http://${address}/ui/"
    ;;
  *) echo "unknown command: $command" >&2; exit 2 ;;
esac
