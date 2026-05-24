import json
import os
import boto3

sfn = boto3.client("stepfunctions")

STATE_MACHINE_ARN = os.environ["STATE_MACHINE_ARN"]


def lambda_handler(event, context):
    detail = event.get("detail", {})
    bucket = detail.get("bucket", {}).get("name", "")
    key = detail.get("object", {}).get("key", "")

    if not bucket or not key:
        return {"statusCode": 400, "body": "Missing bucket or key"}

    if not key.startswith("streams/") or key.endswith("manifest.json"):
        return {"statusCode": 200, "body": "Skipped"}

    execution_input = json.dumps({
        "bucket": bucket,
        "key": key,
        "event_time": event.get("time", ""),
        "execution_id": f"{bucket}-{key.replace('/', '-')}-{context.aws_request_id[:8]}",
    })

    response = sfn.start_execution(
        stateMachineArn=STATE_MACHINE_ARN,
        input=execution_input,
    )

    return {
        "statusCode": 200,
        "body": json.dumps({
            "execution_arn": response["executionArn"],
            "start_date": response["startDate"].isoformat(),
        }),
    }
