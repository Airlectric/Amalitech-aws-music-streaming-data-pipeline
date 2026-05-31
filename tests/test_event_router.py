import json
import os
from unittest.mock import MagicMock, patch

os.environ["STATE_MACHINE_ARN"] = (
    "arn:aws:states:us-east-1:123456789012:stateMachine:test-pipeline"
)

from event_router import _extract_landing_date, lambda_handler


def _make_s3_event(
    bucket="test-bronze", key="streams/landing_date=2024-06-25/streams1.csv"
):
    return {
        "detail": {
            "bucket": {"name": bucket},
            "object": {"key": key},
        },
        "time": "2024-06-25T10:00:00Z",
    }


@patch("event_router.sfn")
def test_router_starts_execution(mock_sfn, lambda_context):
    mock_sfn.start_execution.return_value = {
        "executionArn": "arn:aws:states:us-east-1:123:execution:test:exec1",
        "startDate": MagicMock(isoformat=lambda: "2024-01-01T00:00:00"),
    }
    result = lambda_handler(_make_s3_event(), lambda_context)
    assert result["statusCode"] == 200
    body = json.loads(result["body"])
    assert "execution_arn" in body


@patch("event_router.sfn")
def test_router_skips_non_csv(mock_sfn, lambda_context):
    event = _make_s3_event(key="streams/landing_date=2024-06-25/readme.txt")
    result = lambda_handler(event, lambda_context)
    assert result["statusCode"] == 200
    assert "Skipped" in result["body"]
    mock_sfn.start_execution.assert_not_called()


@patch("event_router.sfn")
def test_router_skips_manifests(mock_sfn, lambda_context):
    event = _make_s3_event(
        key="streams/manifests/landing_date=2024-06-25/streams1.csv.json"
    )
    result = lambda_handler(event, lambda_context)
    assert result["statusCode"] == 200
    assert "Skipped" in result["body"]
    mock_sfn.start_execution.assert_not_called()


@patch("event_router.sfn")
def test_router_skips_non_streams(mock_sfn, lambda_context):
    event = _make_s3_event(key="other/test.csv")
    result = lambda_handler(event, lambda_context)
    assert result["statusCode"] == 200
    assert "Skipped" in result["body"]
    mock_sfn.start_execution.assert_not_called()


@patch("event_router.sfn")
def test_router_missing_bucket(mock_sfn, lambda_context):
    event = {"detail": {"object": {"key": "test.csv"}}, "time": ""}
    result = lambda_handler(event, lambda_context)
    assert result["statusCode"] == 400
    mock_sfn.start_execution.assert_not_called()


@patch("event_router.sfn")
def test_router_execution_payload(mock_sfn, lambda_context):
    mock_sfn.start_execution.return_value = {
        "executionArn": "arn:aws:states:us-east-1:123:execution:test:exec1",
        "startDate": MagicMock(isoformat=lambda: "2024-01-01T00:00:00"),
    }
    lambda_handler(_make_s3_event(), lambda_context)
    call_kwargs = mock_sfn.start_execution.call_args[1]
    payload = json.loads(call_kwargs["input"])
    assert payload["bucket"] == "test-bronze"
    assert payload["key"] == "streams/landing_date=2024-06-25/streams1.csv"
    assert payload["landing_date"] == "2024-06-25"
    assert payload["event_time"] == "2024-06-25T10:00:00Z"


def test_extract_landing_date():
    assert (
        _extract_landing_date("streams/landing_date=2024-06-25/streams1.csv")
        == "2024-06-25"
    )
