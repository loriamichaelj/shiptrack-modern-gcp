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
# The port-forward is restarted whenever it drops, because the pod it points at is being replaced, and the
# simulator tries a request again for RETRY_SECONDS, as a client behind a load balancer does; an event is sent
# again with the same Idempotency-Key. A request that still fails is an availability blip and is reported; it
# never enters the ledger, so it is not a loss. The run fails if fewer than 95% of the shipments could be created,
# because a run in which the traffic stopped when the pods were replaced proves nothing. The check that decides the result is the ledger: accepted (202) and never stored. A Job in the
# cluster (deploy/validation/ledger-check.yaml) looks up each idempotency key in the database, because the
# tracking timeline lists only applied events and an out-of-order event is stored but not applied.
#
# Environment: NAMESPACE (default shiptrack), SERVICE (default shiptrack-api), LOCAL_PORT (default 18000),
# SHIPMENTS (300), CONCURRENCY (10), DELAY (3, seconds between a shipment's events), SEED (1),
# RETRY_SECONDS (180, how long the simulator tries a failed request again), MAX_RUN_SECONDS (1200, how long
# the simulator may run before the run is stopped and fails; a healthy run of 300 shipments takes about 6 minutes),
# GCP_PROJECT_ID (required). Needs kubectl with credentials for the cluster, curl, and uv.
set -euo pipefail

scenario=${1:?usage: validate.sh deploy|preemption|sla <simulator-dir>}
sim_dir=${2:?usage: validate.sh deploy|preemption|sla <simulator-dir>}
[[ "$scenario" =~ ^(deploy|preemption|sla)$ ]] || { echo "unknown scenario: $scenario" >&2; exit 2; }
[[ -d "$sim_dir" ]] || { echo "no simulator directory: $sim_dir" >&2; exit 2; }
sim_dir=$(cd "$sim_dir" && pwd)

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
echo "::add-mask::$GCP_PROJECT_ID"
namespace=${NAMESPACE:-shiptrack}
service=${SERVICE:-shiptrack-api}
port=${LOCAL_PORT:-18000}
shipments=${SHIPMENTS:-300}
concurrency=${CONCURRENCY:-10}
delay=${DELAY:-3}
seed=${SEED:-1}
retry=${RETRY_SECONDS:-180}
max_run=${MAX_RUN_SECONDS:-1200}
base="http://localhost:${port}"
results="$PWD/validation-results"
mkdir -p "$results"
sim_log="$results/run.log"

# A port-forward ends when its pod goes, and one that is still running can point at a pod that is gone and answer
# nothing. So the tunnel is probed every 3 seconds, and one that fails five probes in a row is stopped and started again.
forward_forever() {
  local forward fails
  while true; do
    kubectl -n "$namespace" port-forward "svc/${service}" "${port}:8000" >/dev/null 2>&1 &
    forward=$!
    fails=0
    while kill -0 "$forward" 2>/dev/null; do
      sleep 3
      if curl -s -o /dev/null -m 3 "${base}/healthz"; then fails=0; else fails=$((fails + 1)); fi
      if ((fails >= 5)); then kill "$forward" 2>/dev/null || true; break; fi
    done
    wait "$forward" 2>/dev/null || true
    echo restarted >>"$results/forward-restarts"
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
    --delay "$delay" --seed "$seed" --retry-seconds "$retry" --results-dir "$results" >"$sim_log" 2>&1 &
  sim_pid=$!
}

# One line of progress: how long the run has lasted, how many events the API has accepted so far, how many times
# the port-forward had to be restarted, and whether the tunnel answers now.
progress() {
  local ledger="" candidate accepted=0 restarts=0 probe
  for candidate in "$results"/sent-*.jsonl; do
    [[ -e "$candidate" ]] && ledger=$candidate
  done
  [[ -n "$ledger" ]] && accepted=$(wc -l <"$ledger" | tr -d ' ')
  [[ -e "$results/forward-restarts" ]] && restarts=$(wc -l <"$results/forward-restarts" | tr -d ' ')
  probe=$(curl -s -o /dev/null -m 3 -w '%{http_code}' "${base}/readyz" 2>/dev/null || true)
  echo "progress: ${SECONDS}s, ${accepted} events accepted, port-forward restarted ${restarts} time(s), /readyz through the tunnel: ${probe:-no answer}"
}

# Waits for the simulator and prints what it did. A non-zero exit means some shipment could not be created
# or sent while the pods were being replaced; the ledger check below is what decides the result.
finish_traffic() {
  local status=0 waited=0
  while kill -0 "$sim_pid" 2>/dev/null; do
    sleep 15
    waited=$((waited + 15))
    if ((waited % 30 == 0)); then progress; fi
    if ((waited >= max_run)); then
      echo "::error::the simulator was still running after ${max_run} s, so it is stopped"
      progress
      kill "$sim_pid" 2>/dev/null || true
      pkill -f shiptrack-sim 2>/dev/null || true
      sim_pid=""
      cat "$sim_log"
      exit 1
    fi
  done
  wait "$sim_pid" || status=$?
  sim_pid=""
  cat "$sim_log"
  echo "simulator exit status: ${status} (non-zero means some requests still failed after ${retry} s of retries)"
  local created
  created=$(sed -nE 's/^shipments created +([0-9]+) .*/\1/p' "$sim_log")
  if ((${created:-0} * 100 < shipments * 95)); then
    echo "::error::only ${created:-0} of ${shipments} shipments were created, so the traffic did not last through the disturbance"
    exit 1
  fi
}

wait_ready() {
  local deployment
  for deployment in $(kubectl -n "$namespace" get deployments -o name); do
    kubectl -n "$namespace" rollout status "$deployment" --timeout=600s
  done
}

# run_check_job <manifest>: creates a Job from the release's own image with envsubst, waits for it, prints its
# log (counts only; the database address is hidden in case a library names it), and fails unless it succeeded.
run_check_job() {
  local manifest=$1 image job succeeded failed
  image=$(kubectl -n "$namespace" get deployment shiptrack-api -o jsonpath='{.spec.template.spec.containers[0].image}')
  # shellcheck disable=SC2016 # envsubst reads these names; the shell must not expand them
  job=$(IMAGE="$image" envsubst '${IMAGE} ${GCP_PROJECT_ID} ${LEDGER_CONFIGMAP}' <"$manifest" | kubectl create -f - -o name)
  for _ in $(seq 1 130); do
    succeeded=$(kubectl -n "$namespace" get "$job" -o jsonpath='{.status.succeeded}')
    failed=$(kubectl -n "$namespace" get "$job" -o jsonpath='{.status.failed}')
    [[ "$succeeded" == 1 || "${failed:-0}" -ge 1 ]] && break
    sleep 10
  done
  kubectl -n "$namespace" logs "$job" --all-containers --tail=60 2>&1 \
    | sed -E -e 's/("host": ")[^"]*/\1<HOST>/g' -e 's/(host=)[^ ]+/\1<HOST>/g'
  [[ "$(kubectl -n "$namespace" get "$job" -o jsonpath='{.status.succeeded}')" == 1 ]]
}

check_ledger() {
  local ledger="" candidate
  # The names carry a timestamp, so the last in glob order is the newest.
  for candidate in "$results"/sent-*.jsonl; do
    [[ -e "$candidate" ]] && ledger=$candidate
  done
  [[ -n "$ledger" ]] || { echo "FAIL: the simulator wrote no ledger" >&2; exit 1; }
  jq -r '.idempotency_key' "$ledger" | sort -u >"$results/keys.txt"
  echo "checking $(wc -l <"$results/keys.txt" | tr -d ' ') accepted events against the database; the Job waits up to 5 minutes for the workers"
  LEDGER_CONFIGMAP="shiptrack-ledger-$(date -u +%Y%m%d%H%M%S)"
  export LEDGER_CONFIGMAP
  kubectl -n "$namespace" create configmap "$LEDGER_CONFIGMAP" --from-file=keys.txt="$results/keys.txt" >/dev/null
  local status=0
  run_check_job deploy/validation/ledger-check.yaml || status=$?
  kubectl -n "$namespace" delete configmap "$LEDGER_CONFIGMAP" >/dev/null
  if ((status != 0)); then echo "::error::an accepted event was never stored"; exit 1; fi
}

case "$scenario" in
  deploy)
    start_traffic
    sleep 30
    echo "restarting every Deployment at once, as a release does"
    kubectl -n "$namespace" rollout restart deployment
    wait_ready
    progress
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
      progress
    done
    finish_traffic
    check_ledger
    ;;
  sla)
    start_traffic
    finish_traffic
    echo "starting the SLA check in the cluster; it waits up to 15 minutes for the scan to flag every overdue shipment"
    run_check_job deploy/validation/sla-check.yaml || { echo "::error::the SLA check did not pass"; exit 1; }
    ;;
esac
echo "validation ${scenario}: passed"
