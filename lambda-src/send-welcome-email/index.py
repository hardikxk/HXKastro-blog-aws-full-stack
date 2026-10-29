import json
import os
import boto3

sns = boto3.client("sns")
TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]


def handler(event, context):
    """
    Consumes signups off SQS and notifies the site owner via the shared
    SNS topic.
    """
    for record in event["Records"]:
        payload = json.loads(record["body"])
        email = payload.get("email", "unknown")

        sns.publish(
            TopicArn=TOPIC_ARN,
            Subject="New newsletter subscriber",
            Message=f"{email} just subscribed to the blog newsletter.",
        )

    return {"statusCode": 200}
