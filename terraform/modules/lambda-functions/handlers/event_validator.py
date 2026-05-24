import json
import os
import boto3

s3 = boto3.client("s3")
ssm = boto3.client("ssm")

EXPECTED_SCHEMA_TYPE = os.environ.get("EXPECTED_SCHEMA_TYPE", "music_stream")
SSM_PARAM_PATH = os.environ.get("SSM_PARAM_PATH", "/dev/validator/expected_schema")


def lambda_handler(event, context):
    records = event.get("Records", [])
    if not records:
        return {"statusCode": 400, "body": "No records"}

    results = []
    for record in records:
        bucket = record["s3"]["bucket"]["name"]
        key = record["s3"]["object"]["key"]

        if not key.startswith("streams/"):
            continue

        try:
            schema_type = _get_schema_type()
            obj = s3.get_object(Bucket=bucket, Key=key)
            raw = obj["Body"].read().decode("utf-8")

            records_data = _parse_json(raw)
            valid, errors = _validate_records(records_data, schema_type)

            manifest_key = key.replace(".json", "/manifest.json")
            manifest = {
                "source_key": key,
                "valid": valid,
                "error_count": len(errors),
                "record_count": len(records_data) if isinstance(records_data, list) else 1,
                "schema_type": schema_type,
            }

            if not valid:
                manifest["errors"] = errors[:10]

            s3.put_object(
                Bucket=bucket,
                Key=manifest_key,
                Body=json.dumps(manifest),
                ContentType="application/json",
            )

            if valid:
                s3.put_object_tagging(
                    Bucket=bucket,
                    Key=key,
                    Tagging={"TagSet": [{"Key": "validated", "Value": "true"}]},
                )
            else:
                s3.put_object_tagging(
                    Bucket=bucket,
                    Key=key,
                    Tagging={"TagSet": [{"Key": "validated", "Value": "false"}]},
                )

            results.append({"key": key, "valid": valid, "manifest_key": manifest_key})

        except Exception as e:
            results.append({"key": key, "valid": False, "error": str(e)})

    return {"statusCode": 200, "body": json.dumps(results)}


def _get_schema_type():
    try:
        param = ssm.get_parameter(Name=SSM_PARAM_PATH)
        return param["Parameter"]["Value"]
    except Exception:
        return EXPECTED_SCHEMA_TYPE


def _parse_json(raw):
    lines = raw.strip().split("\n")
    if len(lines) == 1:
        obj = json.loads(lines[0])
        if isinstance(obj, list):
            return obj
        return [obj]
    return [json.loads(line) for line in lines if line.strip()]


def _validate_records(records, schema_type):
    errors = []
    for i, rec in enumerate(records):
        if not isinstance(rec, dict):
            errors.append(f"Record {i}: not a dict")
            continue
        if "artist_id" not in rec or not rec.get("artist_id"):
            errors.append(f"Record {i}: missing artist_id")
        if "title" not in rec or not rec.get("title"):
            errors.append(f"Record {i}: missing title")
        if "event_timestamp" not in rec or not rec.get("event_timestamp"):
            errors.append(f"Record {i}: missing event_timestamp")
        if "user_id" not in rec or not rec.get("user_id"):
            errors.append(f"Record {i}: missing user_id")
    return len(errors) == 0, errors
