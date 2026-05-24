import json
import os
from datetime import datetime
import boto3

s3 = boto3.client("s3")

BRONZE_BUCKET = os.environ["BRONZE_BUCKET"]
ARCHIVE_BUCKET = os.environ["ARCHIVE_BUCKET"]


def lambda_handler(event, context):
    execution_id = event.get("execution_id", context.aws_request_id)
    keys_to_archive = event.get("keys", [])

    if not keys_to_archive:
        bronze_keys = _list_stream_keys(BRONZE_BUCKET)
        keys_to_archive = bronze_keys

    results = []
    for key in keys_to_archive:
        try:
            copy_source = {"Bucket": BRONZE_BUCKET, "Key": key}
            archive_key = f"archived/{datetime.utcnow().strftime('%Y/%m/%d')}/{key.split('/')[-1]}"

            s3.copy_object(
                CopySource=copy_source,
                Bucket=ARCHIVE_BUCKET,
                Key=archive_key,
            )
            s3.delete_object(Bucket=BRONZE_BUCKET, Key=key)

            results.append({"key": key, "status": "archived"})

        except Exception as e:
            results.append({"key": key, "status": "failed", "error": str(e)})

    return {"execution_id": execution_id, "archived_count": len(results), "results": results}


def _list_stream_keys(bucket):
    keys = []
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix="streams/"):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            if not key.endswith("/") and not key.endswith("manifest.json"):
                keys.append(key)
    return keys
