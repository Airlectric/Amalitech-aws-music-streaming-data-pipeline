import os
from unittest.mock import patch

os.environ["BRONZE_BUCKET"] = "test-bronze"
os.environ["QUARANTINE_BUCKET"] = "test-quarantine"

from quarantine_handler import lambda_handler


@patch("quarantine_handler.s3")
def test_quarantine_copies_and_tags(mock_s3, lambda_context):
    event = {
        "bucket": "test-bronze",
        "key": "streams/2024/06/25/batch_bad.json",
        "execution_id": "exec-001",
    }
    result = lambda_handler(event, lambda_context)
    assert result["quarantined"] is True
    assert result["quarantine_bucket"] == "test-quarantine"
    assert result["quarantine_key"] == "bronze/streams/2024/06/25/batch_bad.json"
    mock_s3.copy_object.assert_called_once()
    copy_args = mock_s3.copy_object.call_args[1]
    assert copy_args["Bucket"] == "test-quarantine"
    assert copy_args["Key"] == "bronze/streams/2024/06/25/batch_bad.json"
    mock_s3.put_object_tagging.assert_called_once()
    tag_args = mock_s3.put_object_tagging.call_args[1]
    assert tag_args["Bucket"] == "test-bronze"
    assert tag_args["Tagging"]["TagSet"] == [{"Key": "quarantined", "Value": "true"}]


@patch("quarantine_handler.s3")
def test_quarantine_missing_key(mock_s3, lambda_context):
    event = {"bucket": "test-bronze", "execution_id": "exec-002"}
    result = lambda_handler(event, lambda_context)
    assert result["quarantined"] is False
    assert "Missing key" in result.get("error", "")
    mock_s3.copy_object.assert_not_called()


@patch("quarantine_handler.s3")
def test_quarantine_s3_error(mock_s3, lambda_context):
    mock_s3.copy_object.side_effect = Exception("S3 error")
    event = {
        "bucket": "test-bronze",
        "key": "streams/2024/06/25/batch_bad.json",
        "execution_id": "exec-003",
    }
    result = lambda_handler(event, lambda_context)
    assert result["quarantined"] is False
    assert "S3 error" in result.get("error", "")


@patch("quarantine_handler.s3")
def test_quarantine_default_bucket(mock_s3, lambda_context):
    event = {"key": "streams/test.json", "execution_id": "exec-004"}
    result = lambda_handler(event, lambda_context)
    assert result["quarantined"] is True
    assert result["bucket"] == "test-bronze"
