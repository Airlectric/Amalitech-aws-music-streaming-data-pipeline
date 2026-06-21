# Operations Runbooks — Music Streaming Data Pipeline

> Paths, table names, and resource names below use `{env}` as a placeholder for the
> environment prefix (e.g. `dev`, `prod`). Substitute the real value before running any
> command.

---

## Table of contents

1. [High validator rejection rate](#1-high-validator-rejection-rate)
2. [DLQ backlog — replay procedure](#2-dlq-backlog--replay-procedure)
3. [Glue job failure or timeout](#3-glue-job-failure-or-timeout)
4. [Manual backfill of a past landing date](#4-manual-backfill-of-a-past-landing-date)
5. [Late-arrival / watermark behaviour](#5-late-arrival--watermark-behaviour)
6. [Schema-evolution procedure](#6-schema-evolution-procedure)
7. [Disaster recovery](#7-disaster-recovery)
8. [DDB capacity and hot-partition notes](#8-ddb-capacity-and-hot-partition-notes)
9. [Output file-size tuning](#9-output-file-size-tuning)

---

## 1. High validator rejection rate

**Symptom:** SNS alert from `{env}-step-functions-failed` with cause
`DataValidationFailed`, or the CloudWatch DQ drop-rate alarm
(`{env}-silver-dq-drop-rate-high`) fires.

### Investigate

**Step 1 — find the batch ID from the SNS notification** (or the Step Functions
execution input in the console under `{env}-medallion-pipeline`).

**Step 2 — query the DQ reports table** for the batch:

```
aws dynamodb get-item \
  --table-name {env}-dq-reports \
  --key '{"batch_id":{"S":"<batch_id>"},"event_date":{"S":"YYYY-MM-DD"}}'
```

The item contains `valid_count`, `error_count`, and an `errors` list with the first
N rejection reasons (e.g. missing required field, schema drift, wrong date format).

**Step 3 — inspect the quarantined file** (path is in the Step Functions execution
input under `$.key`; the quarantine handler copies it to the quarantine bucket):

```
aws s3 ls s3://{env}-quarantine/streams/ --recursive | grep <batch_id>
aws s3 cp s3://{env}-quarantine/streams/<path> /tmp/rejected.csv
head -20 /tmp/rejected.csv
```

**Step 4 — check Lambda logs** for the validator's full error list:

```
aws logs tail /aws/lambda/{env}-event-validator --since 1h --format short
```

### Common causes and fixes

| Symptom | Likely cause | Fix |
|---|---|---|
| `missing_required_field: user_id` on most rows | CSV column order changed | Upstream schema change — coordinate with producer, update `STREAMS_SCHEMA` in `silver_etl.py` if intentional |
| `unknown_field: new_col` | New column added upstream without notice | Schema-evolution procedure (§6) |
| All rows rejected, `error_count == record_count` | Wrong delimiter or encoding | Check file manually; if systematic, raise with upstream team |
| Isolated rows rejected | Genuine bad data in source | Normal for ≤ 5 %; if > 10 % over multiple batches, escalate to upstream |

### After fixing the upstream issue

Re-upload the corrected file to Bronze and let EventBridge trigger a new execution,
or use the manual backfill procedure (§4) if the original file has already been
archived.

---

## 2. DLQ backlog — replay procedure

**Symptom:** `{env}-pipeline-dlq-depth` CloudWatch alarm fires. Messages in the DLQ
mean at least one S3 trigger event was not processed after all retries.

### Triage first

```bash
# Count messages in the DLQ
aws sqs get-queue-attributes \
  --queue-url https://sqs.{region}.amazonaws.com/{account-id}/{env}-pipeline-dlq \
  --attribute-names ApproximateNumberOfMessages
```

Read one message to understand what failed (do NOT delete it yet):

```bash
aws sqs receive-message \
  --queue-url https://sqs.{region}.amazonaws.com/{account-id}/{env}-pipeline-dlq \
  --max-number-of-messages 1
```

The message body is the original EventBridge event (S3 Object Created notification).
Extract `detail.bucket.name` and `detail.object.key`.

### Determine the root cause

Check the event-router Lambda logs for the time of the failed delivery:

```bash
aws logs tail /aws/lambda/{env}-event-router --since 6h --format short
```

Fix the root cause (IAM permission, Step Functions throttle, Lambda code bug) before
replaying — replaying into a broken system just re-queues messages.

### Replay

Once the root cause is fixed, re-trigger the pipeline by manually starting a Step
Functions execution with the S3 key from the DLQ message:

```bash
aws stepfunctions start-execution \
  --state-machine-arn arn:aws:states:{region}:{account-id}:stateMachine:{env}-medallion-pipeline \
  --input '{
    "bucket": "{bronze-bucket}",
    "key": "streams/landing_date=YYYY-MM-DD/filename.csv",
    "run_date": "YYYY-MM-DD",
    "execution_id": "manual-replay-YYYYMMDD"
  }'
```

Then delete the replayed message from the DLQ:

```bash
aws sqs delete-message \
  --queue-url https://sqs.{region}.amazonaws.com/{account-id}/{env}-pipeline-dlq \
  --receipt-handle <receipt-handle-from-receive-message>
```

Repeat for each message in the DLQ. Verify the DLQ depth returns to zero and the
`{env}-pipeline-dlq-depth` alarm clears.

---

## 3. Glue job failure or timeout

**Symptom:** `{env}-glue-{silver|gold|ddb}-etl-failed` alarm fires, or Step Functions
execution lands in `PipelineFailed` state.

### Find the run logs

All three Glue jobs write to CloudWatch Logs:

```bash
# Replace {job-name} with: {env}-silver-etl, {env}-gold-etl, or {env}-ddb-etl
aws logs tail /aws-glue/jobs/output --log-stream-name-prefix {job-name} --since 2h
```

The Silver and DDB ETL jobs print a structured `[DQ]` / `[DDB-LOAD]` summary line on
every run. Absence of that line means the job crashed before completing.

### Safe re-run

All jobs are **idempotent and safe to re-run** for the same `run_date`:

- **silver_etl**: writes with `mode("overwrite")` + dynamic partition overwrite —
  the `event_date` partition is fully replaced on each run.
- **gold_etl**: same — each Gold partition (`date=YYYY-MM-DD`) is overwritten.
- **ddb_etl**: uses `put_item`, which is a last-writer-wins upsert in DynamoDB. Re-
  running writes identical items, leaving the table unchanged.

To re-run the full pipeline for a single day:

```bash
aws stepfunctions start-execution \
  --state-machine-arn arn:aws:states:{region}:{account-id}:stateMachine:{env}-medallion-pipeline \
  --input '{
    "bucket": "{bronze-bucket}",
    "key": "streams/landing_date=YYYY-MM-DD/filename.csv",
    "run_date": "YYYY-MM-DD",
    "execution_id": "manual-rerun-YYYYMMDD"
  }'
```

To re-run only Gold + DDB (when Silver is intact but Gold/DDB are suspect):

```bash
# Start Gold directly
aws glue start-job-run \
  --job-name {env}-gold-etl \
  --arguments '{
    "--silver_path": "s3://{silver-bucket}",
    "--gold_path": "s3://{gold-bucket}",
    "--run_date": "YYYY-MM-DD",
    "--execution_start_time": "manual-rerun",
    "--execution_id": "manual-rerun-YYYYMMDD"
  }'
```

Wait for Gold to complete, then start DDB-ETL the same way.

### Timeout

If a job times out, the default Glue timeout is 2880 minutes (48 hours) — a timeout
that short suggests runaway processing, not a clock issue. Check:

1. The input partition — is the CSV abnormally large?
2. Whether the Glue worker count needs increasing (`number_of_workers` in
   `terraform/modules/glue-jobs/variables.tf`).
3. Whether `--enable-auto-scaling` should be turned on (see Stage 3c in the plan).

### Drop-rate circuit breaker tripped

If the `silver_etl` job fails with `ValueError: Drop rate X% exceeds threshold Y%`,
the raw data had too many nulls, duplicates, or bad timestamps. Investigate the source
file quality first; if the file is intentionally sparse, temporarily increase
`--max_drop_rate` in the Glue job arguments via the console before re-running.

---

## 4. Manual backfill of a past landing date

Use when a day's data was never loaded (missed EventBridge trigger) or needs to be
reloaded from scratch.

### Prerequisites

The raw CSV must already exist in the Bronze bucket at the correct path:

```
s3://{bronze-bucket}/streams/landing_date=YYYY-MM-DD/filename.csv
```

If it was archived, restore it from the archive bucket first:

```bash
aws s3 cp \
  s3://{archive-bucket}/streams/landing_date=YYYY-MM-DD/filename.csv \
  s3://{bronze-bucket}/streams/landing_date=YYYY-MM-DD/filename.csv
```

### Trigger the backfill

```bash
aws stepfunctions start-execution \
  --state-machine-arn arn:aws:states:{region}:{account-id}:stateMachine:{env}-medallion-pipeline \
  --input '{
    "bucket": "{bronze-bucket}",
    "key": "streams/landing_date=YYYY-MM-DD/filename.csv",
    "run_date": "YYYY-MM-DD",
    "execution_id": "backfill-YYYYMMDD"
  }'
```

This runs the full Silver → Gold → DDB chain. The pipeline is idempotent for the date,
so running it again for a date that was already loaded is safe.

### Multi-day backfill

To backfill a range of dates, run a loop (from a terminal with AWS CLI access):

```bash
for date in 2024-06-01 2024-06-02 2024-06-03; do
  aws stepfunctions start-execution \
    --state-machine-arn arn:aws:states:{region}:{account-id}:stateMachine:{env}-medallion-pipeline \
    --input "{
      \"bucket\": \"{bronze-bucket}\",
      \"key\": \"streams/landing_date=${date}/streams.csv\",
      \"run_date\": \"${date}\",
      \"execution_id\": \"backfill-${date}\"
    }"
  # Step Functions Standard Workflows have an execution quota.
  # Throttle to one execution per minute for large backfills.
  sleep 60
done
```

Verify in the Step Functions console that all executions succeeded before removing the
restored Bronze files.

---

## 5. Late-arrival / watermark behaviour

### How `run_date` is derived

The pipeline derives `run_date` from the **S3 key's Hive partition**, not from the
`listen_time` values inside the CSV:

```python
# silver_etl.py
def _extract_run_date(stream_key):
    m = re.search(r"landing_date=(\d{4}-\d{2}-\d{2})", stream_key)
    return m.group(1) if m else "unknown"
```

This means:
- A file uploaded on 2024-06-16 to `landing_date=2024-06-15/` is processed as the
  **2024-06-15** batch — the landing date in the key controls the partition, not the
  wall-clock upload time.
- `listen_time` values inside the file are not used to choose the output partition;
  they are cleaned and stored as-is in `listen_ts` and `event_date`.

### Late-arriving events

If events for 2024-06-15 arrive on 2024-06-17 in a new file (e.g. a late sensor
batch), the pipeline **does not automatically update the 2024-06-15 Gold partition**.
The operator must:

1. Upload the late file to `landing_date=2024-06-15/` alongside the original file
   (or replace it if the original should be superseded).
2. Re-run the pipeline for `2024-06-15` via the backfill procedure (§4).
3. Because `overwrite` mode is used, the Silver and Gold `2024-06-15` partitions are
   fully replaced with the combined data.

### Implication for downstream consumers

DynamoDB KPI items for a given `date` are overwritten by `put_item` on re-run, so
they will reflect the latest data after a backfill completes. Athena queries always
read the latest Parquet files on S3 — no cache invalidation is needed.

---

## 6. Schema-evolution procedure

Follow this checklist whenever a source CSV gains or loses a column.

### Adding a column to the streams CSV

1. **`silver_etl.py` — update `STREAMS_SCHEMA`**

   Add the new `StructField` to `STREAMS_SCHEMA`. If the column is nullable, set
   `nullable=True`; if it is required for downstream, add it to the `dropna` call in
   `clean_streams`.

2. **`silver_etl.py` — expose in `build_curated` and the `select()` list**

   Add the column to the `build_curated` return value's `.select(...)` if it should
   appear in Silver output.

3. **`glue-catalog/main.tf` — add the column to `silver_streams_curated`**

   ```hcl
   columns {
     name = "new_column_name"
     type = "string"   # or int / bigint / double / boolean as appropriate
   }
   ```

4. **Gold transforms** — if the new column is needed in KPI calculations, update
   `compute_genre_kpis`, `compute_top_songs`, or `compute_top_genres` in `gold_etl.py`
   and add the column to the relevant Gold catalog tables.

5. **DDB writes** — if the column should appear in DynamoDB items, add it to the
   `put_item` `Item` dict in `ddb_etl.py`.

6. **Tests** — add or update test fixtures in `test_silver_etl.py` to cover the new
   column; update the `_SONGS_SCHEMA` / `_USERS_SCHEMA` helpers if a reference table
   changed.

7. **Deploy** — apply the Terraform changes (`terraform apply`) and verify with an
   Athena `SELECT *` against the updated table to confirm the new column appears.

8. **Backfill** — if historical partitions should contain the new column, run the
   backfill procedure (§4) for the relevant date range. Partitions written before the
   change will have `NULL` for the new column (Parquet schema evolution handles this
   safely for Athena reads).

### Removing a column

Follow the same steps in reverse. Do not remove the column from the Glue Catalog
until all historical partitions have been rewritten or you are comfortable with
Athena returning `NULL` for that column on old partitions. Mark the column as
deprecated in the catalog description first.

### Renaming a column

Treat as add-new + remove-old. Rename in the Python schemas and catalog in the same
commit, backfill if needed, then remove the old column entry.

---

## 7. Disaster recovery

### What is durable

| Layer | Storage | Recovery path |
|---|---|---|
| **Bronze raw** | S3 with versioning enabled | All CSV versions are retained — the source of truth is always recoverable |
| **Silver curated** | S3 (derived from Bronze) | Fully recomputable by re-running `silver_etl` from Bronze |
| **Gold KPIs** | S3 (derived from Silver) | Fully recomputable by re-running `gold_etl` from Silver |
| **DynamoDB KPI tables** | DynamoDB with PITR enabled (35-day window) | Point-in-time restore to any second in the last 35 days; also fully recomputable from Gold |

### RTO / RPO

- **RPO (data loss):** Zero for Bronze (S3 versioning). Silver, Gold, and DDB are
  derived and can be recomputed — no data is permanently lost as long as Bronze
  survives.
- **RTO (time to restore):** Silver + Gold + DDB pipeline for a single day takes
  approximately 10–20 minutes end-to-end. A full backfill of 30 days of data takes
  roughly 5–10 hours if run sequentially (one execution per minute to avoid throttle).

### Recovering Silver / Gold after accidental deletion

```bash
# Example: re-run the last 7 days
for i in $(seq 6 -1 0); do
  date=$(date -d "-${i} days" +%Y-%m-%d)
  aws stepfunctions start-execution \
    --state-machine-arn arn:aws:states:{region}:{account-id}:stateMachine:{env}-medallion-pipeline \
    --input "{
      \"bucket\": \"{bronze-bucket}\",
      \"key\": \"streams/landing_date=${date}/streams.csv\",
      \"run_date\": \"${date}\",
      \"execution_id\": \"dr-restore-${date}\"
    }"
  sleep 60
done
```

### Recovering DynamoDB with PITR

If a logic bug corrupted the DDB KPI tables and the window is within 35 days:

```bash
aws dynamodb restore-table-to-point-in-time \
  --source-table-name {env}-genre-kpis-daily \
  --target-table-name {env}-genre-kpis-daily-restored \
  --restore-date-time "2024-06-15T12:00:00Z"
```

After verifying the restored table, swap traffic to it and delete the corrupted table.
Note: a PITR restore creates a new table — you must update any references (Terraform
state, application config) accordingly. In most cases, **re-running the pipeline is
simpler and faster** than a PITR restore.

### Key ARNs to document per environment

Record these in your team's runbook supplement (do not commit to git):

- Bronze bucket ARN
- Silver bucket ARN
- Gold bucket ARN
- Step Functions state machine ARN
- KMS key ARNs (S3 data lake, DynamoDB)
- SNS alert topic ARN

---

## 8. DDB capacity and hot-partition notes

All three KPI tables use **PAY_PER_REQUEST** (on-demand) billing — there is no
provisioned capacity to tune, and DynamoDB scales automatically for burst writes.

### Write throughput estimate

`ddb_etl` runs once per day and loads data with boto3's `batch_writer()`, which
groups `put_item` calls into `BatchWriteItem` API requests of up to 25 items each.
All items are small (< 300 bytes each), so every write consumes exactly **1 WCU**.

| Table | Items / day (sample data) | Basis |
|---|---|---|
| `genre-kpis-daily` | ~114 | one row per genre |
| `top-songs-by-genre-daily` | ~342 | top 3 songs × ~114 genres |
| `top-genres-daily` | 5 | top 5 genres fixed |
| `dq-reports` | 1 | one DQ report per pipeline run |

Total: ~462 WCUs per daily run. At on-demand pricing ($1.25 / million write
request units), the write cost is **less than $0.001 per day** at current volume.
Even at 1,000× scale (dozens of genres × large catalogues), the daily write
total stays well below on-demand's break-even point versus provisioned capacity.

### Read access patterns

Application reads are served via DynamoDB `GetItem` or `Query`:

| Table | Access pattern | DDB behaviour |
|---|---|---|
| `genre-kpis-daily` | `Query` on `genre` (PK), optionally filtered by `date` | Reads a single logical partition — scales linearly |
| `top-songs-by-genre-daily` | `Query` on `genre_date` (PK) | One API call returns all 3 ranked songs for a day |
| `top-genres-daily` | `Query` on `date` (PK) | One API call returns all 5 ranked genres |

All three queries hit single partitions and return O(1)–O(N) items where N ≤ 5.
There is no scan involved; read amplification is minimal.

### Hot-partition risk

The `{env}-genre-kpis-daily` table is keyed on `genre` (PK) + `date` (SK).
Genres such as "pop" or "rock" will receive more writes than long-tail genres.
Under on-demand mode, DynamoDB manages this automatically up to the account
limit (40,000 WCU/s default). If write throttles appear in CloudWatch
(`AWS/DynamoDB / SystemErrors`), request a limit increase via AWS Support.

### CloudWatch signals to watch

| Metric | Namespace | Concern |
|---|---|---|
| `SystemErrors` | `AWS/DynamoDB` | Throttling or internal DDB errors |
| `ConsumedWriteCapacityUnits` | `AWS/DynamoDB` | Actual write load vs account limit |
| `ConsumedReadCapacityUnits` | `AWS/DynamoDB` | Read load from application traffic |
| `SuccessfulRequestLatency` | `AWS/DynamoDB` | P99 write latency; > 50 ms consistently → investigate |

Add a CloudWatch alarm on `SystemErrors > 0` for each KPI table to get notified
of throttling before it affects the pipeline.

### When to switch to provisioned capacity

Remain on on-demand as long as:
- Daily write volume is < 10 million WCUs, **or**
- Read traffic is bursty or unpredictable (on-demand absorbs spikes without warm-up).

Switch to **provisioned + auto-scaling** only when:
1. Monthly on-demand cost exceeds the provisioned equivalent (on-demand costs ~7× more
   per WCU than provisioned at steady state), **and**
2. The read/write rate is stable enough to set meaningful auto-scaling targets.

At the current once-per-day batch write pattern with small items, this threshold is
not reached until the dataset contains **millions of genres** or the application is
serving tens of thousands of reads per second.

### TTL

| Table | Retention |
|---|---|
| `genre-kpis-daily` | 90 days |
| `top-songs-by-genre-daily` | 365 days |
| `top-genres-daily` | 365 days |
| `dq-reports` | 30 days |

TTL deletes are eventually consistent and free. Do not rely on TTL for exact-second
expiry; use it for background pruning only. The `expires_at` attribute is set by
`ddb_etl.py` at write time as `unix_timestamp + ttl_days × 86400`.

### Write sharding (future)

If a future load profile shows hot partitions on `genre_date` in `top-songs-by-genre-
daily`, consider appending a shard suffix to the PK (`genre_date#shard`) and
aggregating on read. This is not implemented today; the on-demand mode handles current
load comfortably.

---

## 9. Output file-size tuning

### Why `coalesce(1)` is used

`partitionBy()` writes one Parquet file **per Spark task** inside each date partition.
Glue's default shuffle parallelism is often 200 partitions, which produces hundreds of
tiny files (< 1 KB each) per daily partition — even for modest daily volumes. This
causes:

- **Athena cost**: each tiny file is a separate S3 `GET`; Athena charges per-byte
  scanned and performs badly with many small files because it pays per-split overhead
  regardless of content size.
- **DDB-ETL slowness**: `ddb_etl.py` pages through all Parquet files in a partition;
  more files = more `GetObject` calls for the same total bytes.
- **S3 cost**: more `PUT` and `LIST` calls at write time.

Both `silver_etl` and `gold_etl` call `.coalesce(1)` immediately before the write.
This merges all Spark partitions for the day into a single task, producing exactly
**one Parquet file per daily output partition**. Given that each run processes one
CSV file (at most ~34k rows, tens of MB), a single output file per partition is the
right target — the file stays well below the Parquet-optimal 128–256 MB threshold,
and there is no benefit to splitting it.

### When to change this

If daily event volume grows significantly (hundreds of millions of rows / multiple GB
per day), `coalesce(1)` forces all data through a single writer task and becomes a
bottleneck. At that point, switch to `repartition(n)` (which triggers a full shuffle)
and size `n` so each output file is ~128 MB:

```python
# Example: ~2 GB / day → 16 × 128 MB files
df.repartition(16).write.mode("overwrite").partitionBy("event_date").parquet(path)
```

Track file sizes in S3 with:

```bash
aws s3 ls s3://{silver-bucket}/streams_curated/event_date=YYYY-MM-DD/ \
  --human-readable --summarize
```

Upgrade `coalesce(1)` → `repartition(n)` in the Glue job scripts and adjust the
`number_of_workers` setting in `terraform/modules/glue-jobs/variables.tf` accordingly.
