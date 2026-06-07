#!/usr/bin/env python3
"""Simulate real-world streaming data using the provided CSV files.

Uploads the reference CSV files and replays streams*.csv into router-compatible
landing-date partitions.

Usage:
  python3 scripts/produce_streams.py bronze-108782069549         # ~500 events, ~2min demo
  python3 scripts/produce_streams.py bronze-108782069549 --all   # all 34k events
  python3 scripts/produce_streams.py bronze-108782069549 --burst # dump everything now
  python3 scripts/produce_streams.py bronze-108782069549 --count 100
"""

import csv
import io
import os
import random
import time
import uuid
from datetime import datetime

import boto3
from collections import defaultdict
from datetime import datetime


BASE_DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")
STREAM_FIELDS = ["user_id", "track_id", "listen_time"]


# ---------------------------------------------------------------------------
# Data loaders
# ---------------------------------------------------------------------------
def _load_csv(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def load_streams(paths=None):
    if paths is None:
        dir_ = os.path.join(BASE_DATA_DIR, "streams")
        paths = sorted(
            os.path.join(dir_, f) for f in os.listdir(dir_) if f.endswith(".csv")
        )

    events = []
    for p in paths:
        for r in _load_csv(p):
            events.append(
                {
                    "user_id": r["user_id"].strip(),
                    "track_id": r["track_id"].strip(),
                    "listen_time": r["listen_time"].strip(),
                }
            )
    return events


# ---------------------------------------------------------------------------
# Upload
# ---------------------------------------------------------------------------
def upload_reference_data(s3_client, bucket):
    reference_files = [
        (os.path.join(BASE_DATA_DIR, "users", "users.csv"), "reference/users/users.csv"),
        (os.path.join(BASE_DATA_DIR, "songs", "songs.csv"), "reference/songs/songs.csv"),
    ]

    uploaded = []
    for local_path, key in reference_files:
        s3_client.upload_file(
            local_path,
            bucket,
            key,
            ExtraArgs={"ContentType": "text/csv"},
        )
        uploaded.append(key)
    return uploaded


def landing_date_for(event):
    listen_dt = datetime.strptime(event["listen_time"], "%Y-%m-%d %H:%M:%S")
    return listen_dt.strftime("%Y-%m-%d")


def csv_body(events):
    output = io.StringIO()
    writer = csv.DictWriter(output, fieldnames=STREAM_FIELDS)
    writer.writeheader()
    writer.writerows(events)
    return output.getvalue()


def upload_batch(s3_client, bucket, events, prefix):
    if not events:
        return []

    events_by_date = {}
    for event in events:
        events_by_date.setdefault(landing_date_for(event), []).append(event)

    keys = []
    base_prefix = prefix.rstrip("/")
    for landing_date, rows in sorted(events_by_date.items()):
        filename = f"batch_{uuid.uuid4().hex[:8]}.csv"
        key = f"{base_prefix}/landing_date={landing_date}/{filename}"
        s3_client.put_object(
            Bucket=bucket,
            Key=key,
            Body=csv_body(rows).encode("utf-8"),
            ContentType="text/csv",
        )
        keys.append(key)
    return keys


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Simulate unpredictable streaming using real CSV data"
    )
    parser.add_argument("bucket", help="Bronze S3 bucket name")
    parser.add_argument(
        "--prefix",
        default="streams",
        help="S3 stream prefix; landing_date partitions are added below it",
    )
    parser.add_argument("--profile", default=None, help="AWS profile name")
    parser.add_argument("--endpoint-url", default=None, help="S3 endpoint (localstack)")
    parser.add_argument(
        "--skip-reference-upload",
        action="store_true",
        help="Do not upload reference/users and reference/songs CSVs before stream batches",
    )

    group = parser.add_mutually_exclusive_group()
    group.add_argument("--burst", action="store_true", help="Upload all events at once")
    group.add_argument("--all", action="store_true", help="Process ALL 34k events")
    group.add_argument(
        "--count", type=int, default=None, help="Total events to process"
    )

    parser.add_argument(
        "--min-delay",
        type=float,
        default=3,
        help="Min delay between batches in seconds (default: 3)",
    )
    parser.add_argument(
        "--max-delay",
        type=float,
        default=30,
        help="Max delay between batches in seconds (default: 30)",
    )
    parser.add_argument(
        "--min-batch", type=int, default=5, help="Min events per batch (default: 5)"
    )
    parser.add_argument(
        "--max-batch", type=int, default=30, help="Max events per batch (default: 30)"
    )

    args = parser.parse_args()

    session = boto3.Session(profile_name=args.profile)
    s3 = session.client("s3", endpoint_url=args.endpoint_url)

    print("Loading data...")
    users = _load_csv(os.path.join(BASE_DATA_DIR, "users", "users.csv"))
    songs = _load_csv(os.path.join(BASE_DATA_DIR, "songs", "songs.csv"))
    streams = load_streams()
    print(f"  {len(users)} users, {len(songs)} songs, {len(streams)} stream events")

    if not args.skip_reference_upload:
        reference_keys = upload_reference_data(s3, args.bucket)
        print("Uploaded reference data:")
        for key in reference_keys:
            print(f"  -> {key}")

    total_to_process = len(streams)
    if args.count:
        total_to_process = min(args.count, total_to_process)
    elif not args.all and not args.burst:
        total_to_process = min(500, total_to_process)

    if args.burst:
        events = streams[:total_to_process]
        keys = upload_batch(s3, args.bucket, events, args.prefix)
        print(f"Burst: {len(events)} events")
        for key in keys:
            print(f"  -> {key}")
        return

    print(f"Streaming {total_to_process} events in unpredictable batches...")
    print(f"  batch size: {args.min_batch}-{args.max_batch}")
    print(f"  delay: {args.min_delay}-{args.max_delay}s")

    remaining = random.sample(streams, total_to_process)
    batch_num = 0
    pos = 0

    try:
        while pos < len(remaining):
            batch_size = random.randint(args.min_batch, args.max_batch)
            end = min(pos + batch_size, len(remaining))
            events = remaining[pos:end]

            keys = upload_batch(s3, args.bucket, events, args.prefix)
            batch_num += 1
            pct = end / len(remaining) * 100
            print(
                f"  [{batch_num}] batch={len(events)} "
                f"({pct:.0f}%) -> {', '.join(keys)}"
            )

            pos = end

            if pos < len(remaining):
                delay = random.uniform(args.min_delay, args.max_delay)
                time.sleep(delay)

    except KeyboardInterrupt:
        print("\nInterrupted.")

    print(f"Done. {batch_num} batches, {pos} events uploaded.")


if __name__ == "__main__":
    main()
