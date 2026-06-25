import json
import logging
import os
from urllib.parse import unquote_plus

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]

sfn = boto3.client("stepfunctions")

STREAM_PREFIX = "streams/landing_date="
MANIFEST_PREFIX = "streams/manifests/"


def _should_process(key):
    return (
        key.startswith(STREAM_PREFIX)
        and key.endswith(".csv")
        and not key.startswith(MANIFEST_PREFIX)
    )


def _extract_landing_date(key):
    marker = "landing_date="
    if marker not in key:
        return ""
    suffix = key.split(marker, 1)[1]
    return suffix.split("/", 1)[0]


def _replay_message(record):
    message_id = record.get("messageId", "unknown")
    body = record.get("body", "")

    try:
        event = json.loads(body)
    except json.JSONDecodeError:
        logger.error("Message %s has invalid JSON body; leaving in DLQ", message_id)
        return False

    detail = event.get("detail", {})
    bucket = detail.get("bucket", {}).get("name", "")
    key = unquote_plus(detail.get("object", {}).get("key", ""))

    if not bucket or not key:
        logger.error("Message %s missing bucket or key; leaving in DLQ", message_id)
        return False

    if not _should_process(key):
        logger.info("Message %s key=%s does not match pipeline prefix; skipping", message_id, key)
        return True

    etag = detail.get("object", {}).get("etag", "").strip('"')
    # Reuse etag-based execution name for idempotency — same content always maps
    # to the same name, so SFN rejects duplicates within its 90-day window.
    execution_name = etag or message_id
    execution_input = {
        "bucket": bucket,
        "key": key,
        "landing_date": _extract_landing_date(key),
        "event_time": event.get("time", ""),
        "execution_id": execution_name,
    }

    try:
        resp = sfn.start_execution(
            stateMachineArn=STATE_MACHINE_ARN,
            name=execution_name,
            input=json.dumps(execution_input),
        )
        logger.info("Replayed message %s → execution %s", message_id, resp["executionArn"])
        return True
    except sfn.exceptions.ExecutionAlreadyExists:
        logger.info("Execution already exists for message %s (etag=%s); skipping", message_id, etag)
        return True
    except ClientError as exc:
        logger.error("Failed to start execution for message %s: %s", message_id, exc)
        return False


def lambda_handler(event, context):
    failures = []
    for record in event.get("Records", []):
        if not _replay_message(record):
            failures.append({"itemIdentifier": record["messageId"]})
    return {"batchItemFailures": failures}
