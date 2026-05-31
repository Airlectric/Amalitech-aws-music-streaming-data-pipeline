import json
import os
from unittest.mock import MagicMock, patch

os.environ["BRONZE_BUCKET"] = "test-bronze"
os.environ["DQ_TABLE_NAME"] = "test-dq-reports"

from event_validator import (
    _detect_schema_drift,
    _derive_run_date,
    _manifest_key_for,
    _parse_csv,
    _validate_records,
    lambda_handler,
)

VALID_CSV = (
    "user_id,track_id,listen_time\n"
    "26213,4dBa8T7oDV9WvGr7kVS4Ez,2024-06-25 17:43:13\n"
)


def test_parse_csv():
    rows = _parse_csv(VALID_CSV)
    assert len(rows) == 1
    assert rows[0]["user_id"] == "26213"


def test_validate_records_valid():
    valid, errors = _validate_records(_parse_csv(VALID_CSV))
    assert valid is True
    assert errors == []


def test_validate_records_missing_required():
    raw = "user_id,track_id,listen_time\n26213,,2024-06-25 17:43:13\n"
    valid, errors = _validate_records(_parse_csv(raw))
    assert valid is False
    assert any("track_id" in error for error in errors)


def test_validate_records_empty_csv():
    raw = "user_id,track_id,listen_time\n"
    valid, errors = _validate_records(_parse_csv(raw))
    assert valid is False
    assert "no data rows" in errors[0].lower()


def test_detect_schema_drift_no_drift():
    drift = _detect_schema_drift(_parse_csv(VALID_CSV))
    assert drift == {}


def test_detect_schema_drift_unknown_field():
    raw = "user_id,track_id,listen_time,unexpected\n26213,abc,2024-06-25 17:43:13,x\n"
    drift = _detect_schema_drift(_parse_csv(raw))
    assert "unknown_fields" in drift
    assert "unexpected" in drift["unknown_fields"]


def test_detect_schema_drift_missing_required():
    raw = "user_id,track_id\n26213,abc\n"
    drift = _detect_schema_drift(_parse_csv(raw))
    assert "missing_required_fields" in drift
    assert "listen_time" in drift["missing_required_fields"]


def test_derive_run_date_from_listen_time():
    assert _derive_run_date(_parse_csv(VALID_CSV), "2024-06-30") == "2024-06-25"


def test_manifest_key():
    key = "streams/landing_date=2024-06-25/streams1.csv"
    assert (
        _manifest_key_for(key)
        == "streams/manifests/landing_date=2024-06-25/streams1.csv.json"
    )


@patch("event_validator.s3")
@patch("event_validator.dynamodb")
def test_lambda_handler_valid_event(mock_dynamodb, mock_s3, lambda_context):
    mock_s3.get_object.return_value = {
        "Body": MagicMock(read=lambda: VALID_CSV.encode())
    }
    mock_table = MagicMock()
    mock_dynamodb.Table.return_value = mock_table

    event = {
        "bucket": "test-bronze",
        "key": "streams/landing_date=2024-06-25/streams1.csv",
        "execution_id": "exec-001",
        "event_time": "2024-06-25T10:00:00Z",
        "landing_date": "2024-06-25",
    }
    result = lambda_handler(event, lambda_context)

    assert result["valid"] is True
    assert result["record_count"] == 1
    assert result["error_count"] == 0
    assert result["run_date"] == "2024-06-25"
    mock_s3.put_object.assert_called_once()
    mock_s3.put_object_tagging.assert_called_once()
    mock_table.put_item.assert_called_once()


@patch("event_validator.s3")
def test_lambda_handler_missing_bucket(mock_s3, lambda_context):
    result = lambda_handler({"key": "streams/test.csv", "execution_id": "e1"}, lambda_context)
    assert result["valid"] is False
    assert "Missing bucket or key" in str(result.get("error", ""))


@patch("event_validator.s3")
def test_lambda_handler_s3_read_error(mock_s3, lambda_context):
    mock_s3.get_object.side_effect = Exception("S3 error")
    result = lambda_handler(
        {"bucket": "test-bronze", "key": "streams/test.csv", "execution_id": "e1"},
        lambda_context,
    )
    assert result["valid"] is False
    assert "S3 error" in str(result.get("error", ""))


@patch("event_validator.s3")
@patch("event_validator.dynamodb")
def test_lambda_handler_invalid_records(mock_dynamodb, mock_s3, lambda_context):
    bad_csv = "user_id,track_id,listen_time\n26213,,2024-06-25 17:43:13\n"
    mock_s3.get_object.return_value = {
        "Body": MagicMock(read=lambda: bad_csv.encode())
    }

    result = lambda_handler(
        {
            "bucket": "test-bronze",
            "key": "streams/landing_date=2024-06-25/bad.csv",
            "execution_id": "exec-002",
        },
        lambda_context,
    )

    assert result["valid"] is False
    assert result["error_count"] > 0


@patch("event_validator.s3")
@patch("event_validator.dynamodb")
def test_lambda_handler_dynamodb_error_is_non_fatal(
    mock_dynamodb, mock_s3, lambda_context
):
    mock_s3.get_object.return_value = {
        "Body": MagicMock(read=lambda: VALID_CSV.encode())
    }
    mock_table = MagicMock()
    mock_table.put_item.side_effect = Exception("DynamoDB error")
    mock_dynamodb.Table.return_value = mock_table

    result = lambda_handler(
        {
            "bucket": "test-bronze",
            "key": "streams/landing_date=2024-06-25/streams1.csv",
            "execution_id": "exec-003",
        },
        lambda_context,
    )

    assert result["valid"] is True
