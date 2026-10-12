import os
import json
import time
import uuid
import logging
import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Determine DynamoDB table and endpoint configuration
TABLE_NAME = os.environ.get("DYNAMODB_TABLE_NAME", "local-events-table")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

endpoint_url = os.environ.get("AWS_ENDPOINT_URL")
if not endpoint_url and os.environ.get("LOCALSTACK_HOSTNAME"):
    edge_port = os.environ.get("EDGE_PORT", "4566")
    endpoint_url = f"http://{os.environ.get('LOCALSTACK_HOSTNAME')}:{edge_port}"

dynamodb_kwargs = {
    "region_name": AWS_REGION
}
if endpoint_url:
    dynamodb_kwargs["endpoint_url"] = endpoint_url

dynamodb = boto3.resource("dynamodb", **dynamodb_kwargs)
table = dynamodb.Table(TABLE_NAME)


def handler(event, context):
    """
    AWS Lambda handler that processes SQS batches and persists records into DynamoDB.
    """
    logger.info("Received event: %s", json.dumps(event))

    records = event.get("Records", [])
    processed_count = 0

    for record in records:
        message_id = record.get("messageId", str(uuid.uuid4()))
        body_raw = record.get("body", "")
        event_source = record.get("eventSource", "aws:sqs")
        timestamp_now = int(time.time() * 1000)

        # Parse message payload safely
        try:
            body_content = json.loads(body_raw)
        except (ValueError, TypeError):
            body_content = {"raw": body_raw}

        # Build item conforming to DynamoDB pk and sk schema
        item = {
            "pk": f"MSG#{message_id}",
            "sk": f"TS#{timestamp_now}",
            "message_id": message_id,
            "event_source": event_source,
            "created_at": timestamp_now,
            "payload": json.dumps(body_content) if isinstance(body_content, (dict, list)) else str(body_content),
            "status": "PROCESSED",
        }

        try:
            logger.info("Writing item to DynamoDB table %s: %s", TABLE_NAME, item["pk"])
            table.put_item(Item=item)
            processed_count += 1
        except ClientError as err:
            logger.error(
                "Failed to write item %s to DynamoDB: %s",
                message_id,
                err.response.get("Error", {}).get("Message")
            )
            raise err

    logger.info("Successfully processed and saved %d records.", processed_count)
    return {
        "statusCode": 200,
        "processed_records": processed_count
    }
