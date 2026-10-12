#!/usr/bin/env bash
set -euo pipefail

# Configuration
LOCALSTACK_HOST="${LOCALSTACK_HOST:-localhost}"
GATEWAY_PORT="${GATEWAY_PORT:-4566}"
HEALTH_URL="http://${LOCALSTACK_HOST}:${GATEWAY_PORT}/_localstack/health"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-30}"
RETRY_INTERVAL="${RETRY_INTERVAL:-2}"

echo "=========================================================="
echo "Waiting for LocalStack to be ready at: ${HEALTH_URL}"
echo "Max attempts: ${MAX_ATTEMPTS} (Interval: ${RETRY_INTERVAL}s)"
echo "=========================================================="

attempt=1

while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
  if command -v curl >/dev/null 2>&1; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${HEALTH_URL}" || true)
  else
    echo "ERROR: 'curl' is required to perform health check." >&2
    exit 1
  fi

  if [ "$HTTP_CODE" = "200" ]; then
    echo "SUCCESS: LocalStack is fully operational (HTTP 200)!"
    echo "Service health overview:"
    curl -s "${HEALTH_URL}" | grep -o '"{.*}"' || curl -s "${HEALTH_URL}" || true
    echo ""
    exit 0
  fi

  echo "Attempt ${attempt}/${MAX_ATTEMPTS}: LocalStack returned HTTP ${HTTP_CODE:-none}. Retrying in ${RETRY_INTERVAL}s..."
  attempt=$((attempt + 1))
  sleep "$RETRY_INTERVAL"
done

echo "ERROR: LocalStack failed to become ready within $((MAX_ATTEMPTS * RETRY_INTERVAL)) seconds." >&2
exit 1
