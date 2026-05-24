import sys
import json
from datetime import datetime, timezone
from awsglue.utils import getResolvedOptions
from decimal import Decimal
import boto3

args = getResolvedOptions(sys.argv, ["gold_path", "table_hourly", "table_daily", "table_monthly"])
gold_path = args["gold_path"]
table_hourly = args["table_hourly"]
table_daily = args["table_daily"]
table_monthly = args["table_monthly"]

s3 = boto3.client("s3")
ddb = boto3.resource("dynamodb")

bucket = gold_path.replace("s3://", "").rstrip("/")

import io
import pyarrow.parquet as pq
import re

resp = s3.list_objects_v2(Bucket=bucket, Prefix="year=")
rows = {}
for obj in resp.get("Contents", []):
    if obj["Key"].endswith(".parquet"):
        body = s3.get_object(Bucket=bucket, Key=obj["Key"])["Body"].read()
        table = pq.read_table(io.BytesIO(body))
        d = table.to_pydict()
        if not rows:
            rows = {k: list(v) for k, v in d.items()}
        else:
            for k in rows:
                rows[k].extend(d[k])

if not rows or not rows.get("artist"):
    print("No data found in gold path")
    sys.exit(0)

# Parse window_start -> year/month/day/hour
import re
ws_pattern = re.compile(r"(\d{4})-(\d{2})-(\d{2})-T-(\d{2})")

years, months, days, hours = [], [], [], []
for ws in rows["window_start"]:
    m = ws_pattern.match(ws)
    if m:
        years.append(int(m.group(1)))
        months.append(int(m.group(2)))
        days.append(int(m.group(3)))
        hours.append(int(m.group(4)))
    else:
        years.append(None)
        months.append(None)
        days.append(None)
        hours.append(None)

rows["year"] = years
rows["month"] = months
rows["day"] = days
rows["hour"] = hours

valid = [i for i, a in enumerate(rows["artist"]) if a is not None and rows["year"][i] is not None]
if not valid:
    print("No valid rows found")
    sys.exit(0)

rows = {k: [v[i] for i in valid] for k, v in rows.items()}

now_ts = int(datetime.now(timezone.utc).timestamp())
ttl_90 = Decimal(now_ts + (90 * 86400))
ttl_365 = Decimal(now_ts + (365 * 86400))

hourly_items = []
for i in range(len(rows["artist"])):
    hour_ts = f"{rows['year'][i]}-{rows['month'][i]:02d}-{rows['day'][i]:02d}T{rows['hour'][i]:02d}:00:00"
    hourly_items.append({
        "artist_id": rows["artist"][i],
        "hour_ts": hour_ts,
        "total_streams": rows["total_streams"][i],
        "unique_listeners": rows["unique_listeners"][i],
        "avg_listen_time_s": Decimal(str(round(rows["avg_listen_time_s"][i], 2))),
        "ttl": ttl_90,
    })

table = ddb.Table(table_hourly)
with table.batch_writer() as batch:
    for item in hourly_items:
        batch.put_item(Item=item)
print(f"Hourly: {len(hourly_items)} items")

daily_agg = {}
for i in range(len(rows["artist"])):
    key = (rows["artist"][i], rows["year"][i], rows["month"][i], rows["day"][i])
    if key not in daily_agg:
        daily_agg[key] = {"total_streams": 0, "unique_listeners": 0, "avg_list": []}
    daily_agg[key]["total_streams"] += rows["total_streams"][i]
    daily_agg[key]["unique_listeners"] += rows["unique_listeners"][i]
    daily_agg[key]["avg_list"].append(rows["avg_listen_time_s"][i])

daily_items = []
for (artist, year, month, day), agg in daily_agg.items():
    daily_items.append({
        "artist_id": artist,
        "date": f"{year}-{month:02d}-{day:02d}",
        "total_streams": agg["total_streams"],
        "unique_listeners": agg["unique_listeners"],
        "avg_listen_time_s": Decimal(str(round(sum(agg["avg_list"]) / len(agg["avg_list"]), 2))),
        "ttl": ttl_365,
    })

table = ddb.Table(table_daily)
with table.batch_writer() as batch:
    for item in daily_items:
        batch.put_item(Item=item)
print(f"Daily: {len(daily_items)} items")

monthly_agg = {}
for i in range(len(rows["artist"])):
    key = (rows["artist"][i], rows["year"][i], rows["month"][i])
    if key not in monthly_agg:
        monthly_agg[key] = {"total_streams": 0, "unique_listeners": 0, "avg_list": []}
    monthly_agg[key]["total_streams"] += rows["total_streams"][i]
    monthly_agg[key]["unique_listeners"] += rows["unique_listeners"][i]
    monthly_agg[key]["avg_list"].append(rows["avg_listen_time_s"][i])

monthly_items = []
for (artist, year, month), agg in monthly_agg.items():
    monthly_items.append({
        "artist_id": artist,
        "month": f"{year}-{month:02d}",
        "total_streams": agg["total_streams"],
        "unique_listeners": agg["unique_listeners"],
        "avg_listen_time_s": Decimal(str(round(sum(agg["avg_list"]) / len(agg["avg_list"]), 2))),
    })

table = ddb.Table(table_monthly)
with table.batch_writer() as batch:
    for item in monthly_items:
        batch.put_item(Item=item)
print(f"Monthly: {len(monthly_items)} items")
