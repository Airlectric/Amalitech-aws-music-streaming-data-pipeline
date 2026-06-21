"""Unit tests for gold_etl.py pure transform functions.

Requires Java 11+ and pyspark; skipped automatically when either is absent.
Run only Spark tests:  pytest -m spark
Skip Spark tests:      pytest -m "not spark"
"""

import pytest
from datetime import date

pytest.importorskip("pyspark", reason="PySpark not installed — skipping Spark tests")

from pyspark.sql import Row
from pyspark.sql.types import (
    DateType,
    DoubleType,
    IntegerType,
    StringType,
    StructField,
    StructType,
)

from gold_etl import compute_genre_kpis, compute_top_genres, compute_top_songs

pytestmark = pytest.mark.spark

# ---------------------------------------------------------------------------
# Minimal silver schema — only the columns the gold functions use
# ---------------------------------------------------------------------------

_SILVER_SCHEMA = StructType(
    [
        StructField("user_id", IntegerType(), True),
        StructField("track_id", StringType(), True),
        StructField("track_name", StringType(), True),
        StructField("genre", StringType(), True),
        StructField("event_date", DateType(), True),
        StructField("listen_seconds", DoubleType(), True),
    ]
)


def _silver(spark, rows):
    return spark.createDataFrame(rows, schema=_SILVER_SCHEMA)


def _d(date_str):
    """Parse 'YYYY-MM-DD' into a date object for Row values."""
    y, m, d = date_str.split("-")
    return date(int(y), int(m), int(d))


# ---------------------------------------------------------------------------
# compute_genre_kpis
# ---------------------------------------------------------------------------


def test_genre_kpis_listen_count_and_unique_listeners(spark):
    df = _silver(
        spark,
        [
            Row(user_id=1, track_id="T1", track_name="S1", genre="pop", event_date=_d("2024-06-01"), listen_seconds=180.0),
            Row(user_id=2, track_id="T2", track_name="S2", genre="pop", event_date=_d("2024-06-01"), listen_seconds=120.0),
            Row(user_id=1, track_id="T2", track_name="S2", genre="pop", event_date=_d("2024-06-01"), listen_seconds=120.0),
        ],
    )
    result = compute_genre_kpis(df)
    row = result.filter(result.genre == "pop").first()
    assert row["listen_count"] == 3
    assert row["unique_listeners"] == 2


def test_genre_kpis_total_and_avg_listen_seconds(spark):
    df = _silver(
        spark,
        [
            Row(user_id=1, track_id="T1", track_name="S1", genre="jazz", event_date=_d("2024-06-01"), listen_seconds=60.0),
            Row(user_id=2, track_id="T2", track_name="S2", genre="jazz", event_date=_d("2024-06-01"), listen_seconds=120.0),
        ],
    )
    result = compute_genre_kpis(df)
    row = result.filter(result.genre == "jazz").first()
    assert row["total_listen_seconds"] == pytest.approx(180.0)
    assert row["avg_listen_seconds_per_user"] == pytest.approx(90.0)


def test_genre_kpis_date_column_is_string_yyyy_mm_dd(spark):
    df = _silver(
        spark,
        [Row(user_id=1, track_id="T1", track_name="S1", genre="pop", event_date=_d("2024-06-15"), listen_seconds=60.0)],
    )
    result = compute_genre_kpis(df)
    row = result.first()
    assert row["date"] == "2024-06-15"
    assert "event_date" not in result.columns


def test_genre_kpis_multiple_dates_and_genres_are_independent(spark):
    df = _silver(
        spark,
        [
            Row(user_id=1, track_id="T1", track_name="S1", genre="rock", event_date=_d("2024-06-01"), listen_seconds=90.0),
            Row(user_id=1, track_id="T2", track_name="S2", genre="rock", event_date=_d("2024-06-02"), listen_seconds=90.0),
            Row(user_id=2, track_id="T3", track_name="S3", genre="pop", event_date=_d("2024-06-01"), listen_seconds=60.0),
        ],
    )
    result = compute_genre_kpis(df)
    assert result.count() == 3


# ---------------------------------------------------------------------------
# compute_top_songs
# ---------------------------------------------------------------------------


def test_top_songs_ranks_by_play_count_descending(spark):
    df = _silver(
        spark,
        [
            Row(user_id=1, track_id="T1", track_name="Hit", genre="pop", event_date=_d("2024-06-01"), listen_seconds=60.0),
            Row(user_id=2, track_id="T1", track_name="Hit", genre="pop", event_date=_d("2024-06-01"), listen_seconds=60.0),
            Row(user_id=3, track_id="T1", track_name="Hit", genre="pop", event_date=_d("2024-06-01"), listen_seconds=60.0),
            Row(user_id=1, track_id="T2", track_name="Mid", genre="pop", event_date=_d("2024-06-01"), listen_seconds=60.0),
            Row(user_id=2, track_id="T2", track_name="Mid", genre="pop", event_date=_d("2024-06-01"), listen_seconds=60.0),
        ],
    )
    result = compute_top_songs(df, n=3)
    ranks = {row["track_id"]: row["rank"] for row in result.collect()}
    assert ranks["T1"] == 1
    assert ranks["T2"] == 2


def test_top_songs_tiebreak_by_track_id_ascending(spark):
    df = _silver(
        spark,
        [
            Row(user_id=1, track_id="T3", track_name="C", genre="pop", event_date=_d("2024-06-01"), listen_seconds=60.0),
            Row(user_id=1, track_id="T1", track_name="A", genre="pop", event_date=_d("2024-06-01"), listen_seconds=60.0),
            Row(user_id=1, track_id="T2", track_name="B", genre="pop", event_date=_d("2024-06-01"), listen_seconds=60.0),
        ],
    )
    result = compute_top_songs(df, n=3)
    rows = {r["track_id"]: r["rank"] for r in result.collect()}
    assert rows["T1"] == 1
    assert rows["T2"] == 2
    assert rows["T3"] == 3


def test_top_songs_limits_to_n_per_genre_and_date(spark):
    rows = [
        Row(user_id=i, track_id=f"T{i}", track_name=f"Song{i}", genre="pop", event_date=_d("2024-06-01"), listen_seconds=60.0)
        for i in range(1, 6)
    ]
    df = _silver(spark, rows)
    result = compute_top_songs(df, n=3)
    assert result.filter(result.genre == "pop").count() == 3
    assert all(r["rank"] <= 3 for r in result.collect())


def test_top_songs_genre_date_composite_key_format(spark):
    df = _silver(
        spark,
        [Row(user_id=1, track_id="T1", track_name="S1", genre="jazz", event_date=_d("2024-06-15"), listen_seconds=60.0)],
    )
    result = compute_top_songs(df, n=3)
    row = result.first()
    assert row["genre_date"] == "jazz#2024-06-15"
    assert "event_date" not in result.columns


def test_top_songs_separate_rankings_per_genre(spark):
    df = _silver(
        spark,
        [
            Row(user_id=1, track_id="T1", track_name="A", genre="pop", event_date=_d("2024-06-01"), listen_seconds=60.0),
            Row(user_id=1, track_id="T2", track_name="B", genre="rock", event_date=_d("2024-06-01"), listen_seconds=60.0),
        ],
    )
    result = compute_top_songs(df, n=3)
    for row in result.collect():
        assert row["rank"] == 1


# ---------------------------------------------------------------------------
# compute_top_genres
# ---------------------------------------------------------------------------


def test_top_genres_ranks_by_listen_count_descending(spark):
    df = _silver(
        spark,
        [
            Row(user_id=1, track_id="T1", track_name="S1", genre="pop", event_date=_d("2024-06-01"), listen_seconds=60.0),
            Row(user_id=2, track_id="T1", track_name="S1", genre="pop", event_date=_d("2024-06-01"), listen_seconds=60.0),
            Row(user_id=1, track_id="T2", track_name="S2", genre="jazz", event_date=_d("2024-06-01"), listen_seconds=60.0),
        ],
    )
    result = compute_top_genres(df, n=5)
    ranks = {r["genre"]: r["rank"] for r in result.collect()}
    assert ranks["pop"] == 1
    assert ranks["jazz"] == 2


def test_top_genres_tiebreak_by_genre_name_ascending(spark):
    df = _silver(
        spark,
        [
            Row(user_id=1, track_id="T1", track_name="S1", genre="rock", event_date=_d("2024-06-01"), listen_seconds=60.0),
            Row(user_id=2, track_id="T2", track_name="S2", genre="jazz", event_date=_d("2024-06-01"), listen_seconds=60.0),
        ],
    )
    result = compute_top_genres(df, n=5)
    ranks = {r["genre"]: r["rank"] for r in result.collect()}
    assert ranks["jazz"] == 1  # "jazz" < "rock" alphabetically
    assert ranks["rock"] == 2


def test_top_genres_limits_to_n(spark):
    genres = [f"genre_{i:02d}" for i in range(8)]
    rows = [
        Row(user_id=1, track_id=f"T{i}", track_name=f"S{i}", genre=genres[i], event_date=_d("2024-06-01"), listen_seconds=60.0)
        for i in range(8)
    ]
    df = _silver(spark, rows)
    result = compute_top_genres(df, n=5)
    assert result.count() == 5
    assert all(r["rank"] <= 5 for r in result.collect())


def test_top_genres_date_column_and_no_event_date(spark):
    df = _silver(
        spark,
        [Row(user_id=1, track_id="T1", track_name="S1", genre="pop", event_date=_d("2024-07-04"), listen_seconds=60.0)],
    )
    result = compute_top_genres(df, n=5)
    row = result.first()
    assert row["date"] == "2024-07-04"
    assert "event_date" not in result.columns
