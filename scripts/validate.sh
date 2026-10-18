#!/usr/bin/env bash
# Validation of the running stack (design 9.3, acceptance criteria 6 and 7), from a runner that reaches the
# cluster only through `kubectl port-forward`.
#
# Usage: scripts/validate.sh deploy|preemption|sla <simulator-dir>
#   deploy      the simulator sends traffic while every Deployment is restarted at once, as a release does,
#               then the ledger is checked: every event the API accepted must be stored.
#   preemption  the same traffic while the pods are deleted with the 25 second grace Autopilot gives a Spot
#               pod, all at once, twice. A real reclaim cannot be forced; this is the pod's side of one.
#   sla         the simulator sends shipments, some created already late, and a Job in the cluster checks
#               that every breached shipment has exactly one alert (deploy/validation/sla-check.yaml).
#
# The port-forward is restarted whenever it drops, because the pod it points at is being replaced. A request
# that fails while the pod goes is an availability blip and is reported; it never enters the ledger, so it is
# not a loss. The check that decides the result is the ledger: accepted (202) and never stored.
#
# Environment: NAMESPACE (default shiptrack), SERVICE (default shiptrack-api), LOCAL_PORT (default 18000),
# SHIPMENTS (300), CONCURRENCY (10), DELAY (3, seconds between a shipment's events), SEED (1),
# GCP_PROJECT_ID (sla only). Needs kubectl with credentials for the cluster, curl, and uv.
set -euo pipefail

scenario=${1:?usage: validate.sh deploy|preemption|sla <simulator-dir>}
sim_dir=${2:?usage: validate.sh deploy|preemption|sla <simulator-dir>}
[[ "$scenario" =~ ^(deploy|preemption|sla)$ ]] || { echo "unknown scenario: $scenario" >&2; exit 2; }
[[ -d "$sim_dir" ]] || { echo "no simulator directory: $sim_dir" >&2; exit 2; }
sim_dir=$(cd "$sim_dir" && pwd)

namespace=${NAMESPACE:-shiptrack}
service=${SERVICE:-shiptrack-api}
port=${LOCAL_PORT:-18000}
shipments=${SHIPMENTS:-300}
concurrency=${CONCURRENCY:-10}
delay=${DELAY:-3}
seed=${SEED:-1}
base="http://localhost:${port}"
results="$PWD/validation-results"
mkdir -p "$results"
sim_log="$results/run.log"

forward_forever() {
  while true; do
    kubectl -n "$namespace" port-forward "svc/${service}" "${port}:8000" >/dev/null 2>&1 || true
    sleep 1
  done
}
forward_forever &
forwarder=$!
sim_pid=""
cleanup() {
  if [[ -n "$sim_pid" ]]; then kill "$sim_pid" 2>/dev/null || true; fi
  kill "$forwarder" 2>/dev/null || true
  pkill -f "kubectl.*port-forward svc/${service}" 2>/dev/null || true
}
trap cleanup EXIT

for attempt in $(seq 1 30); do
  if curl -sS --max-time 5 -o /dev/null "${base}/readyz" 2>/dev/null; then break; fi
  [[ "$attempt" == 30 ]] && { echo "FAIL: the port-forward to ${service} never answered" >&2; exit 1; }
  sleep 2
done

sim() { (cd "$sim_dir" && uv run --frozen shiptrack-sim "$@"); }

start_traffic() {
  echo "sending ${shipments} shipments, ${concurrency} at a time, ${delay} s between a shipment's events"
  sim run --base-url "$base" --target none --shipments "$shipments" --concurrency "$concurrency" \
    --delay "$delay" --seed "$seed" --results-dir "$results" >"$sim_log" 2>&1 &
  sim_pid=$!
}

# Waits for the simulator and prints what it did. A non-zero exit means some shipment could not be created
# or sent while the pods were being replaced; the ledger check below is what decides the result.
finish_traffic() {
  local status=0
  wait "$sim_pid" || status=$?
  sim_pid=""
  cat "$sim_log"
  echo "simulator exit status: ${status} (non-zero means some requests failed while pods were replaced)"
}

wait_ready() {
  local deployment
  for deployment in $(kubectl -n "$namespace" get deployments -o name); do
    kubectl -n "$namespace" rollout status "$deployment" --timeout=600s
  done
}

check_ledger() {
  local ledger="" candidate
  # The names carry a timestamp, so the last in glob order is the newest.
  for candidate in "$results"/sent-*.jsonl; do
    [[ -e "$candidate" ]] && ledger=$candidate
  done
  [[ -n "$ledger" ]] || { echo "FAIL: the simulator wrote no ledger" >&2; exit 1; }
  echo "checking $(wc -l <"$ledger" | tr -d ' ') accepted events against the tracking timelines"
  sim verify --ledger "$ledger" --base-url "$base" --target none --wait 300
}

case "$scenario" in
  deploy)
    start_traffic
    sleep 30
    echo "restarting every Deployment at once, as a release does"
    kubectl -n "$namespace" rollout restart deployment
    wait_ready
    finish_traffic
    check_ledger
    ;;
  preemption)
    start_traffic
    for round in 1 2; do
      sleep 60
      echo "round ${round}: deleting every pod with a 25 second grace period"
      kubectl -n "$namespace" delete pods -l 'app.kubernetes.io/component in (api,worker-events,worker-notify)' \
        --grace-period=25 --wait=false
      # The old pods linger for the grace period, so wait it out before asking whether the new ones are ready.
      sleep 30
      wait_ready
    done
    finish_traffic
    check_ledger
    ;;
  sla)
    : "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required for sla}"
    image=$(kubectl -n "$namespace" get deployment shiptrack-api -o jsonpath='{.spec.template.spec.containers[0].image}')
    echo "::add-mask::$GCP_PROJECT_ID"
    start_traffic
    finish_traffic
    echo "starting the SLA check in the cluster; it waits up to 15 minutes for the scan to flag every overdue shipment"
    # shellcheck disable=SC2016 # envsubst reads these names; the shell must not expand them
    job=$(IMAGE="$image" envsubst '${IMAGE} ${GCP_PROJECT_ID}' <deploy/validation/sla-check.yaml | kubectl create -f - -o name)
    for _ in $(seq 1 130); do
      succeeded=$(kubectl -n "$namespace" get "$job" -o jsonpath='{.status.succeeded}')
      failed=$(kubectl -n "$namespace" get "$job" -o jsonpath='{.status.failed}')
      [[ "$succeeded" == 1 || "${failed:-0}" -ge 1 ]] && break
      sleep 10
    done
    # The Job's log holds counts; the database address is hidden in case a library names it.
    kubectl -n "$namespace" logs "$job" --all-containers --tail=60 2>&1 \
      | sed -E -e 's/("host": ")[^"]*/\1<HOST>/g' -e 's/(host=)[^ ]+/\1<HOST>/g'
    [[ "$(kubectl -n "$namespace" get "$job" -o jsonpath='{.status.succeeded}')" == 1 ]] \
      || { echo "::error::the SLA check did not pass"; exit 1; }
    ;;
esac
echo "validation ${scenario}: passed"
