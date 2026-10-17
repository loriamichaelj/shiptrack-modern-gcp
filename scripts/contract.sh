#!/usr/bin/env bash
# Run the platform's contract suite against the API in the cluster, through `kubectl port-forward`. The
# cluster has no public address, so a runner reaches the service only this way, and the AWS routing headers
# and test token have nothing to steer: the suite runs against one stack, with an empty token.
#
# Usage: scripts/contract.sh smoke|full <contract-dir>
#   smoke  four readiness and reachability checks, then the 8-test smoke subset
#   full   the same checks, then every test that needs one stack
#
# Environment: NAMESPACE (default shiptrack), SERVICE (default shiptrack-api), LOCAL_PORT (default 18000).
# Needs kubectl with credentials for the cluster, curl, and uv.
set -euo pipefail

suite=${1:?usage: contract.sh smoke|full <contract-dir>}
contract_dir=${2:-}
[[ "$suite" == smoke || "$suite" == full ]] || { echo "unknown suite: $suite" >&2; exit 2; }
namespace=${NAMESPACE:-shiptrack}
service=${SERVICE:-shiptrack-api}
port=${LOCAL_PORT:-18000}
base="http://localhost:${port}"

kubectl -n "$namespace" port-forward "svc/${service}" "${port}:8000" >/dev/null 2>&1 &
forward=$!
trap 'kill "$forward" 2>/dev/null || true' EXIT

# The forward takes a moment, and a rollout can finish before the new pods answer.
for attempt in $(seq 1 30); do
  if curl -sS --max-time 5 -o /dev/null "${base}/healthz" 2>/dev/null; then break; fi
  [[ "$attempt" == 30 ]] && { echo "FAIL: the port-forward to ${service} never answered" >&2; exit 1; }
  sleep 2
done

check() {
  local path=$1 want=$2 headers status stack
  headers=$(curl -sS --max-time 15 -D - -o /dev/null "${base}${path}")
  status=$(printf '%s' "$headers" | awk 'NR==1 {print $2}')
  stack=$(printf '%s' "$headers" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-shiptrack-stack" {print $2}')
  if [[ "$status" != "$want" ]]; then
    echo "FAIL ${path}: expected ${want}, got ${status:-no response}" >&2
    return 1
  fi
  if [[ "$stack" != "modern" ]]; then
    echo "FAIL ${path}: X-ShipTrack-Stack is '${stack:-missing}', not modern" >&2
    return 1
  fi
  echo "ok   ${path} -> ${status} from modern"
}

for attempt in $(seq 1 12); do
  if check /readyz 200 2>/dev/null; then break; fi
  [[ "$attempt" == 12 ]] && check /readyz 200
  sleep 10
done
check /healthz 200
check "/api/v1/shipments?limit=1" 200
check /ui/ 200

if [[ -z "$contract_dir" || ! -d "$contract_dir" ]]; then
  echo "::warning::no contract suite directory; only the built-in checks ran"
  exit 0
fi
marker="smoke"
[[ "$suite" == full ]] && marker="not sla"
echo "running the contract suite (${suite})"
(cd "$contract_dir" && TARGET=modern SINGLE_STACK=1 BASE_URL="$base" TEST_TOKEN="" uv run --frozen pytest -m "$marker" -q)
