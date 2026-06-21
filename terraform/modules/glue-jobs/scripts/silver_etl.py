import re
import sys

import boto3
from pyspark.sql import SparkSession, functions as F
from pyspark.sql.types import IntegerType, LongType, StringType, StructField, StructType

STREAMS_SCHEMA = StructType(
    [
        StructField("user_id", IntegerType(), False),
        StructField("track_id", StringType(), False),
        StructField("listen_time", StringType(), False),
    ]
)

SONGS_SCHEMA = StructType(
    [
        StructField("id", IntegerType(), True),
        StructField("track_id", StringType(), False),
        StructField("artists", StringType(), True),
        StructField("album_name", StringType(), True),
        StructField("track_name", StringType(), True),
        StructField("popularity", IntegerType(), True),
        StructField("duration_ms", LongType(), True),
        StructField("explicit", StringType(), True),
        StructField("danceability", StringType(), True),
        StructField("energy", StringType(), True),
        StructField("key", StringType(), True),
        StructField("loudness", StringType(), True),
        StructField("mode", StringType(), True),
        StructField("speechiness", StringType(), True),
        StructField("acousticness", StringType(), True),
        StructField("instrumentalness", StringType(), True),
        StructField("liveness", StringType(), True),
        StructField("valence", StringType(), True),
        StructField("tempo", StringType(), True),
        StructField("time_signature", StringType(), True),
        StructField("track_genre", StringType(), True),
    ]
)

USERS_SCHEMA = StructType(
    [
        StructField("user_id", IntegerType(), False),
        StructField("user_name", StringType(), True),
        StructField("user_age", IntegerType(), True),
        StructField("user_country", StringType(), True),
        StructField("created_at", StringType(), True),
    ]
)

_CW_NAMESPACE = "MusicPipeline/DQ"


# ---------------------------------------------------------------------------
# Pure transform functions — importable and testable without the Glue runtime
# ---------------------------------------------------------------------------


def clean_streams(df):
    """Drop rows missing required fields, dedup, and parse listen_ts."""
    return (
        df.dropna(subset=["user_id", "track_id", "listen_time"])
        .dropDuplicates(["user_id", "track_id", "listen_time"])
        .withColumn("listen_ts", F.to_timestamp("listen_time", "yyyy-MM-dd HH:mm:ss"))
        .dropna(subset=["listen_ts"])
    )


def select_songs(df):
    """Narrow songs DataFrame to the columns used downstream."""
    return df.select(
        "track_id",
        "artists",
        "album_name",
        "track_name",
        "duration_ms",
        "track_genre",
    )


def select_users(df):
    """Narrow users DataFrame to the columns used downstream."""
    return df.select("user_id", "user_country")


def build_curated(streams_df, songs_df, users_df, source_file):
    """Join streams with songs and users; derive genre, listen_seconds, event_date."""
    return (
        streams_df.join(songs_df, on="track_id", how="inner")
        .join(users_df, on="user_id", how="left")
        .withColumn("event_date", F.to_date("listen_ts"))
        .withColumn("genre", F.lower(F.trim(F.col("track_genre"))))
        .withColumn("listen_seconds", F.col("duration_ms") / F.lit(1000.0))
        .withColumn("source_file", F.lit(source_file))
        .select(
            "user_id",
            "track_id",
            "track_name",
            "artists",
            "album_name",
            "genre",
            "listen_time",
            "listen_ts",
            "event_date",
            "duration_ms",
            "listen_seconds",
            "user_country",
            "source_file",
        )
    )


# ---------------------------------------------------------------------------
# Helpers used only by main() — not part of the public testable API
# ---------------------------------------------------------------------------


def _get_arg_default(key, default):
    """Return an optional Glue job arg value, falling back to default if absent."""
    for i, token in enumerate(sys.argv):
        if token == f"--{key}" and i + 1 < len(sys.argv):
            return sys.argv[i + 1]
    return default


def _extract_run_date(stream_key):
    """Extract YYYY-MM-DD from a Hive-partitioned S3 key (landing_date=...)."""
    m = re.search(r"landing_date=(\d{4}-\d{2}-\d{2})", stream_key)
    return m.group(1) if m else "unknown"


def _emit_dq_metrics(cw_client, run_date, counts, drop_rate_pct):
    """Push DQ gate counts and drop rate to CloudWatch (MusicPipeline/DQ).

    Per-gate counts carry both Job and RunDate dimensions for trend queries.
    DropRatePct uses only the Job dimension so a stable CloudWatch alarm can
    target it without a new dimension value appearing for every run date.
    """
    full_dims = [{"Name": "Job", "Value": "silver_etl"}, {"Name": "RunDate", "Value": run_date}]
    job_dim = [{"Name": "Job", "Value": "silver_etl"}]
    metric_data = [
        *[{"MetricName": k, "Value": float(v), "Unit": "Count", "Dimensions": full_dims} for k, v in counts.items()],
        {"MetricName": "DropRatePct", "Value": drop_rate_pct, "Unit": "Percent", "Dimensions": job_dim},
    ]
    for i in range(0, len(metric_data), 20):
        cw_client.put_metric_data(Namespace=_CW_NAMESPACE, MetricData=metric_data[i : i + 20])


# ---------------------------------------------------------------------------
# Glue entry point
# ---------------------------------------------------------------------------


def main():
    from awsglue.utils import getResolvedOptions

    args = getResolvedOptions(sys.argv, ["bronze_bucket", "stream_key", "silver_path"])
    bronze_bucket = args["bronze_bucket"]
    stream_key = args["stream_key"]
    silver_path = args["silver_path"].rstrip("/")
    max_drop_rate = float(_get_arg_default("max_drop_rate", "0.10"))
    run_date = _extract_run_date(stream_key)

    stream_path = f"s3://{bronze_bucket}/{stream_key}"
    songs_path = f"s3://{bronze_bucket}/reference/songs/"
    users_path = f"s3://{bronze_bucket}/reference/users/"

    spark = SparkSession.builder.appName("SilverETL").getOrCreate()
    spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")
    cw = boto3.client("cloudwatch")

    # --- Reference-data guard: fail before any join if reference data is absent ---
    raw_songs = spark.read.option("header", "true").schema(SONGS_SCHEMA).csv(songs_path)
    raw_users = spark.read.option("header", "true").schema(USERS_SCHEMA).csv(users_path)
    if not raw_songs.head(1):
        raise ValueError(f"Reference data songs is empty or missing at {songs_path}")
    if not raw_users.head(1):
        raise ValueError(f"Reference data users is empty or missing at {users_path}")
    songs_df = select_songs(raw_songs)
    users_df = select_users(raw_users)

    # --- DQ accounting: count rows surviving each cleansing gate ---
    raw_df = spark.read.option("header", "true").schema(STREAMS_SCHEMA).csv(stream_path)
    raw_df.cache()
    raw_count = raw_df.count()

    after_dropna = raw_df.dropna(subset=["user_id", "track_id", "listen_time"])
    after_dropna.cache()
    after_dropna_count = after_dropna.count()
    raw_df.unpersist()

    after_dedup = after_dropna.dropDuplicates(["user_id", "track_id", "listen_time"])
    after_dedup.cache()
    after_dedup_count = after_dedup.count()
    after_dropna.unpersist()

    after_ts = (
        after_dedup.withColumn("listen_ts", F.to_timestamp("listen_time", "yyyy-MM-dd HH:mm:ss")).dropna(subset=["listen_ts"])
    )
    after_ts.cache()
    after_ts_count = after_ts.count()
    after_dedup.unpersist()

    # Inner join to songs — unmatched tracks are intentionally dropped
    joined_songs = after_ts.join(songs_df, on="track_id", how="inner")
    joined_songs.cache()
    after_join_count = joined_songs.count()
    after_ts.unpersist()
    unmatched_songs_count = after_ts_count - after_join_count

    # --- Emit DQ metrics and check drop-rate circuit breaker ---
    drop_rate = (raw_count - after_join_count) / raw_count if raw_count > 0 else 0.0
    drop_rate_pct = drop_rate * 100.0
    counts = {
        "RawCount": raw_count,
        "AfterDropNaCount": after_dropna_count,
        "AfterDedupCount": after_dedup_count,
        "AfterTimestampParseCount": after_ts_count,
        "AfterSongsJoinCount": after_join_count,
        "UnmatchedSongsCount": unmatched_songs_count,
    }
    _emit_dq_metrics(cw, run_date, counts, drop_rate_pct)
    print(
        f"[DQ] run_date={run_date} raw={raw_count} after_dropna={after_dropna_count} "
        f"after_dedup={after_dedup_count} after_ts_parse={after_ts_count} "
        f"after_songs_join={after_join_count} unmatched_songs={unmatched_songs_count} "
        f"drop_rate={drop_rate:.1%}"
    )

    if raw_count > 0 and drop_rate > max_drop_rate:
        raise ValueError(
            f"Drop rate {drop_rate:.1%} exceeds threshold {max_drop_rate:.1%} "
            f"(raw={raw_count}, final={after_join_count}). "
            "Check reference data coverage and upstream data quality."
        )

    # --- Build final curated DataFrame (left join to users) ---
    curated_df = (
        joined_songs.join(users_df, on="user_id", how="left")
        .withColumn("event_date", F.to_date("listen_ts"))
        .withColumn("genre", F.lower(F.trim(F.col("track_genre"))))
        .withColumn("listen_seconds", F.col("duration_ms") / F.lit(1000.0))
        .withColumn("source_file", F.lit(stream_path))
        .select(
            "user_id",
            "track_id",
            "track_name",
            "artists",
            "album_name",
            "genre",
            "listen_time",
            "listen_ts",
            "event_date",
            "duration_ms",
            "listen_seconds",
            "user_country",
            "source_file",
        )
    )

    curated_df.write.mode("overwrite").partitionBy("event_date").parquet(f"{silver_path}/streams_curated")
    spark.stop()


if __name__ == "__main__":
    main()
