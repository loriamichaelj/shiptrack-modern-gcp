#!/usr/bin/env bash
# Report the project's cost for one month from the billing export (ADR-0028): by service, by the `name`
# label, by day, and against the budget. Read-only. Run by ops-check-cost.yml as the plan account.
# Usage: .github/scripts/cost-report.sh [YYYY-MM]    (default: the current month, UTC)
#
# The report goes to the job summary and to stdout. It holds amounts, service names, and label values,
# never the project, the billing account, or a resource name.
#
# Environment:
#   GCP_PROJECT_ID   project that the export covers (required)
#   BUDGET_USD       monthly budget to compare with (default 50, as terraform/finops)
#   GCP_PROJECT_NUMBER  optional; also hidden from error text
#   GCP_REGION       location of the export dataset (default us-central1)
set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
month=${1:-$(date -u +%Y-%m)}
[[ "$month" =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]] || { echo "month must be YYYY-MM" >&2; exit 2; }
budget=${BUDGET_USD:-50}
dataset=shiptrack_billing_export
echo "::add-mask::$GCP_PROJECT_ID"

year=$((10#${month%-*}))
mon=$((10#${month#*-}))
if ((mon == 12)); then next_year=$((year + 1)); next_mon=1; else next_year=$year; next_mon=$((mon + 1)); fi
start=$(printf '%04d-%02d-01 00:00:00+00' "$year" "$mon")
end=$(printf '%04d-%02d-01 00:00:00+00' "$next_year" "$next_mon")
case $mon in
  1 | 3 | 5 | 7 | 8 | 10 | 12) days_in_month=31 ;;
  4 | 6 | 9 | 11) days_in_month=30 ;;
  2) if ((year % 4 == 0 && (year % 100 != 0 || year % 400 == 0))); then days_in_month=29; else days_in_month=28; fi ;;
esac

# The net cost of a row is its cost plus its credits, which are negative.
net='cost + IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) AS c), 0)'
from="FROM \`${GCP_PROJECT_ID}.${dataset}.gcp_billing_export_v1_*\`
WHERE project.id = @project AND usage_start_time >= @start_ts AND usage_start_time < @end_ts"

out=$(mktemp)
err=$(mktemp)
trap 'rm -f "$out" "$err"' EXIT

# bq wraps long lines, which can split the project ID across two lines where a log mask no longer
# matches it. Join the lines before hiding the ID, and hide the project number as well.
scrub() { tr -d '\n' | sed -e "s/${GCP_PROJECT_ID}/***/g" -e "s/${GCP_PROJECT_NUMBER:-@@none@@}/***/g"; }
emit() { printf '%s\n' "$*" | tee -a "$out"; }

# run_query <sql>: the JSON rows go to $result. bq prints warnings to stderr even when the query works, so
# stderr is kept apart and joins $result only on a failure.
run_query() {
  if result=$(bq --project_id="$GCP_PROJECT_ID" --location="${GCP_REGION:-us-central1}" query --quiet \
    --use_legacy_sql=false --format=json --max_rows=1000 \
    --parameter="project::${GCP_PROJECT_ID}" \
    --parameter="start_ts:TIMESTAMP:${start}" \
    --parameter="end_ts:TIMESTAMP:${end}" "$1" 2>"$err"); then
    return 0
  fi
  result="${result}$(cat "$err")"
  return 1
}

run_query "SELECT service.description AS service,
  ROUND(SUM(cost), 2) AS gross,
  ROUND(SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) AS c), 0)), 2) AS credits,
  ROUND(SUM(${net}), 2) AS net
${from} GROUP BY service ORDER BY net DESC" || {
  # Wrapping also removes the spaces between words, so match with the whitespace taken out.
  if tr -d ' \n' <<<"$result" | grep -qiE 'notfound|doesnotexist|doesnotmatchanytable'; then
    emit "## Cost for ${month}"
    emit
    emit "There is no billing export data yet. The export fills the dataset within a day of being switched on."
    [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && cat "$out" >>"$GITHUB_STEP_SUMMARY"
    exit 0
  fi
  echo "cost query failed: $(scrub <<<"$result")" >&2
  exit 1
}
by_service=$result

run_query "SELECT IFNULL((SELECT l.value FROM UNNEST(labels) AS l WHERE l.key = 'name'), '(no name label)') AS name,
  ROUND(SUM(${net}), 2) AS net
${from} GROUP BY name ORDER BY net DESC" || { echo "cost query failed: $(scrub <<<"$result")" >&2; exit 1; }
by_label=$result
run_query "SELECT FORMAT_DATE('%Y-%m-%d', DATE(usage_start_time)) AS day, ROUND(SUM(${net}), 2) AS net
${from} GROUP BY day ORDER BY day" || { echo "cost query failed: $(scrub <<<"$result")" >&2; exit 1; }
by_day=$result

total=$(jq -r '[.[].net | tonumber] | add // 0' <<<"$by_service")
covered=$(jq -r 'length' <<<"$by_day")
last_day=$(jq -r 'if length == 0 then "none" else .[-1].day end' <<<"$by_day")

emit "## Cost for ${month}"
emit
emit "Net of credits: **\$$(printf '%.2f' "$total")** against a budget of \$${budget}. Data to ${last_day} (billing data lags by up to a day)."
if ((covered > 0)) && [[ "$month" == "$(date -u +%Y-%m)" ]]; then
  projected=$(jq -n --argjson t "$total" --argjson d "$covered" --argjson m "$days_in_month" '$t / $d * $m')
  emit "Run rate over ${covered} day(s) with data projects to **\$$(printf '%.2f' "$projected")** for the month."
fi
emit
emit "### By service"
emit
emit "| Service | Gross | Credits | Net |"
emit "|---|---:|---:|---:|"
jq -r '.[] | "| \(.service) | \(.gross) | \(.credits) | \(.net) |"' <<<"$by_service" | tee -a "$out"
emit
emit "### By \`name\` label"
emit
emit "| Label | Net |"
emit "|---|---:|"
jq -r '.[] | "| \(.name) | \(.net) |"' <<<"$by_label" | tee -a "$out"
emit
emit "### By day"
emit
emit "| Day | Net |"
emit "|---|---:|"
jq -r '.[] | "| \(.day) | \(.net) |"' <<<"$by_day" | tee -a "$out"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat "$out" >>"$GITHUB_STEP_SUMMARY"
fi
