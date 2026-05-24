import json
import os
from unittest.mock import patch, MagicMock
import pytest

os.environ["BRONZE_BUCKET"] = "test-bronze"
os.environ["DQ_TABLE_NAME"] = "test-dq-reports"
os.environ["EXPECTED_SCHEMA_TYPE"] = "music_stream"
os.environ["SSM_PARAM_PATH"] = "/test/validator/expected_schema"

from event_validator import (
    lambda_handler,
    _parse_json,
    _validate_records,
    _detect_schema_drift,
)


VALID_RECORD = {
    "event_id": "e1",
    "artist_id": "artist-1",
    "artist_name": "Test Artist",
    "title": "Test Song",
    "album": "Test Album",
    "duration_ms": 240000,
    "genre": "pop",
    "event_date": "2024/06/25",
    "event_timestamp": "2024-06-25 10:00:00",
    "user_id": "user-1",
    "user_country": "United States",
    "platform": "mobile",
    "play_duration_seconds": 120,
    "skipped": False,
}


def test_parse_json_single_object():
    raw = json.dumps(VALID_RECORD)
    result = _parse_json(raw)
    assert len(result) == 1
    assert result[0]["event_id"] == "e1"


def test_parse_json_list():
    raw = json.dumps([VALID_RECORD, VALID_RECORD])
    result = _parse_json(raw)
    assert len(result) == 2


def test_parse_json_jsonl():
    raw = json.dumps(VALID_RECORD) + "\n" + json.dumps(VALID_RECORD)
    result = _parse_json(raw)
    assert len(result) == 2


def test_validate_records_valid():
    valid, errors = _validate_records([VALID_RECORD])
    assert valid is True
    assert errors == []


def test_validate_records_missing_required():
    bad = VALID_RECORD.copy()
    del bad["artist_id"]
    valid, errors = _validate_records([bad])
    assert valid is False
    assert any("artist_id" in e for e in errors)


def test_validate_records_empty_required():
    bad = VALID_RECORD.copy()
    bad["title"] = ""
    valid, errors = _validate_records([bad])
    assert valid is False
    assert any("title" in e for e in errors)


def test_validate_records_none_required():
    bad = VALID_RECORD.copy()
    bad["user_id"] = None
    valid, errors = _validate_records([bad])
    assert valid is False
    assert any("user_id" in e for e in errors)


def test_validate_records_non_dict():
    valid, errors = _validate_records(["not_a_dict"])
    assert valid is False
    assert any("not a dict" in e for e in errors)


def test_validate_records_multiple_errors():
    bad1 = {"event_id": "e1"}
    bad2 = {"event_id": "e2"}
    valid, errors = _validate_records([bad1, bad2])
    assert valid is False
    assert len(errors) >= 2


def test_detect_drift_no_drift():
    drift = _detect_schema_drift([VALID_RECORD])
    assert drift == {}


def test_detect_drift_unknown_fields():
    rec = VALID_RECORD.copy()
    rec["unexpected_field"] = "surprise"
    drift = _detect_schema_drift([rec])
    assert "unknown_fields" in drift
    assert "unexpected_field" in drift["unknown_fields"]


def test_detect_drift_missing_optional():
    rec = VALID_RECORD.copy()
    del rec["album"]
    drift = _detect_schema_drift([rec])
    assert "missing_optional_fields" in drift
    assert "album" in drift["missing_optional_fields"]


def test_detect_drift_missing_required():
    rec = VALID_RECORD.copy()
    del rec["artist_id"]
    drift = _detect_schema_drift([rec])
    assert "missing_required_fields" in drift
    assert "artist_id" in drift["missing_required_fields"]


@patch("event_validator.s3")
@patch("event_validator.dynamodb")
def test_lambda_handler_valid_event(mock_dynamodb, mock_s3, lambda_context):
    mock_s3.get_object.return_value = {
        "Body": MagicMock(read=lambda: json.dumps(VALID_RECORD).encode())
    }
    mock_table = MagicMock()
    mock_dynamodb.Table.return_value = mock_table

    event = {
        "bucket": "test-bronze",
        "key": "streams/2024/06/25/batch_test.json",
        "execution_id": "exec-001",
        "event_time": "2024-06-25T10:00:00Z",
    }
    result = lambda_handler(event, lambda_context)

    assert result["valid"] is True
    assert result["record_count"] == 1
    assert result["error_count"] == 0
    assert result["execution_id"] == "exec-001"
    assert result["bucket"] == "test-bronze"
    assert result["key"] == "streams/2024/06/25/batch_test.json"

    mock_s3.put_object.assert_called()
    mock_s3.put_object_tagging.assert_called_once()
    mock_table.put_item.assert_called_once()


@patch("event_validator.s3")
def test_lambda_handler_missing_bucket(mock_s3, lambda_context):
    result = lambda_handler({"key": "test.json", "execution_id": "e1"}, lambda_context)
    assert result["valid"] is False
    assert "Missing bucket or key" in str(result.get("error", ""))


@patch("event_validator.s3")
def test_lambda_handler_missing_key(mock_s3, lambda_context):
    result = lambda_handler(
        {"bucket": "test-bronze", "execution_id": "e1"}, lambda_context
    )
    assert result["valid"] is False
    assert "Missing bucket or key" in str(result.get("error", ""))


@patch("event_validator.s3")
def test_lambda_handler_s3_read_error(mock_s3, lambda_context):
    mock_s3.get_object.side_effect = Exception("S3 error")
    result = lambda_handler(
        {"bucket": "test-bronze", "key": "test.json", "execution_id": "e1"},
        lambda_context,
    )
    assert result["valid"] is False
    assert "S3 error" in str(result.get("error", ""))


@patch("event_validator.s3")
@patch("event_validator.dynamodb")
def test_lambda_handler_invalid_records(mock_dynamodb, mock_s3, lambda_context):
    invalid_data = {"event_id": "e1"}
    mock_s3.get_object.return_value = {
        "Body": MagicMock(read=lambda: json.dumps(invalid_data).encode())
    }

    result = lambda_handler(
        {
            "bucket": "test-bronze",
            "key": "streams/2024/06/25/batch_bad.json",
            "execution_id": "exec-002",
        },
        lambda_context,
    )

    assert result["valid"] is False
    assert result["error_count"] > 0

    manifest_call = [
        c
        for c in mock_s3.put_object.call_args_list
        if c[1]["Key"].endswith("manifest.json")
    ]
    assert len(manifest_call) > 0
    manifest = json.loads(manifest_call[0][1]["Body"])
    assert manifest["valid"] is False


@patch("event_validator.s3")
@patch("event_validator.dynamodb")
def test_lambda_handler_dynamodb_error_is_caught(
    mock_dynamodb, mock_s3, lambda_context
):
    mock_s3.get_object.return_value = {
        "Body": MagicMock(read=lambda: json.dumps(VALID_RECORD).encode())
    }
    mock_table = MagicMock()
    mock_table.put_item.side_effect = Exception("DynamoDB error")
    mock_dynamodb.Table.return_value = mock_table

    result = lambda_handler(
        {
            "bucket": "test-bronze",
            "key": "streams/2024/06/25/batch_test.json",
            "execution_id": "exec-003",
        },
        lambda_context,
    )

    assert result["valid"] is True  # DynamoDB failure is non-fatal
