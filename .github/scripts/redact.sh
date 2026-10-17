# shellcheck shell=bash
# Sourced by terraform-ci.sh, terraform-destroy.sh, and terraform/seed/scripts/ci.sh. The repository is
# public, so a failed command's output must not carry the project, its number, the state bucket, the
# billing account, or the alert address. A tool that wraps its output can split an identifier across
# two lines, where a log mask no longer matches it, so a failure is printed only after two steps:
#   1. every identifier is replaced, wherever it appears whole;
#   2. if an identifier could still be put together from the text with its line breaks, box characters,
#      and spaces taken out, the output is withheld and a notice is printed instead.
# Needs GCP_PROJECT_ID and GCP_PROJECT_NUMBER; GCP_BILLING_ACCOUNT_ID and GCP_ALERT_EMAIL are optional.

_identifiers() {
  printf '%s\n' "$GCP_PROJECT_ID" "$GCP_PROJECT_NUMBER" "shiptrack-tfstate-${GCP_PROJECT_NUMBER}" \
    "${GCP_BILLING_ACCOUNT_ID:-}" "${GCP_ALERT_EMAIL:-}"
}

# print_failure <file>: the file's text on stderr, with identifiers hidden or the whole text withheld.
print_failure() {
  local file=$1 text flat value
  text=$(cat "$file")
  while IFS= read -r value; do
    [[ -n "$value" ]] && text=${text//"$value"/***}
  done < <(_identifiers)
  flat=${text//│/}
  flat=$(tr -d ' \t\n' <<<"$flat")
  while IFS= read -r value; do
    if [[ -n "$value" && "$flat" == *"$value"* ]]; then
      echo "The failure output may hold an identifier split across lines, so it is withheld." >&2
      return 0
    fi
  done < <(_identifiers)
  printf '%s\n' "$text" >&2
}
