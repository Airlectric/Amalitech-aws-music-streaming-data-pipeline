#!/usr/bin/env python3
"""Simulate real-world streaming data using the provided CSV files.

Loads users.csv, songs.csv, and streams*.csv, then replays the events
in unpredictable batches with variable timing — matching the bronze
Glue catalog table schema.

Usage:
  python scripts/produce_streams.py bronze-108782069549         # ~500 events, ~2min demo
  python scripts/produce_streams.py bronze-108782069549 --all   # all 34k events
  python scripts/produce_streams.py bronze-108782069549 --burst # dump everything now
  python scripts/produce_streams.py bronze-108782069549 --count 100
"""

import csv
import json
import os
import random
import time
import uuid

import boto3
from collections import defaultdict
from datetime import datetime


BASE_DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")

# ---------------------------------------------------------------------------
# Platform options (keep it simple — 3 choices)
# ---------------------------------------------------------------------------
PLATFORMS = ("mobile", "web", "api")

# User-country → short region (used downstream for grouping)
COUNTRY_TO_REGION = defaultdict(
    lambda: "ROW",
    {
        "United States": "US",
        "Canada": "NA",
        "Mexico": "LATAM",
        "Brazil": "LATAM",
        "Argentina": "LATAM",
        "Colombia": "LATAM",
        "Chile": "LATAM",
        "Peru": "LATAM",
        "United Kingdom": "EU",
        "Germany": "EU",
        "France": "EU",
        "Spain": "EU",
        "Italy": "EU",
        "Netherlands": "EU",
        "Ireland": "EU",
        "Sweden": "EU",
        "Norway": "EU",
        "Denmark": "EU",
        "Finland": "EU",
        "Poland": "EU",
        "Portugal": "EU",
        "Belgium": "EU",
        "Switzerland": "EU",
        "Austria": "EU",
        "Australia": "APAC",
        "New Zealand": "APAC",
        "Japan": "APAC",
        "South Korea": "APAC",
        "India": "APAC",
        "China": "APAC",
        "Nigeria": "AF",
        "South Africa": "AF",
        "Egypt": "AF",
    },
)


# ---------------------------------------------------------------------------
# Data loaders
# ---------------------------------------------------------------------------
def _load_csv(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def load_users(path=None):
    path = path or os.path.join(BASE_DATA_DIR, "users", "users.csv")
    rows = _load_csv(path)
    lookup = {}
    for r in rows:
        uid = r["user_id"].strip()
        lookup[uid] = {
            "user_id": uid,
            "user_name": r["user_name"].strip(),
            "user_age": int(r["user_age"]),
            "user_country": r["user_country"].strip(),
            "region": COUNTRY_TO_REGION[r["user_country"].strip()],
        }
    return lookup


def load_songs(path=None):
    path = path or os.path.join(BASE_DATA_DIR, "songs", "songs.csv")
    rows = _load_csv(path)
    lookup = {}
    popularity_bins = []
    for r in rows:
        tid = r["track_id"].strip()
        pop = int(r["popularity"])
        lookup[tid] = {
            "track_id": tid,
            "title": r["track_name"].strip(),
            "artist_name": r["artists"].strip(),
            "artist_id": r["artists"].strip(),
            "album": r["album_name"].strip(),
            "duration_ms": int(r["duration_ms"]),
            "genre": r["track_genre"].strip(),
            "popularity": pop,
        }
        popularity_bins.extend([tid] * max(1, pop))
    return lookup, popularity_bins


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
# Event generation
# ---------------------------------------------------------------------------
def build_events(stream_events, users, songs, pop_bins, count=None):
    """Build bronze-format events from stream event pool."""

    selected = stream_events
    if count and count < len(selected):
        weights = [songs.get(e["track_id"], {}).get("popularity", 1) for e in selected]
        total = sum(weights)
        probs = [w / total for w in weights] if total else None
        idx = random.choices(range(len(selected)), weights=probs, k=count)
        selected = [selected[i] for i in idx]

    out = []
    for se in selected:
        track = songs.get(se["track_id"])
        user = users.get(se["user_id"])
        if not track or not user:
            continue

        listen_dt = datetime.strptime(se["listen_time"], "%Y-%m-%d %H:%M:%S")
        event_date = listen_dt.strftime("%Y/%m/%d")

        # Simulate listening behaviour
        if random.random() < 0.08:
            play_duration = 0
            skipped = True
        else:
            max_play = max(5, track["duration_ms"] // 1000)
            play_duration = random.randint(5, max_play)
            skipped = False

        out.append(
            {
                "event_id": str(uuid.uuid4()),
                "artist_id": track["artist_id"],
                "artist_name": track["artist_name"],
                "title": track["title"],
                "album": track["album"],
                "duration_ms": track["duration_ms"],
                "genre": track["genre"],
                "event_date": event_date,
                "event_timestamp": se["listen_time"],
                "user_id": user["user_id"],
                "user_country": user["user_country"],
                "platform": random.choice(PLATFORMS),
                "play_duration_seconds": play_duration,
                "skipped": skipped,
            }
        )
    return out


# ---------------------------------------------------------------------------
# Upload
# ---------------------------------------------------------------------------
def upload_batch(s3_client, bucket, events, prefix):
    if not events:
        return None

    # Use the first event's event_date for the partition path
    event_date = events[0]["event_date"]
    filename = f"batch_{uuid.uuid4().hex[:8]}.json"
    key = f"{prefix}{event_date}/{filename}"
    body = "\n".join(json.dumps(e) for e in events)
    s3_client.put_object(Bucket=bucket, Key=key, Body=body.encode())
    return key


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Simulate unpredictable streaming using real CSV data"
    )
    parser.add_argument("bucket", help="Bronze S3 bucket name")
    parser.add_argument("--prefix", default="streams/", help="S3 key prefix")
    parser.add_argument("--profile", default=None, help="AWS profile name")
    parser.add_argument("--endpoint-url", default=None, help="S3 endpoint (localstack)")

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

    # ---- Load data ---------------------------------------------------------
    print("Loading data...")
    users = load_users()
    songs, pop_bins = load_songs()
    streams = load_streams()
    print(f"  {len(users)} users, {len(songs)} songs, {len(streams)} stream events")

    total_to_process = len(streams)
    if args.count:
        total_to_process = min(args.count, total_to_process)
    elif not args.all and not args.burst:
        total_to_process = min(500, total_to_process)

    if args.burst:
        events = build_events(streams, users, songs, pop_bins, count=total_to_process)
        key = upload_batch(s3, args.bucket, events, args.prefix)
        print(f"Burst: {len(events)} events → {key}")
        return

    print(f"Streaming {total_to_process} events in unpredictable batches...")
    print(f"  batch size: {args.min_batch}–{args.max_batch}")
    print(f"  delay: {args.min_delay}–{args.max_delay}s")

    # Shuffle & track remaining
    remaining = random.sample(streams, total_to_process)
    batch_num = 0
    pos = 0

    try:
        while pos < len(remaining):
            batch_size = random.randint(args.min_batch, args.max_batch)
            end = min(pos + batch_size, len(remaining))
            batch = remaining[pos:end]

            events = build_events(batch, users, songs, pop_bins)
            key = upload_batch(s3, args.bucket, events, args.prefix)
            batch_num += 1
            pct = end / len(remaining) * 100
            print(
                f"  [{batch_num}] batch={len(events)} "
                f"date={events[0]['event_date'] if events else '?'} "
                f"({pct:.0f}%) → {key}"
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
