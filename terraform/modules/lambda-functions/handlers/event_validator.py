import json
import os
import sys
from datetime import datetime, timezone
import boto3

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")
ssm = boto3.client("ssm")

BRONZE_BUCKET = os.environ["BRONZE_BUCKET"]
DQ_TABLE_NAME = os.environ["DQ_TABLE_NAME"]
EXPECTED_SCHEMA_TYPE = os.environ.get("EXPECTED_SCHEMA_TYPE", "music_stream")
SSM_PARAM_PATH = os.environ.get("SSM_PARAM_PATH", "/dev/validator/expected_schema")

REQUIRED_FIELDS = ["artist_id", "title", "event_timestamp", "user_id"]

# Expected fields from Glue catalog bronze schema (used for drift detection)
# Avoiding direct Glue API call to prevent VPC endpoint timeout issues
EXPECTED_FIELDS = REQUIRED_FIELDS + [
    "artist_name",
    "album",
    "duration_ms",
    "genre",
    "event_date",
    "user_country",
    "platform",
    "play_duration_seconds",
    "skipped",
    "event_id",
]


def lambda_handler(event, context):
    bucket = event.get("bucket", "")
    key = event.get("key", "")
    execution_id = event.get("execution_id", context.aws_request_id)
    event_time = event.get("event_time", datetime.now(timezone.utc).isoformat())

    if not bucket or not key:
        return {
            "valid": False,
            "execution_id": execution_id,
            "error": "Missing bucket or key",
        }

    try:
        obj = s3.get_object(Bucket=bucket, Key=key)
        raw = obj["Body"].read().decode("utf-8")
    except Exception as e:
        return {
            "valid": False,
            "execution_id": execution_id,
            "bucket": bucket,
            "key": key,
            "error": f"Failed to read object: {str(e)}",
        }

    records = _parse_json(raw)
    record_count = len(records)
    valid, errors = _validate_records(records)
    drift = _detect_schema_drift(records)

    manifest_key = key.replace(".json", "/manifest.json")
    manifest = {
        "source_key": key,
        "valid": valid,
        "record_count": record_count,
        "error_count": len(errors),
        "schema_type": EXPECTED_SCHEMA_TYPE,
        "schema_drift": drift,
        "execution_id": execution_id,
        "validated_at": datetime.now(timezone.utc).isoformat(),
    }
    if not valid:
        manifest["errors"] = errors[:10]

    s3.put_object(
        Bucket=bucket,
        Key=manifest_key,
        Body=json.dumps(manifest),
        ContentType="application/json",
    )

    tag_value = "false" if not valid else "true"
    s3.put_object_tagging(
        Bucket=bucket,
        Key=key,
        Tagging={"TagSet": [{"Key": "validated", "Value": tag_value}]},
    )

    _write_dq_report(bucket, key, execution_id, event_time, record_count, errors, drift)

    return {
        "valid": valid,
        "execution_id": execution_id,
        "bucket": bucket,
        "key": key,
        "record_count": record_count,
        "error_count": len(errors),
        "schema_drift": drift,
    }


def _parse_json(raw):
    lines = raw.strip().split("\n")
    if len(lines) == 1:
        obj = json.loads(lines[0])
        if isinstance(obj, list):
            return obj
        return [obj]
    return [json.loads(line) for line in lines if line.strip()]


def _validate_records(records):
    errors = []
    for i, rec in enumerate(records):
        if not isinstance(rec, dict):
            errors.append(f"Record {i}: not a dict")
            continue
        for field in REQUIRED_FIELDS:
            if (
                field not in rec
                or rec.get(field) is None
                or str(rec.get(field, "")).strip() == ""
            ):
                errors.append(f"Record {i}: missing or empty required field '{field}'")
    return len(errors) == 0, errors


def _detect_schema_drift(records):
    expected_set = set(EXPECTED_FIELDS)
    observed_fields = set()
    for rec in records:
        if isinstance(rec, dict):
            observed_fields.update(rec.keys())

    unknown = observed_fields - expected_set
    missing = expected_set - observed_fields

    drift = {}
    if unknown:
        drift["unknown_fields"] = sorted(unknown)
    if missing:
        drift["missing_optional_fields"] = sorted(missing - set(REQUIRED_FIELDS))
        drift["missing_required_fields"] = sorted(missing & set(REQUIRED_FIELDS))
    return drift


def _write_dq_report(
    bucket, key, execution_id, event_time, record_count, errors, drift
):
    try:
        table = dynamodb.Table(DQ_TABLE_NAME)
        table.put_item(
            Item={
                "batch_id": execution_id,
                "event_date": event_time[:10],
                "bucket": bucket,
                "key": key,
                "record_count": record_count,
                "error_count": len(errors),
                "errors": errors[:20],
                "schema_drift": drift,
                "processed_at": datetime.now(timezone.utc).isoformat(),
                "expires_at": int(datetime.now(timezone.utc).timestamp()) + 2592000,
            }
        )
    except Exception:
        pass
