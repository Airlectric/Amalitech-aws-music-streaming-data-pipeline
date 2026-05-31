import io
import math
import sys
from decimal import Decimal

import boto3
import pyarrow.parquet as pq
from awsglue.utils import getResolvedOptions

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
    bucket, prefix = parse_s3_path(base_path)
    rows = []
    paginator = s3_client.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            if not obj["Key"].endswith(".parquet"):
                continue
            body = s3_client.get_object(Bucket=bucket, Key=obj["Key"])["Body"].read()
            table = pq.read_table(io.BytesIO(body))
            partition_values = extract_partition_values(obj["Key"])
            for row in table.to_pylist():
                merged_row = dict(partition_values)
                merged_row.update(row)
                rows.append(merged_row)
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


def main():
    args = getResolvedOptions(
        sys.argv,
        [
            "gold_path",
            "table_genre_kpis",
            "table_top_songs",
            "table_top_genres",
            "run_date",
        ],
    )

    gold_path = args["gold_path"].rstrip("/")
    table_genre_kpis = args["table_genre_kpis"]
    table_top_songs = args["table_top_songs"]
    table_top_genres = args["table_top_genres"]
    run_date = args["run_date"]

    s3_client = boto3.client("s3")
    ddb = boto3.resource("dynamodb")

    genre_kpis_rows = read_partition_rows(
        s3_client, f"{gold_path}/genre_kpis_daily/date={run_date}"
    )
    top_songs_rows = read_partition_rows(
        s3_client, f"{gold_path}/top_songs_by_genre_daily/date={run_date}"
    )
    top_genres_rows = read_partition_rows(
        s3_client, f"{gold_path}/top_genres_daily/date={run_date}"
    )

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
                    "avg_listen_seconds_per_user": to_decimal(
                        row["avg_listen_seconds_per_user"]
                    ),
                }
            )

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

    print(
        f"Loaded {len(genre_kpis_rows)} genre KPI rows, "
        f"{len(top_songs_rows)} top song rows, "
        f"and {len(top_genres_rows)} top genre rows for {run_date}"
    )


if __name__ == "__main__":
    main()
