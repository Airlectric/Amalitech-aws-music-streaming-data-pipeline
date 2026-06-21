import io
import os
import sys
import types
from decimal import Decimal
from unittest.mock import MagicMock, patch

import pytest


GLUE_SCRIPTS_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..",
    "terraform/modules/glue-jobs/scripts",
)
sys.path.insert(0, os.path.abspath(GLUE_SCRIPTS_DIR))

awsglue = types.ModuleType("awsglue")
awsglue_utils = types.ModuleType("awsglue.utils")
awsglue_utils.getResolvedOptions = lambda argv, options: {}
awsglue.utils = awsglue_utils
sys.modules.setdefault("awsglue", awsglue)
sys.modules.setdefault("awsglue.utils", awsglue_utils)

from ddb_etl import extract_partition_values, read_partition_rows, to_decimal


def test_extract_partition_values():
    key = "top_genres_daily/date=2024-06-25/part-0000.parquet"
    assert extract_partition_values(key) == {"date": "2024-06-25"}


def test_to_decimal_coerces_missing_and_non_finite_values():
    assert to_decimal(None) == Decimal("0")
    assert to_decimal("nan") == Decimal("0")
    assert to_decimal(float("inf")) == Decimal("0")
    assert to_decimal("12.5") == Decimal("12.5")


@patch("ddb_etl.pq.read_table")
def test_read_partition_rows_merges_partition_values(mock_read_table):
    mock_s3 = MagicMock()
    mock_s3.get_paginator.return_value.paginate.return_value = [
        {"Contents": [{"Key": "gold/genre_kpis_daily/date=2024-06-25/part-0000.parquet"}]}
    ]
    mock_s3.get_object.return_value = {"Body": io.BytesIO(b"parquet-bytes")}
    mock_read_table.return_value.to_pylist.return_value = [
        {"genre": "Pop", "listen_count": 3, "unique_listeners": 2}
    ]

    rows = read_partition_rows(mock_s3, "s3://bucket/gold/genre_kpis_daily/date=2024-06-25")

    assert rows == [
        {
            "date": "2024-06-25",
            "genre": "Pop",
            "listen_count": 3,
            "unique_listeners": 2,
        }
    ]


@patch("ddb_etl.pq.read_table")
def test_read_partition_rows_poison_partition_raises_runtime_error(mock_read_table):
    """Verify that a corrupted Parquet file triggers RuntimeError naming the bad key."""
    mock_s3 = MagicMock()
    mock_s3.get_paginator.return_value.paginate.return_value = [
        {
            "Contents": [
                {"Key": "gold/date=2024-06-25/part-0000.parquet"},
                {"Key": "gold/date=2024-06-25/part-0001.parquet"},
            ]
        }
    ]
    mock_s3.get_object.return_value = {"Body": io.BytesIO(b"bytes")}

    good_table = MagicMock()
    good_table.to_pylist.return_value = [{"genre": "Pop"}]
    mock_read_table.side_effect = [good_table, ValueError("not a parquet file")]

    with pytest.raises(RuntimeError) as exc_info:
        read_partition_rows(mock_s3, "s3://bucket/gold/date=2024-06-25")

    assert "gold/date=2024-06-25/part-0001.parquet" in str(exc_info.value)
    assert "1 Parquet file" in str(exc_info.value)


@patch("ddb_etl.pq.read_table")
def test_read_partition_rows_multiple_bad_keys_all_listed(mock_read_table):
    """RuntimeError lists every bad key when multiple partitions are corrupted."""
    mock_s3 = MagicMock()
    mock_s3.get_paginator.return_value.paginate.return_value = [
        {
            "Contents": [
                {"Key": "gold/date=2024-06-25/part-0000.parquet"},
                {"Key": "gold/date=2024-06-25/part-0001.parquet"},
            ]
        }
    ]
    mock_s3.get_object.return_value = {"Body": io.BytesIO(b"bytes")}
    mock_read_table.side_effect = [
        OSError("corrupt"),
        OSError("corrupt"),
    ]

    with pytest.raises(RuntimeError) as exc_info:
        read_partition_rows(mock_s3, "s3://bucket/gold/date=2024-06-25")

    error_msg = str(exc_info.value)
    assert "gold/date=2024-06-25/part-0000.parquet" in error_msg
    assert "gold/date=2024-06-25/part-0001.parquet" in error_msg
    assert "2 Parquet file" in error_msg
