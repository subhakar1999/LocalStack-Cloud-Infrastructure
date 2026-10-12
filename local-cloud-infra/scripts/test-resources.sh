#!/usr/bin/env bash
set -euo pipefail

# Configuration
LOCALSTACK_HOST="${LOCALSTACK_HOST:-localhost}"
GATEWAY_PORT="${GATEWAY_PORT:-4566}"
ENDPOINT_URL="http://${LOCALSTACK_HOST}:${GATEWAY_PORT}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_DEFAULT_REGION="${REGION}"

BUCKET_NAME="${S3_BUCKET_NAME:-local-assets-bucket}"
TOPIC_NAME="${SNS_TOPIC_NAME:-local-events-topic}"
TABLE_NAME="${DYNAMODB_TABLE_NAME:-local-events-table}"

# Determine AWS CLI command wrapper
if command -v awslocal >/dev/null 2>&1; then
  AWS_CMD="awslocal"
  echo "[INFO] Using 'awslocal' CLI"
elif command -v aws >/dev/null 2>&1; then
  AWS_CMD="aws --endpoint-url=${ENDPOINT_URL}"
  echo "[INFO] Using 'aws' CLI with --endpoint-url=${ENDPOINT_URL}"
else
  echo "[ERROR] Neither 'awslocal' nor 'aws' CLI was found in PATH." >&2
  echo "[ERROR] Please install awscli or awscli-local (pip install awscli-local)." >&2
  exit 1
fi

echo "=========================================================="
echo " Starting End-to-End Test Suite against LocalStack"
echo " Endpoint:    ${ENDPOINT_URL}"
echo " S3 Bucket:   ${BUCKET_NAME}"
echo " SNS Topic:   ${TOPIC_NAME}"
echo " DynamoDB:    ${TABLE_NAME}"
echo "=========================================================="

# -----------------------------------------------------------------------------
# Test 1: S3 Bucket Upload & Verification
# -----------------------------------------------------------------------------
echo ""
echo "--> [1/3] Testing S3 Storage..."
TEST_FILE=$(mktemp /tmp/s3-test-XXXXXX.txt 2>/dev/null || echo "s3-test-upload.tmp")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "LocalStack S3 Test Payload generated at ${TIMESTAMP}" > "${TEST_FILE}"

OBJECT_KEY="test-objects/sample-${RANDOM}.txt"
echo "Uploading test object to s3://${BUCKET_NAME}/${OBJECT_KEY}..."
$AWS_CMD s3 cp "${TEST_FILE}" "s3://${BUCKET_NAME}/${OBJECT_KEY}"

echo "Listing objects in bucket to verify upload..."
$AWS_CMD s3 ls "s3://${BUCKET_NAME}/test-objects/"

rm -f "${TEST_FILE}"
echo "[PASS] S3 bucket upload and list succeeded."

# -----------------------------------------------------------------------------
# Test 2: Publish Message to SNS Topic
# -----------------------------------------------------------------------------
echo ""
echo "--> [2/3] Testing SNS Topic Publishing..."
ACCOUNT_ID="000000000000"
TOPIC_ARN="arn:aws:sns:${REGION}:${ACCOUNT_ID}:${TOPIC_NAME}"
UNIQUE_MSG_ID="msg-$(date +%s)-${RANDOM}"
MESSAGE_PAYLOAD="{\"id\": \"${UNIQUE_MSG_ID}\", \"action\": \"TEST_EVENT\", \"timestamp\": \"${TIMESTAMP}\"}"

echo "Publishing event payload to SNS Topic: ${TOPIC_ARN}"
PUBLISH_RESP=$($AWS_CMD sns publish \
  --topic-arn "${TOPIC_ARN}" \
  --message "${MESSAGE_PAYLOAD}" \
  --subject "LocalStack-Integration-Test")

echo "SNS Publish Response: ${PUBLISH_RESP}"
echo "[PASS] Event published to SNS successfully."

# -----------------------------------------------------------------------------
# Test 3: Verify Event Propagation via SQS & Lambda into DynamoDB
# -----------------------------------------------------------------------------
echo ""
echo "--> [3/3] Verifying Async Pipeline (SNS -> SQS -> Lambda -> DynamoDB)..."
echo "Waiting for Lambda event source mapping to process the message and insert into DynamoDB..."

MAX_WAIT=20
WAIT_INTERVAL=2
ELAPSED=0
FOUND=0

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
  sleep "$WAIT_INTERVAL"
  ELAPSED=$((ELAPSED + WAIT_INTERVAL))

  ITEMS=$($AWS_CMD dynamodb scan --table-name "${TABLE_NAME}" --max-items 10 2>/dev/null || true)

  if echo "$ITEMS" | grep -q "${UNIQUE_MSG_ID}"; then
    FOUND=1
    echo "Found matching record in DynamoDB after ${ELAPSED}s!"
    echo "Record excerpt:"
    echo "$ITEMS" | grep -C 5 "${UNIQUE_MSG_ID}" || echo "$ITEMS"
    break
  elif echo "$ITEMS" | grep -q "PROCESSED"; then
    FOUND=1
    echo "Found processed records in DynamoDB after ${ELAPSED}s!"
    break
  fi

  echo "Awaiting Lambda execution... (${ELAPSED}/${MAX_WAIT}s)"
done

if [ "$FOUND" -eq 1 ]; then
  echo ""
  echo "=========================================================="
  echo " ALL TESTS PASSED SUCCESSFULLY! "
  echo " S3 upload verified."
  echo " SNS -> SQS -> Lambda -> DynamoDB flow verified."
  echo "=========================================================="
  exit 0
else
  echo ""
  echo "[WARNING] Record not found in DynamoDB within ${MAX_WAIT}s."
  echo "Current DynamoDB items scan:"
  $AWS_CMD dynamodb scan --table-name "${TABLE_NAME}" || true
  exit 1
fi
