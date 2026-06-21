import io
import math
import sys
from decimal import Decimal

import boto3
import pyarrow.parquet as pq

_CW_NAMESPACE = "MusicPipeline/DQ"


def parse_s3_path(path):
    bucket, key = path.replace("s3://", "", 1).split("/", 1)
    return bucket, key.rstrip("/")


def extract_partition_values(key):
    partition_values = {}
    for segment in key.split("/"):
        if "=" not in segment:
            continue
        partition_key, partition_value = segment.split("=", 1)
        if partition_key and partition_value:
            partition_values[partition_key] = partition_value
    return partition_values


def read_partition_rows(s3_client, base_path):
    """Read all Parquet files under base_path, merging Hive partition values into each row.

    Raises RuntimeError if any Parquet file cannot be parsed (poison-partition guard).
    """
    bucket, prefix = parse_s3_path(base_path)
    rows = []
    bad_keys = []
    paginator = s3_client.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            if not obj["Key"].endswith(".parquet"):
                continue
            body = s3_client.get_object(Bucket=bucket, Key=obj["Key"])["Body"].read()
            try:
                table = pq.read_table(io.BytesIO(body))
            except Exception as exc:
                print(f"[ERROR] Failed to parse Parquet at {obj['Key']}: {exc}")
                bad_keys.append(obj["Key"])
                continue
            partition_values = extract_partition_values(obj["Key"])
            for row in table.to_pylist():
                merged_row = dict(partition_values)
                merged_row.update(row)
                rows.append(merged_row)

    if bad_keys:
        raise RuntimeError(
            f"Poison-partition guard: failed to parse {len(bad_keys)} Parquet file(s): "
            f"{bad_keys}. Fix or remove the corrupted files and re-run."
        )
    return rows


def to_decimal(value, default="0"):
    if value is None:
        return Decimal(default)
    if isinstance(value, float) and not math.isfinite(value):
        return Decimal(default)

    text = str(value).strip()
    if text.lower() in {"", "nan", "inf", "-inf", "none", "null"}:
        return Decimal(default)
    return Decimal(text)


def _emit_load_metrics(cw_client, run_date, counts):
    """Emit per-table row-count metrics to CloudWatch (MusicPipeline/DQ)."""
    dims = [{"Name": "Job", "Value": "ddb_etl"}, {"Name": "RunDate", "Value": run_date}]
    metric_data = [
        {"MetricName": k, "Value": float(v), "Unit": "Count", "Dimensions": dims}
        for k, v in counts.items()
    ]
    for i in range(0, len(metric_data), 20):
        cw_client.put_metric_data(Namespace=_CW_NAMESPACE, MetricData=metric_data[i : i + 20])


def main():
    from awsglue.utils import getResolvedOptions

    args = getResolvedOptions(
        sys.argv,
        ["gold_path", "table_genre_kpis", "table_top_songs", "table_top_genres", "run_date"],
    )
    gold_path = args["gold_path"].rstrip("/")
    table_genre_kpis = args["table_genre_kpis"]
    table_top_songs = args["table_top_songs"]
    table_top_genres = args["table_top_genres"]
    run_date = args["run_date"]

    s3_client = boto3.client("s3")
    ddb = boto3.resource("dynamodb")
    cw = boto3.client("cloudwatch")

    # --- Read Gold partitions (poison-partition guard active inside read_partition_rows) ---
    genre_kpis_rows = read_partition_rows(s3_client, f"{gold_path}/genre_kpis_daily/date={run_date}")
    top_songs_rows = read_partition_rows(s3_client, f"{gold_path}/top_songs_by_genre_daily/date={run_date}")
    top_genres_rows = read_partition_rows(s3_client, f"{gold_path}/top_genres_daily/date={run_date}")

    # --- Write genre KPIs and reconcile ---
    genre_kpis_written = 0
    genre_kpis_table = ddb.Table(table_genre_kpis)
    with genre_kpis_table.batch_writer() as batch:
        for row in genre_kpis_rows:
            batch.put_item(
                Item={
                    "genre": row["genre"],
                    "date": row["date"],
                    "listen_count": int(row["listen_count"]),
                    "unique_listeners": int(row["unique_listeners"]),
                    "total_listen_seconds": to_decimal(row["total_listen_seconds"]),
                    "avg_listen_seconds_per_user": to_decimal(row["avg_listen_seconds_per_user"]),
                }
            )
            genre_kpis_written += 1
    if genre_kpis_written != len(genre_kpis_rows):
        raise RuntimeError(
            f"Reconciliation failed for {table_genre_kpis}: "
            f"read {len(genre_kpis_rows)} rows but submitted {genre_kpis_written} put_item calls."
        )

    # --- Write top songs and reconcile ---
    top_songs_written = 0
    top_songs_table = ddb.Table(table_top_songs)
    with top_songs_table.batch_writer() as batch:
        for row in top_songs_rows:
            batch.put_item(
                Item={
                    "genre_date": row["genre_date"],
                    "rank": int(row["rank"]),
                    "track_id": row["track_id"],
                    "track_name": row["track_name"],
                    "play_count": int(row["play_count"]),
                }
            )
            top_songs_written += 1
    if top_songs_written != len(top_songs_rows):
        raise RuntimeError(
            f"Reconciliation failed for {table_top_songs}: "
            f"read {len(top_songs_rows)} rows but submitted {top_songs_written} put_item calls."
        )

    # --- Write top genres and reconcile ---
    top_genres_written = 0
    top_genres_table = ddb.Table(table_top_genres)
    with top_genres_table.batch_writer() as batch:
        for row in top_genres_rows:
            batch.put_item(
                Item={
                    "date": row["date"],
                    "rank": int(row["rank"]),
                    "genre": row["genre"],
                    "listen_count": int(row["listen_count"]),
                }
            )
            top_genres_written += 1
    if top_genres_written != len(top_genres_rows):
        raise RuntimeError(
            f"Reconciliation failed for {table_top_genres}: "
            f"read {len(top_genres_rows)} rows but submitted {top_genres_written} put_item calls."
        )

    # --- Emit load metrics and structured summary ---
    counts = {
        "GenreKpisLoaded": genre_kpis_written,
        "TopSongsLoaded": top_songs_written,
        "TopGenresLoaded": top_genres_written,
    }
    _emit_load_metrics(cw, run_date, counts)
    print(
        f"[DDB-LOAD] run_date={run_date} "
        f"genre_kpis={genre_kpis_written} "
        f"top_songs={top_songs_written} "
        f"top_genres={top_genres_written}"
    )


if __name__ == "__main__":
    main()
