"""Event router Lambda — the entry point between S3 object events and the Step Functions pipeline.

Sits between EventBridge (which receives S3 `Object Created` events on the bronze bucket)
and the Step Functions state machine that orchestrates the medallion ETL flow.

EventBridge can target Step Functions directly, so this Lambda is a *deliberate* extra
hop. Its jobs:

1. Pre-flight filter — reject S3 events for objects we don't process (manifests,
   non-CSV files, anything outside the `streams/landing_date=*` prefix) *before*
   spending a Step Functions execution + Glue cold-start on garbage.
2. Payload shaping — flatten the verbose S3 event JSON into the compact input shape
   the state machine expects, so downstream tasks don't each dig through
   `detail.object.key`.
3. Audit log line — one structured log entry per inbound file in one place, useful
   during incident triage.
4. Idempotency via execution-name dedupe — S3 → EventBridge delivers at-least-once,
   so duplicate events for the same object can arrive. We set the SFN execution
   `name` to the S3 object's eTag (content-derived hash), which makes
   `StartExecution` reject duplicates within the 90-day name-uniqueness window.
   Re-uploading the same bytes is a no-op; different content gets a new run.
"""

import json
import os
from urllib.parse import unquote_plus

import boto3

sfn = boto3.client("stepfunctions")

STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]

# Only objects under this prefix represent a new daily stream batch that should
# trigger the pipeline. Reference data (songs/users) lives elsewhere and is
# loaded out-of-band; manifests are sidecar files written by the validator.
STREAM_PREFIX = "streams/landing_date="
MANIFEST_PREFIX = "streams/manifests/"


def lambda_handler(event, context):
    """Handle one EventBridge `Object Created` notification and start an SFN execution.

    Returns a small JSON envelope (statusCode + body) for observability — the
    return value isn't consumed by anything downstream, but it shows up in
    CloudWatch logs and makes failures easy to spot.
    """
    detail = event.get("detail", {})
    bucket = detail.get("bucket", {}).get("name", "")
    # S3 keys arrive URL-encoded in EventBridge payloads (spaces -> '+', etc.);
    # unquote_plus restores the literal key we need for GetObject calls.
    key = unquote_plus(detail.get("object", {}).get("key", ""))

    if not bucket or not key:
        return {"statusCode": 400, "body": "Missing bucket or key"}

    if not _should_process(key):
        return {"statusCode": 200, "body": "Skipped"}

    landing_date = _extract_landing_date(key)
    # eTag is content-derived (MD5 for single-part, or "<md5>-<n>" for multipart).
    # Using it as the SFN execution `name` is what gives us idempotent dedupe:
    # the same bytes always map to the same name, and SFN enforces name-uniqueness
    # for 90 days. Fall back to the Lambda request id if eTag is somehow missing —
    # better to allow a possible duplicate run than to drop a legitimate event.
    etag = detail.get("object", {}).get("etag", "").strip('"')
    execution_name = etag or context.aws_request_id
    execution_input = {
        "bucket": bucket,
        "key": key,
        "landing_date": landing_date,
        "event_time": event.get("time", ""),
        # Surface the SFN execution name as a stable id downstream tasks can use
        # to correlate logs/manifests/DQ reports across retries of the same run.
        "execution_id": execution_name,
    }

    try:
        response = sfn.start_execution(
            stateMachineArn=STATE_MACHINE_ARN,
            name=execution_name,
            input=json.dumps(execution_input),
        )
    except sfn.exceptions.ExecutionAlreadyExists:
        # Duplicate S3 event for an object we've already started processing —
        # this is the *intended* outcome of the dedupe, not an error.
        print(f"Duplicate event for {bucket}/{key} (eTag={etag}); skipping")
        return {"statusCode": 200, "body": "Duplicate skipped"}

    return {
        "statusCode": 200,
        "body": json.dumps(
            {
                "execution_arn": response["executionArn"],
                "start_date": response["startDate"].isoformat(),
            }
        ),
    }


def _should_process(key):
    """Pre-flight filter — return True only for new stream batches we should ingest.

    Rejects (silently skips):
      - Objects outside `streams/landing_date=…/` (e.g. reference data uploads).
      - Manifest sidecars under `streams/manifests/` written by the validator —
        without this guard, every manifest write would re-trigger the pipeline
        in a loop.
      - Non-CSV files (incomplete multipart uploads sometimes land as `.tmp`).
    """
    return (
        key.startswith(STREAM_PREFIX)
        and key.endswith(".csv")
        and not key.startswith(MANIFEST_PREFIX)
    )


def _extract_landing_date(key):
    """Pull `YYYY-MM-DD` out of a Hive-style `landing_date=YYYY-MM-DD/` prefix.

    The landing date is the partition key downstream tasks use to locate this
    batch's Silver/Gold output, so it's worth surfacing in the SFN input rather
    than re-parsing the key in every task. Returns "" if the marker is missing
    (defensive — `_should_process` already guarantees it's present in practice).
    """
    marker = "landing_date="
    if marker not in key:
        return ""

    suffix = key.split(marker, 1)[1]
    return suffix.split("/", 1)[0]
