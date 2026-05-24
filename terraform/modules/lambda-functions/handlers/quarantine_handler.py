import json
import os
from datetime import datetime, timezone
import boto3

s3 = boto3.client("s3")

BRONZE_BUCKET = os.environ["BRONZE_BUCKET"]
QUARANTINE_BUCKET = os.environ["QUARANTINE_BUCKET"]


def lambda_handler(event, context):
    bucket = event.get("bucket", BRONZE_BUCKET)
    key = event.get("key", "")
    execution_id = event.get("execution_id", context.aws_request_id)

    if not key:
        return {
            "quarantined": False,
            "execution_id": execution_id,
            "error": "Missing key",
        }

    quarantine_key = f"bronze/{key}"

    try:
        copy_source = {"Bucket": bucket, "Key": key}
        s3.copy_object(
            CopySource=copy_source,
            Bucket=QUARANTINE_BUCKET,
            Key=quarantine_key,
        )

        s3.put_object_tagging(
            Bucket=bucket,
            Key=key,
            Tagging={"TagSet": [{"Key": "quarantined", "Value": "true"}]},
        )

        return {
            "quarantined": True,
            "execution_id": execution_id,
            "bucket": bucket,
            "key": key,
            "quarantine_bucket": QUARANTINE_BUCKET,
            "quarantine_key": quarantine_key,
        }

    except Exception as e:
        return {
            "quarantined": False,
            "execution_id": execution_id,
            "bucket": bucket,
            "key": key,
            "error": str(e),
        }
