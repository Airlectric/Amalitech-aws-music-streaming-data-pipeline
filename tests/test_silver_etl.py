"""Unit tests for silver_etl.py pure transform functions.

Requires Java 11+ and pyspark; skipped automatically when either is absent.
Run only Spark tests:  pytest -m spark
Skip Spark tests:      pytest -m "not spark"
"""

import pytest

pytest.importorskip("pyspark", reason="PySpark not installed — skipping Spark tests")

from pyspark.sql import Row
from pyspark.sql.types import IntegerType, LongType, StringType, StructField, StructType

from silver_etl import (
    STREAMS_SCHEMA,
    build_curated,
    clean_streams,
    select_songs,
    select_users,
    _extract_run_date,
)

pytestmark = pytest.mark.spark

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_SONGS_SCHEMA = StructType(
    [
        StructField("track_id", StringType(), False),
        StructField("artists", StringType(), True),
        StructField("album_name", StringType(), True),
        StructField("track_name", StringType(), True),
        StructField("duration_ms", LongType(), True),
        StructField("track_genre", StringType(), True),
    ]
)

_USERS_SCHEMA = StructType(
    [
        StructField("user_id", IntegerType(), False),
        StructField("user_country", StringType(), True),
    ]
)


def _streams(spark, rows):
    return spark.createDataFrame(rows, schema=STREAMS_SCHEMA)


def _songs(spark, rows):
    return spark.createDataFrame(rows, schema=_SONGS_SCHEMA)


def _users(spark, rows):
    return spark.createDataFrame(rows, schema=_USERS_SCHEMA)


# ---------------------------------------------------------------------------
# _extract_run_date
# ---------------------------------------------------------------------------


def test_extract_run_date_from_hive_path():
    assert _extract_run_date("streams/landing_date=2024-06-15/streams.csv") == "2024-06-15"


def test_extract_run_date_unknown_when_absent():
    assert _extract_run_date("streams/no-partition/file.csv") == "unknown"


# ---------------------------------------------------------------------------
# clean_streams
# ---------------------------------------------------------------------------


def test_clean_streams_drops_null_required_fields(spark):
    df = _streams(
        spark,
        [
            Row(user_id=1, track_id="T1", listen_time="2024-06-01 10:00:00"),  # valid
            Row(user_id=None, track_id="T2", listen_time="2024-06-01 11:00:00"),  # null user_id
            Row(user_id=2, track_id=None, listen_time="2024-06-01 12:00:00"),  # null track_id
            Row(user_id=3, track_id="T3", listen_time=None),  # null listen_time
        ],
    )
    result = clean_streams(df)
    assert result.count() == 1
    assert result.first()["user_id"] == 1


def test_clean_streams_deduplicates_on_key_triplet(spark):
    df = _streams(
        spark,
        [
            Row(user_id=1, track_id="T1", listen_time="2024-06-01 10:00:00"),
            Row(user_id=1, track_id="T1", listen_time="2024-06-01 10:00:00"),  # exact duplicate
            Row(user_id=1, track_id="T1", listen_time="2024-06-01 11:00:00"),  # different time
        ],
    )
    result = clean_streams(df)
    assert result.count() == 2


def test_clean_streams_drops_unparseable_timestamps(spark):
    df = _streams(
        spark,
        [
            Row(user_id=1, track_id="T1", listen_time="2024-06-01 10:00:00"),  # valid
            Row(user_id=2, track_id="T2", listen_time="not-a-date"),  # bad timestamp
            Row(user_id=3, track_id="T3", listen_time="2024/06/01"),  # wrong format
        ],
    )
    result = clean_streams(df)
    assert result.count() == 1
    assert result.first()["user_id"] == 1


def test_clean_streams_adds_listen_ts_column(spark):
    df = _streams(
        spark,
        [Row(user_id=1, track_id="T1", listen_time="2024-06-01 10:30:00")],
    )
    result = clean_streams(df)
    assert "listen_ts" in result.columns
    row = result.first()
    assert str(row["listen_ts"]) == "2024-06-01 10:30:00"


# ---------------------------------------------------------------------------
# build_curated
# ---------------------------------------------------------------------------


def test_build_curated_inner_join_drops_unmatched_tracks(spark):
    streams = clean_streams(
        _streams(
            spark,
            [
                Row(user_id=1, track_id="T1", listen_time="2024-06-01 10:00:00"),
                Row(user_id=2, track_id="T_MISSING", listen_time="2024-06-01 11:00:00"),
            ],
        )
    )
    songs = _songs(spark, [Row(track_id="T1", artists="A", album_name="Al", track_name="Song1", duration_ms=180000, track_genre="Pop")])
    users = _users(spark, [Row(user_id=1, user_country="GH"), Row(user_id=2, user_country="US")])

    result = build_curated(streams, select_songs(songs), select_users(users), "s3://bucket/key")
    assert result.count() == 1
    assert result.first()["track_id"] == "T1"


def test_build_curated_left_join_keeps_stream_with_missing_user(spark):
    streams = clean_streams(
        _streams(
            spark,
            [Row(user_id=99, track_id="T1", listen_time="2024-06-01 10:00:00")],
        )
    )
    songs = _songs(spark, [Row(track_id="T1", artists="A", album_name="Al", track_name="Song1", duration_ms=120000, track_genre="Jazz")])
    users = _users(spark, [])  # no matching user

    result = build_curated(streams, select_songs(songs), select_users(users), "s3://bucket/key")
    assert result.count() == 1
    assert result.first()["user_country"] is None


def test_build_curated_genre_is_lowercased_and_trimmed(spark):
    streams = clean_streams(
        _streams(
            spark,
            [Row(user_id=1, track_id="T1", listen_time="2024-06-01 10:00:00")],
        )
    )
    songs = _songs(spark, [Row(track_id="T1", artists="A", album_name="Al", track_name="S", duration_ms=60000, track_genre="  Hip Hop  ")])
    users = _users(spark, [Row(user_id=1, user_country="GH")])

    result = build_curated(streams, select_songs(songs), select_users(users), "s3://bucket/key")
    assert result.first()["genre"] == "hip hop"


def test_build_curated_listen_seconds_is_duration_ms_divided_by_1000(spark):
    streams = clean_streams(
        _streams(
            spark,
            [Row(user_id=1, track_id="T1", listen_time="2024-06-01 10:00:00")],
        )
    )
    songs = _songs(spark, [Row(track_id="T1", artists="A", album_name="Al", track_name="S", duration_ms=240000, track_genre="Pop")])
    users = _users(spark, [Row(user_id=1, user_country="GH")])

    result = build_curated(streams, select_songs(songs), select_users(users), "s3://bucket/key")
    assert result.first()["listen_seconds"] == pytest.approx(240.0)


def test_build_curated_derives_event_date(spark):
    streams = clean_streams(
        _streams(
            spark,
            [Row(user_id=1, track_id="T1", listen_time="2024-06-15 08:45:00")],
        )
    )
    songs = _songs(spark, [Row(track_id="T1", artists="A", album_name="Al", track_name="S", duration_ms=60000, track_genre="Pop")])
    users = _users(spark, [Row(user_id=1, user_country="GH")])

    result = build_curated(streams, select_songs(songs), select_users(users), "s3://bucket/key")
    from datetime import date

    assert result.first()["event_date"] == date(2024, 6, 15)


# ---------------------------------------------------------------------------
# Drop-rate helper (module-level, importable without Spark)
# ---------------------------------------------------------------------------


def test_extract_run_date_various_key_formats():
    cases = [
        ("streams/landing_date=2024-01-01/batch.csv", "2024-01-01"),
        ("s3://bucket/streams/landing_date=2025-12-31/f.csv", "2025-12-31"),
        ("no_partition", "unknown"),
    ]
    for key, expected in cases:
        assert _extract_run_date(key) == expected
