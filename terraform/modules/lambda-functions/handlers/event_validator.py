import csv
import io
import json
import os
from datetime import datetime, timezone

import boto3

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")

BRONZE_BUCKET = os.environ["BRONZE_BUCKET"]
DQ_TABLE_NAME = os.environ["DQ_TABLE_NAME"]

REQUIRED_FIELDS = ["user_id", "track_id", "listen_time"]
OPTIONAL_FIELDS = []


def lambda_handler(event, context):
    bucket = event.get("bucket", "")
    key = event.get("key", "")
    execution_id = event.get("execution_id", context.aws_request_id)
    event_time = event.get("event_time", datetime.now(timezone.utc).isoformat())
    landing_date = event.get("landing_date", "")

    if not bucket or not key:
        return {
            "valid": False,
            "execution_id": execution_id,
            "error": "Missing bucket or key",
        }

    try:
        obj = s3.get_object(Bucket=bucket, Key=key)
        raw = obj["Body"].read().decode("utf-8")
    except Exception as exc:
        print(f"Failed to read {bucket}/{key}: {exc}")
        return {
            "valid": False,
            "execution_id": execution_id,
            "bucket": bucket,
            "key": key,
            "error": f"Failed to read object: {exc}",
        }

    rows = _parse_csv(raw)
    record_count = len(rows)
    valid, errors = _validate_records(rows)
    drift = _detect_schema_drift(rows)
    run_date = _derive_run_date(rows, landing_date)

    manifest_key = _manifest_key_for(key)
    manifest = {
        "source_key": key,
        "landing_date": landing_date,
        "run_date": run_date,
        "valid": valid,
        "record_count": record_count,
        "error_count": len(errors),
        "schema_drift": drift,
        "execution_id": execution_id,
        "validated_at": datetime.now(timezone.utc).isoformat(),
    }
    if errors:
        manifest["errors"] = errors[:20]

    s3.put_object(
        Bucket=bucket,
        Key=manifest_key,
        Body=json.dumps(manifest),
        ContentType="application/json",
    )

    s3.put_object_tagging(
        Bucket=bucket,
        Key=key,
        Tagging={
            "TagSet": [
                {"Key": "validated", "Value": "true" if valid else "false"},
                {"Key": "pipeline_run_id", "Value": execution_id[:256]},
                {"Key": "landing_date", "Value": landing_date[:256] if landing_date else "unknown"},
            ]
        },
    )

    _write_dq_report(
        bucket=bucket,
        key=key,
        execution_id=execution_id,
        event_time=event_time,
        record_count=record_count,
        errors=errors,
        drift=drift,
    )

    return {
        "valid": valid,
        "execution_id": execution_id,
        "bucket": bucket,
        "key": key,
        "landing_date": landing_date,
        "run_date": run_date,
        "record_count": record_count,
        "error_count": len(errors),
        "schema_drift": drift,
    }


def _parse_csv(raw):
    reader = csv.DictReader(io.StringIO(raw))
    return list(reader)


def _validate_records(rows):
    errors = []

    if not rows:
        return False, ["CSV contains no data rows"]

    for index, row in enumerate(rows, start=2):
        if not isinstance(row, dict):
            errors.append(f"Row {index}: not a structured record")
            continue

        for field in REQUIRED_FIELDS:
            value = row.get(field)
            if value is None or str(value).strip() == "":
                errors.append(f"Row {index}: missing required field '{field}'")

    return len(errors) == 0, errors


def _detect_schema_drift(rows):
    if not rows:
        return {"missing_required_fields": REQUIRED_FIELDS}

    observed_fields = set(rows[0].keys())
    required_fields = set(REQUIRED_FIELDS)
    optional_fields = set(OPTIONAL_FIELDS)
    expected_fields = required_fields | optional_fields

    drift = {}
    unknown = observed_fields - expected_fields
    missing_required = required_fields - observed_fields
    missing_optional = optional_fields - observed_fields

    if unknown:
        drift["unknown_fields"] = sorted(unknown)
    if missing_required:
        drift["missing_required_fields"] = sorted(missing_required)
    if missing_optional:
        drift["missing_optional_fields"] = sorted(missing_optional)

    return drift


def _derive_run_date(rows, landing_date):
    observed_dates = []

    for row in rows:
        value = row.get("listen_time")
        if not value:
            continue
        try:
            observed_dates.append(datetime.strptime(value, "%Y-%m-%d %H:%M:%S").date())
        except ValueError:
            continue

    if not observed_dates:
        return landing_date

    # Current source files are daily batches, so the event date in the data is the correct KPI date.
    return min(observed_dates).isoformat()


def _manifest_key_for(source_key):
    if source_key.startswith("streams/"):
        return f"streams/manifests/{source_key[len('streams/'):]}.json"
    return f"streams/manifests/{source_key}.json"


def _write_dq_report(bucket, key, execution_id, event_time, record_count, errors, drift):
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
    except Exception as exc:
        print(f"Failed to write DQ report for {bucket}/{key}: {exc}")
