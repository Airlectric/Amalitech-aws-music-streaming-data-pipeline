#!/usr/bin/env python3
"""Generate sample streaming data and upload to Bronze S3 bucket."""

import json
import random
import uuid
from datetime import datetime, timedelta, timezone

import boto3

TRACKS = [
    {"track_id": "TR001", "title": "Midnight Dreams", "artist": "Luna Nova", "album": "Starlight", "genre": "Pop", "duration_s": 234},
    {"track_id": "TR002", "title": "Electric Pulse", "artist": "The Voltaires", "album": "High Voltage", "genre": "Rock", "duration_s": 198},
    {"track_id": "TR003", "title": "Neon Garden", "artist": "Synthia", "album": "Digital Bloom", "genre": "Electronic", "duration_s": 312},
    {"track_id": "TR004", "title": "River Flow", "artist": "Jasmine K", "album": "Gentle Currents", "genre": "Jazz", "duration_s": 267},
    {"track_id": "TR005", "title": "Thunder Clap", "artist": "Bass Collective", "album": "Storm Front", "genre": "Hip-Hop", "duration_s": 183},
    {"track_id": "TR006", "title": "Solar Wind", "artist": "Cosmic Drift", "album": "Interstellar", "genre": "Ambient", "duration_s": 420},
    {"track_id": "TR007", "title": "Velvet Touch", "artist": "Satin Soul", "album": "Smooth Nights", "genre": "R&B", "duration_s": 251},
    {"track_id": "TR008", "title": "Cactus Bloom", "artist": "Desert Rose", "album": "Arid Beauty", "genre": "Folk", "duration_s": 215},
    {"track_id": "TR009", "title": "Binary Sunset", "artist": "Circuit Breakers", "album": "Code Red", "genre": "Electronic", "duration_s": 345},
    {"track_id": "TR010", "title": "Ocean Whisper", "artist": "Coral Wave", "album": "Deep Blue", "genre": "Ambient", "duration_s": 378},
]

USERS = [f"user_{i:04d}" for i in range(1, 51)]


def generate_stream_event(timestamp: datetime) -> dict:
    track = random.choice(TRACKS)
    return {
        "event_id": str(uuid.uuid4()),
        "user_id": random.choice(USERS),
        "track_id": track["track_id"],
        "title": track["title"],
        "artist": track["artist"],
        "album": track["album"],
        "genre": track["genre"],
        "duration_s": track["duration_s"],
        "listen_time_s": random.randint(10, track["duration_s"]),
        "timestamp": timestamp.isoformat(),
        "region": random.choice(["US", "EU", "APAC", "LATAM"]),
        "device": random.choice(["mobile", "desktop", "tablet", "smart_speaker"]),
        "subscription_tier": random.choice(["free", "premium", "family"]),
    }


def upload_batch(s3_client, bucket: str, events: list[dict], prefix: str):
    timestamp = datetime.now(timezone.utc)
    date_path = timestamp.strftime("year=%Y/month=%m/day=%d/hour=%H")

    filename = f"streams_{timestamp.strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:8]}.json"
    key = f"{prefix}{date_path}/{filename}"

    body = "\n".join(json.dumps(e) for e in events)
    s3_client.put_object(Bucket=bucket, Key=key, Body=body.encode())
    return key


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Generate and upload sample streams")
    parser.add_argument("bucket", help="Bronze S3 bucket name")
    parser.add_argument("--count", type=int, default=10, help="Number of events per batch")
    parser.add_argument("--batches", type=int, default=1, help="Number of batches")
    parser.add_argument("--interval-s", type=int, default=0, help="Seconds between batches")
    parser.add_argument("--prefix", default="streams/", help="S3 key prefix")
    parser.add_argument("--profile", default=None, help="AWS profile name")
    parser.add_argument("--endpoint-url", default=None, help="S3 endpoint URL (for localstack)")
    args = parser.parse_args()

    session = boto3.Session(profile_name=args.profile)
    s3 = session.client("s3", endpoint_url=args.endpoint_url)

    print(f"Generating {args.count}x{args.batches} events → s3://{args.bucket}/{args.prefix}")
    for i in range(args.batches):
        now = datetime.now(timezone.utc)
        events = [generate_stream_event(now - timedelta(seconds=random.randint(0, 300))) for _ in range(args.count)]
        key = upload_batch(s3, args.bucket, events, args.prefix)
        print(f"  [{i+1}/{args.batches}] Uploaded {args.count} events → {key}")
        if args.interval_s and i < args.batches - 1:
            import time
            time.sleep(args.interval_s)

    print("Done.")


if __name__ == "__main__":
    main()
