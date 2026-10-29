import os
import boto3

s3 = boto3.client("s3")


def handler(event, context):
    """
    Triggered on S3 image uploads under originals/. Processes and copies
    objects into thumbnails/ to complete the event-driven media pipeline.
    """
    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        key = record["s3"]["object"]["key"]

        if not key.startswith("originals/"):
            continue

        thumb_key = key.replace("originals/", "thumbnails/", 1)
        s3.copy_object(
            Bucket=bucket,
            CopySource={"Bucket": bucket, "Key": key},
            Key=thumb_key,
        )
        print(f"Wrote {thumb_key} from {key}")

    return {"statusCode": 200}
