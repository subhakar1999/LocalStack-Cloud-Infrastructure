"""Replace these task handlers with the application's business logic later."""
import json
import os
import uuid
from decimal import Decimal
import boto3


def validate(event, context):
    if not isinstance(event, dict) or not event.get("customer"):
        raise ValueError("customer is required")
    items = event.get("items")
    if not isinstance(items, list) or not items:
        raise ValueError("at least one item is required")
    for item in items:
        if not isinstance(item, dict) or not item.get("name"):
            raise ValueError("each item needs a name")
        quantity = item.get("quantity")
        if isinstance(quantity, bool) or not isinstance(quantity, int) or quantity < 1:
            raise ValueError("quantity must be a positive integer")
        price = item.get("price")
        if isinstance(price, bool) or not isinstance(price, (int, float)):
            raise ValueError("price must be numeric")
        amount = Decimal(str(price))
        if not amount.is_finite() or amount < 0:
            raise ValueError("price must be finite and nonnegative")
    return {**event, "orderId": event.get("orderId") or str(uuid.uuid4()), "status": "VALIDATED"}


def calculate(event, context):
    total = sum(Decimal(str(item["price"])) * item["quantity"] for item in event["items"])
    return {**event, "total": str(total.quantize(Decimal("0.01"))), "status": "CALCULATED"}


def persist(event, context):
    endpoint = os.environ.get("AWS_ENDPOINT_URL")
    if not endpoint and os.environ.get("LOCALSTACK_HOSTNAME"):
        endpoint = "http://" + os.environ["LOCALSTACK_HOSTNAME"] + ":4566"
    table = boto3.resource("dynamodb", endpoint_url=endpoint).Table(os.environ["ORDERS_TABLE"])
    result = {**event, "status": "COMPLETED"}
    table.put_item(Item={"pk": "ORDER#" + str(event["orderId"]), "sk": "DETAILS", "status": "COMPLETED", "customer": event["customer"], "total": Decimal(event["total"]), "payload": json.dumps(result)})
    return result
