import json
import os
import re
import boto3

dynamodb = boto3.resource("dynamodb")
sqs = boto3.client("sqs")

TABLE = dynamodb.Table(os.environ["DYNAMODB_TABLE"])
QUEUE_URL = os.environ["SQS_QUEUE_URL"]

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def handler(event, context):
    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"error": "Invalid JSON body"})

    email = (body.get("email") or "").strip().lower()
    if not EMAIL_RE.match(email):
        return _response(400, {"error": "A valid email is required"})

    TABLE.put_item(Item={"PK": "SUBSCRIBER", "SK": email})

    sqs.send_message(QueueUrl=QUEUE_URL, MessageBody=json.dumps({"email": email}))

    return _response(200, {"message": "Subscribed"})


def _response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
