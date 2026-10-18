#!/usr/bin/env bash
# Looks at, fills, and drains the dead-letter queues from a runner (ADR-0034). Prints counts, ids, and
# attribute names; never a message body, because a body can hold a shipment's details.
#
# Usage: scripts/queues.sh status|poison|redrive events|notifications
#   status    pulls up to 20 messages from the flow's dead-letter subscription without acknowledging them,
#             and prints how many it saw, with each message's id, age, and delivery attempts. A pulled
#             message is hidden for the subscription's acknowledgement deadline and then visible again.
#   poison    publishes one malformed message to the flow's topic. The worker cannot apply it, so after five
#             deliveries Pub/Sub moves it to the dead-letter topic and the dead-letter alert fires.
#   redrive   moves every message from the dead-letter subscription back to the flow's topic, one at a time:
#             a message is acknowledged only after its republish succeeded. Dead-lettering attributes are
#             dropped. Do this after the cause is fixed, or it returns to the dead-letter queue.
#
# Environment: GCP_PROJECT_ID (required), MAX_MESSAGES for redrive (default 500).
# Needs gcloud with credentials that may pull from and publish to the flow's topics and subscriptions, and jq.
set -euo pipefail

action=${1:?usage: queues.sh status|poison|redrive events|notifications}
flow=${2:?usage: queues.sh status|poison|redrive events|notifications}
: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
echo "::add-mask::$GCP_PROJECT_ID"

case "$flow" in
  events)        topic=shiptrack-carrier-events ;;
  notifications) topic=shiptrack-notifications ;;
  *) echo "unknown flow: $flow" >&2; exit 2 ;;
esac
dead_letter_subscription="${topic}-dead-letter-inspect"
max=${MAX_MESSAGES:-500}

pull() { # pull <limit> [--auto-ack]
  local limit=$1
  shift
  gcloud pubsub subscriptions pull "$dead_letter_subscription" --project "$GCP_PROJECT_ID" \
    --limit "$limit" --format=json "$@" 2>/dev/null
}

case "$action" in
  status)
    messages=$(pull 20)
    count=$(jq 'length' <<<"$messages")
    echo "${flow}: ${count} message(s) seen in the dead-letter queue (at most 20 are shown)"
    jq -r '.[] | "  id \(.message.messageId)  published \(.message.publishTime)  delivery attempts \(.deliveryAttempt // "n/a")  attributes: \((.message.attributes // {}) | keys | join(","))"' <<<"$messages"
    ;;
  poison)
    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    # The notifications subscription filters on detail_type: a message without an announced type is dropped
    # before delivery, so the malformed one carries a real type.
    attribute="idempotency_key=poison-${stamp}"
    [[ "$flow" == notifications ]] && attribute="${attribute},detail_type=ShipmentDelivered"
    gcloud pubsub topics publish "$topic" --project "$GCP_PROJECT_ID" \
      --message "this is not an event ${stamp}" --attribute "$attribute" >/dev/null
    echo "${flow}: published one malformed message (poison-${stamp}). It reaches the dead-letter queue after five deliveries."
    ;;
  redrive)
    moved=0
    while ((moved < max)); do
      messages=$(pull 10)
      count=$(jq 'length' <<<"$messages")
      ((count > 0)) || break
      for index in $(seq 0 $((count - 1))); do
        ack_id=$(jq -r ".[$index].ackId" <<<"$messages")
        body=$(jq -r ".[$index].message.data // \"\"" <<<"$messages" | base64 -d)
        # Attribute values are plain tokens; anything else would need quoting that gcloud's flag cannot take.
        attributes=$(jq -r ".[$index].message.attributes // {} | with_entries(select(.key | startswith(\"CloudPubSubDeadLetter\") | not)) | to_entries | map(\"\(.key)=\(.value)\") | join(\",\")" <<<"$messages")
        if [[ -n "$attributes" && ! "$attributes" =~ ^[A-Za-z0-9_=.,:-]+$ ]]; then
          echo "::error::a message has attributes that cannot be republished safely; it stays in the dead-letter queue"
          exit 1
        fi
        publish=(gcloud pubsub topics publish "$topic" --project "$GCP_PROJECT_ID" --message "$body")
        [[ -n "$attributes" ]] && publish+=(--attribute "$attributes")
        "${publish[@]}" >/dev/null
        gcloud pubsub subscriptions ack "$dead_letter_subscription" --project "$GCP_PROJECT_ID" --ack-ids "$ack_id" >/dev/null
        moved=$((moved + 1))
      done
    done
    echo "${flow}: moved ${moved} message(s) from the dead-letter queue back to the topic"
    ;;
  *) echo "unknown action: $action" >&2; exit 2 ;;
esac
