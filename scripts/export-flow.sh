#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Configuration (modifiable)
# -----------------------------
# Exemple d'utilisation :
# export NIFI_REGISTRY_URL="http://localhost:18080/nifi-registry-api"
# export BUCKET_ID="3be3cbc4-c402-4c23-ade0-be34a2b08a0f"
# export FLOW_ID="a6177ea6-35ab-4f3e-a148-eeef31e00f3b"
# export FLOW_NAME="nifi_flow"
export NIFI_REGISTRY_URL="http://localhost:18080/nifi-registry-api"
export NIFI_REGISTRY_URL="http://localhost:18080/nifi-registry-api"
export BUCKET_ID="3be3cbc4-c402-4c23-ade0-be34a2b08a0f"
export FLOW_ID="a6177ea6-35ab-4f3e-a148-eeef31e00f3b"
export FLOW_NAME="nifi_flow"


# Note: Le push vers GitHub doit être fait manuellement
# -----------------------------

: "${NIFI_REGISTRY_URL:?Need to set NIFI_REGISTRY_URL e.g. http://localhost:18080/nifi-registry-api}"
: "${BUCKET_ID:?Need to set BUCKET_ID}"
: "${FLOW_ID:?Need to set FLOW_ID}"
: "${FLOW_NAME:?Need to set FLOW_NAME}"

# Local paths
FLOWS_DIR="./flows"
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ")
OUTFILE="${FLOWS_DIR}/${FLOW_NAME}-${TIMESTAMP}.json"
TMPFILE="$(mktemp)"

# Ensure tools exist
command -v curl >/dev/null 2>&1 || { echo "curl required but not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq required but not found"; exit 1; }

mkdir -p "${FLOWS_DIR}"

echo "Fetching latest snapshot from NiFi Registry..."
API_ENDPOINT="${NIFI_REGISTRY_URL%/}/buckets/${BUCKET_ID}/flows/${FLOW_ID}/versions/latest"

http_status=$(curl -sS -w "%{http_code}" -o "${TMPFILE}" "${API_ENDPOINT}")
if [[ "$http_status" != "200" ]]; then
  echo "Error: NiFi Registry returned HTTP $http_status"
  echo "Response (truncated):"
  head -n 40 "${TMPFILE}"
  rm -f "${TMPFILE}"
  exit 2
fi

# Pretty print / normalize JSON and save to final file
jq '.' "${TMPFILE}" > "${OUTFILE}" || { echo "Failed to parse JSON"; rm -f "${TMPFILE}"; exit 3; }
rm -f "${TMPFILE}"

echo "✅ Snapshot exporté localement : ${OUTFILE}"
echo "📝 Push vers GitHub à faire manuellement par la suite"
echo "Done."
