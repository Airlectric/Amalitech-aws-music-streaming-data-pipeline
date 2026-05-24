import os
from unittest.mock import patch, MagicMock

os.environ["BRONZE_BUCKET"] = "test-bronze"
os.environ["ARCHIVE_BUCKET"] = "test-archive"

from stream_archiver import lambda_handler, _list_stream_keys


@patch("stream_archiver.s3")
def test_archiver_with_keys(mock_s3, lambda_context):
    event = {"execution_id": "exec-001", "keys": ["streams/2024/06/25/batch_test.json"]}
    result = lambda_handler(event, lambda_context)
    assert result["execution_id"] == "exec-001"
    assert result["archived_count"] == 1
    assert result["results"][0]["status"] == "archived"
    mock_s3.copy_object.assert_called_once()
    mock_s3.delete_object.assert_called_once()


@patch("stream_archiver.s3")
def test_archiver_no_keys_lists_bronze(mock_s3, lambda_context):
    mock_s3.get_paginator.return_value.paginate.return_value = [
        {
            "Contents": [
                {"Key": "streams/2024/06/25/batch_1.json"},
                {"Key": "streams/2024/06/25/batch_2.json"},
            ]
        }
    ]
    event = {"execution_id": "exec-002", "keys": []}
    result = lambda_handler(event, lambda_context)
    assert result["archived_count"] == 2
    assert mock_s3.copy_object.call_count == 2
    assert mock_s3.delete_object.call_count == 2


@patch("stream_archiver.s3")
def test_archiver_skips_manifest_in_list(mock_s3, lambda_context):
    mock_s3.get_paginator.return_value.paginate.return_value = [
        {
            "Contents": [
                {"Key": "streams/2024/06/25/batch_1.json"},
                {"Key": "streams/2024/06/25/manifest.json"},
            ]
        }
    ]
    event = {"execution_id": "exec-003", "keys": []}
    result = lambda_handler(event, lambda_context)
    assert result["archived_count"] == 1


@patch("stream_archiver.s3")
def test_archiver_copy_error_does_not_crash(mock_s3, lambda_context):
    mock_s3.copy_object.side_effect = [Exception("Copy failed"), None]
    event = {
        "execution_id": "exec-004",
        "keys": ["streams/2024/06/25/batch_1.json", "streams/2024/06/25/batch_2.json"],
    }
    result = lambda_handler(event, lambda_context)
    assert result["archived_count"] == 2
    assert result["results"][0]["status"] == "failed"
    assert result["results"][1]["status"] == "archived"


@patch("stream_archiver.s3")
def test_list_stream_keys(mock_s3):
    mock_s3.get_paginator.return_value.paginate.return_value = [
        {
            "Contents": [
                {"Key": "streams/2024/06/25/batch_test.json"},
                {"Key": "streams/2024/06/25/manifest.json"},
            ]
        }
    ]
    keys = _list_stream_keys("test-bronze")
    assert "streams/2024/06/25/batch_test.json" in keys
    assert "streams/2024/06/25/manifest.json" not in keys
