#!/usr/bin/env bash
# Prints, one per line, the --set arguments that complete deploy/values-gcp.yaml: the image digest and the
# three values that identify the project. deploy-app and the chart CI job both use it, so the chart is
# checked with the arguments it is deployed with.
#
# Usage: mapfile -t args < <(scripts/chart-args.sh); helm template ... "${args[@]}"
#
# Environment (all required):
#   IMAGE_DIGEST                      sha256:<64 hex>
#   GCP_PROJECT_ID                    the project
#   GCP_PROOF_OF_DELIVERY_BUCKET      the proof-of-delivery bucket
#   GCP_PROOF_OF_DELIVERY_SIGNER      the signer service account's email
set -euo pipefail

: "${IMAGE_DIGEST:?IMAGE_DIGEST is required}"
: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
: "${GCP_PROOF_OF_DELIVERY_BUCKET:?GCP_PROOF_OF_DELIVERY_BUCKET is required}"
: "${GCP_PROOF_OF_DELIVERY_SIGNER:?GCP_PROOF_OF_DELIVERY_SIGNER is required}"
[[ "$IMAGE_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "IMAGE_DIGEST is not sha256:<64 hex>" >&2; exit 2; }

printf '%s\n' \
  "--set" "image.digest=${IMAGE_DIGEST}" \
  "--set" "gcp.project=${GCP_PROJECT_ID}" \
  "--set" "gcp.proofOfDeliveryBucket=${GCP_PROOF_OF_DELIVERY_BUCKET}" \
  "--set" "gcp.proofOfDeliverySigner=${GCP_PROOF_OF_DELIVERY_SIGNER}"
