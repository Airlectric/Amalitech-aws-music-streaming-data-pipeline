import os
from unittest.mock import patch

import pytest

os.environ["BRONZE_BUCKET"] = "test-bronze"
os.environ["ARCHIVE_BUCKET"] = "test-archive"

from stream_archiver import _list_stream_keys, lambda_handler


@patch("stream_archiver.s3")
def test_archiver_with_single_key(mock_s3, lambda_context):
    event = {
        "execution_id": "exec-001",
        "key": "streams/landing_date=2024-06-25/streams1.csv",
    }
    result = lambda_handler(event, lambda_context)
    assert result["execution_id"] == "exec-001"
    assert result["archived_count"] == 1
    assert result["results"][0]["status"] == "archived"
    mock_s3.copy_object.assert_called_once()
    mock_s3.delete_object.assert_called_once()


@patch("stream_archiver.s3")
def test_archiver_uses_keys_list(mock_s3, lambda_context):
    event = {
        "execution_id": "exec-002",
        "keys": [
            "streams/landing_date=2024-06-25/streams1.csv",
            "streams/landing_date=2024-06-25/streams2.csv",
        ],
    }
    result = lambda_handler(event, lambda_context)
    assert result["archived_count"] == 2
    assert mock_s3.copy_object.call_count == 2
    assert mock_s3.delete_object.call_count == 2


@patch("stream_archiver.s3")
def test_archiver_skips_non_csv(mock_s3, lambda_context):
    event = {
        "execution_id": "exec-003",
        "keys": ["streams/landing_date=2024-06-25/readme.txt"],
    }
    result = lambda_handler(event, lambda_context)
    assert result["archived_count"] == 0
    mock_s3.copy_object.assert_not_called()


@patch("stream_archiver.s3")
def test_archiver_copy_error_raises(mock_s3, lambda_context):
    # Partial/total archive failures must surface as an error so Step Functions can
    # Catch them (and alert via SNS) rather than report a silent success.
    mock_s3.copy_object.side_effect = Exception("Copy failed")
    event = {
        "execution_id": "exec-004",
        "key": "streams/landing_date=2024-06-25/streams1.csv",
    }
    with pytest.raises(RuntimeError):
        lambda_handler(event, lambda_context)
    # The source object must not be deleted when the copy fails.
    mock_s3.delete_object.assert_not_called()


@patch("stream_archiver.s3")
def test_list_stream_keys(mock_s3):
    mock_s3.get_paginator.return_value.paginate.return_value = [
        {
            "Contents": [
                {"Key": "streams/landing_date=2024-06-25/streams1.csv"},
                {"Key": "streams/manifests/landing_date=2024-06-25/streams1.csv.json"},
                {"Key": "streams/landing_date=2024-06-25/readme.txt"},
            ]
        }
    ]
    keys = _list_stream_keys("test-bronze")
    assert "streams/landing_date=2024-06-25/streams1.csv" in keys
    assert (
        "streams/manifests/landing_date=2024-06-25/streams1.csv.json" not in keys
    )
