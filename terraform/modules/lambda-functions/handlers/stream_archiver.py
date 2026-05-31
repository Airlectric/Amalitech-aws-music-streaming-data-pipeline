from datetime import datetime, timezone
import os

import boto3

s3 = boto3.client("s3")

BRONZE_BUCKET = os.environ["BRONZE_BUCKET"]
ARCHIVE_BUCKET = os.environ["ARCHIVE_BUCKET"]
STREAM_PREFIX = "streams/landing_date="
MANIFEST_PREFIX = "streams/manifests/"


def lambda_handler(event, context):
    execution_id = event.get("execution_id", context.aws_request_id)
    keys_to_archive = event.get("keys") or []
    if not keys_to_archive and event.get("key"):
        keys_to_archive = [event["key"]]

    if not keys_to_archive:
        keys_to_archive = _list_stream_keys(BRONZE_BUCKET)

    results = []
    for key in keys_to_archive:
        if not _is_archivable_stream(key):
            continue

        try:
            copy_source = {"Bucket": BRONZE_BUCKET, "Key": key}
            archive_key = key

            s3.copy_object(
                CopySource=copy_source,
                Bucket=ARCHIVE_BUCKET,
                Key=archive_key,
            )
            s3.delete_object(Bucket=BRONZE_BUCKET, Key=key)

            results.append({"key": key, "archive_key": archive_key, "status": "archived"})
        except Exception as exc:
            results.append({"key": key, "status": "failed", "error": str(exc)})

    archived = [result for result in results if result.get("status") == "archived"]
    failed = [result for result in results if result.get("status") == "failed"]

    response = {
        "execution_id": execution_id,
        "archived_count": len(archived),
        "results": results,
        "archived_at": datetime.now(timezone.utc).isoformat(),
    }

    if failed:
        failed_keys = ", ".join(result["key"] for result in failed)
        raise RuntimeError(f"Archive failed for {len(failed)} object(s): {failed_keys}")

    return response


def _list_stream_keys(bucket):
    keys = []
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=STREAM_PREFIX):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            if _is_archivable_stream(key):
                keys.append(key)
    return keys


def _is_archivable_stream(key):
    return (
        bool(key)
        and key.startswith(STREAM_PREFIX)
        and key.endswith(".csv")
        and not key.startswith(MANIFEST_PREFIX)
    )
