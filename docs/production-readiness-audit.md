# Production Readiness Audit — Music Streaming Data Pipeline

> **Audit date:** 2026-06-21  
> **Branch audited:** `feat/stage0-pyspark-refactor`  
> **Auditor:** Engineering review prior to promote-to-main

This document records every gap found during the pre-production audit, the
remediation applied (or the rationale for accepting the gap), and the current
status of each item. Items are grouped by tier — correctness first, then
observability, performance, security, and known remaining limitations.

**Status key**

| Symbol | Meaning |
|--------|---------|
| ✅ Fixed | Gap closed in this hardening branch |
| ⚠️ Accepted | Gap known; accepted with documented rationale |
| 🔮 Future | Out of scope now; tracked for a future cycle |

---

## Tier 0 — Correctness

These gaps could cause silent data loss, wrong output, or untestable logic.

### 0.1 ETL scripts not importable/testable without Glue runtime ✅ Fixed

**Gap:** `silver_etl.py` and `gold_etl.py` had their transform logic inline
inside `main()`, guarded by `from awsglue.utils import getResolvedOptions`. Any
unit test would need a Glue runtime — impossible in CI.

**Fix:** Extracted `clean_streams`, `select_songs`, `select_users`,
`build_curated` (silver) and `compute_genre_kpis`, `compute_top_songs`,
`compute_top_genres` (gold) as pure, importable functions behind the
`if __name__ == "__main__"` guard. Tests can now import and call them directly
with a local `SparkSession`.

**Commit:** `dc6abf8`

---

### 0.2 Silver ETL had no data quality accounting ✅ Fixed

**Gap:** The Silver job wrote output without counting how many rows were dropped
at each cleaning stage. A 100 % rejection rate would silently produce an empty
partition with no error.

**Fix:** Added per-gate row counts (raw → dropna → dedup → timestamp parse →
inner join) emitted to CloudWatch (`MusicPipeline/DQ`). Added a
`max_drop_rate` circuit breaker (default 10 %): if the drop rate exceeds the
threshold, the job raises `ValueError` so Step Functions `Catch` → SNS alert
fires.

**Commit:** `f964f1f` · **File:** `silver_etl.py`

---

### 0.3 DDB ETL had no poison-partition guard or write reconciliation ✅ Fixed

**Gap:** `ddb_etl.py` iterated Parquet files without catching parse errors. A
single corrupt file would crash the entire load with an undiagnosable traceback.
There was also no verification that every row read was actually submitted.

**Fix:** Added a try/except around `pq.read_table` that accumulates bad keys and
raises `RuntimeError` at the end, naming every corrupt file. Added a write-count
assertion after each `batch_writer()` block (rows read == `put_item` calls
submitted).

**Commit:** `968fcf7` · **File:** `ddb_etl.py`

---

### 0.4 Gold ETL read the entire Silver table instead of the run-date partition ✅ Fixed

**Gap:** `gold_etl.py` called `spark.read.parquet(f"{silver_path}/streams_curated")`,
scanning every historical partition on every run. This grows linearly with
backlog size and makes an absent partition a silent empty result rather than an
error.

**Fix:** Changed to a direct partition read:
```python
spark.read.option("basePath", f"{silver_path}/streams_curated")
           .parquet(f"{silver_path}/streams_curated/event_date={run_date}")
```
Added guards for an absent path (raises `RuntimeError`) and an empty partition
(raises `ValueError`). The `basePath` option is required because `partitionBy()`
strips the `event_date` column from Parquet file metadata.

**Commit:** `69d0e1b` · **File:** `gold_etl.py`

---

### 0.5 No unit or integration tests ✅ Fixed

**Gap:** The test suite existed only for Lambda handlers. All Glue ETL logic was
untested.

**Fix:** Added 35 tests across five files:

| File | What is tested |
|------|----------------|
| `test_silver_etl.py` | `clean_streams` (null-drop, dedup, bad timestamp), `build_curated` (join logic, genre normalisation, `listen_seconds`, `event_date`), `_extract_run_date` edge cases |
| `test_gold_etl.py` | `compute_genre_kpis` (counts, unique listeners, totals/averages), `compute_top_songs` (ranking, tiebreak, n-limit, composite key), `compute_top_genres` (ranking, tiebreak, n-limit) |
| `test_ddb_etl.py` | Partition path parsing, decimal coercion, paginated read/merge, poison-partition guard (single + multi-file), write reconciliation |

PySpark tests use a session-scoped `SparkSession` via `conftest.py` and are
auto-skipped without Java 11 (`pytest.importorskip("pyspark")`).

**Commit:** `86d66f9`

---

## Tier 1 — Observability

### 1.1 No alarms on DLQ depth, pipeline SLA, or DQ drop rate ✅ Fixed

**Gap:** The CloudWatch dashboard existed but no alarms would fire if the DLQ
accumulated messages, the pipeline didn't run for a day, or Silver dropped more
than 10 % of rows.

**Fix:** Added three alarms to `terraform/modules/observability/main.tf`:

| Alarm | Condition | Meaning |
|-------|-----------|---------|
| `{env}-pipeline-dlq-depth` | `ApproximateNumberOfMessagesVisible > 0` | EventBridge → Lambda delivery failed and was captured in the DLQ |
| `{env}-pipeline-sla-breach` | `ExecutionsSucceeded < 1` over 25 h | Pipeline did not complete at least once in the past day |
| `{env}-silver-dq-drop-rate-high` | `DropRatePct > 10` | Silver ETL dropped more than 10 % of input rows |

`DropRatePct` is emitted with only the `{Job}` dimension (not `{Job, RunDate}`)
so a single alarm covers all run dates without needing to be recreated daily.

**Commit:** `7656d22`

---

### 1.2 Lambda functions had X-Ray tracing in PassThrough mode ✅ Fixed

**Gap:** All four Lambda `tracing_config` blocks were set to `"PassThrough"`,
so no distributed traces were recorded across the Lambda → Step Functions →
Glue chain.

**Fix:** Changed all four to `mode = "Active"` and attached the
`AWSXRayDaemonWriteAccess` managed policy to each Lambda role.

**Commit:** `7656d22` · **Files:** `lambda-functions/main.tf`, `iam-roles/main.tf`

---

### 1.3 No lineage metadata in Silver, Gold, or DynamoDB records ✅ Fixed

**Gap:** Records in every layer were anonymous — there was no way to trace which
pipeline execution (or which run date) produced a given row, making incident
investigation rely entirely on CloudWatch timestamps.

**Fix:** Added two lineage columns end-to-end:

| Column | Source | Written to |
|--------|--------|-----------|
| `ingested_at` | `$$.Execution.StartTime` (Step Functions context) | Silver Parquet, Gold Parquet, DDB items |
| `source_execution_id` | `$$.Execution.Id` | Silver Parquet, Gold Parquet, DDB items |

The Step Functions state machine passes both values as Glue job arguments via
the `"--key.$"` Parameters syntax. The Glue Catalog tables were updated to
register both columns.

**Commit:** `5665973` · **Files:** `silver_etl.py`, `gold_etl.py`, `ddb_etl.py`,
`step-functions/main.tf`, `glue-catalog/main.tf`

---

### 1.4 No operations runbook ✅ Fixed

**Gap:** There was no documented procedure for common operational tasks: replaying
the DLQ, backfilling a missed date, handling a schema change, recovering after
accidental deletion.

**Fix:** Created `docs/runbooks.md` with nine sections:

1. High validator rejection rate
2. DLQ backlog — replay procedure
3. Glue job failure or timeout
4. Manual backfill of a past landing date
5. Late-arrival / watermark behaviour
6. Schema-evolution procedure
7. Disaster recovery (RTO/RPO)
8. DDB capacity and hot-partition notes
9. Output file-size tuning

**Commit:** `bdf07ca`

---

### 1.5 README had factual errors ✅ Fixed

**Gap:** The README described Bronze files as JSON (they are CSV), qualified the
no-VPC stance as "current dev" (it is intentional design), and understated the
test count.

**Fix:** Corrected all three; added PySpark test commands; updated the repo
layout table.

**Commit:** `29e6d6f`

---

## Tier 2 — Performance

### 2.1 Partitioned writes produced many tiny Parquet files ✅ Fixed

**Gap:** Spark's default parallelism creates one output file per task per
partition. With 200 shuffle partitions and small daily data (tens of thousands
of rows), each `event_date` or `date` partition contained hundreds of files
under 1 KB each — multiplying Athena S3 `GET` costs and slowing `ddb_etl`'s
per-file page loop.

**Fix:** Added `.coalesce(1)` before every `.write.mode("overwrite").partitionBy()`
call in `silver_etl.py` and `gold_etl.py`. At the current daily volume (< 34k
rows, tens of MB), one file per partition is well within the 128–256 MB Parquet
sweet-spot. `runbooks.md §9` documents the upgrade path to `repartition(n)` when
daily volume grows.

**Commit:** `951c6f7`

---

### 2.2 Glue jobs had a single shared worker count and timeout ✅ Fixed

**Gap:** A single `worker_count` and `timeout_minutes` variable applied to all
three jobs. Silver (heavy join + clean), Gold (lightweight aggregation), and
DDB-ETL (Python Shell, not Spark) have very different resource profiles.

**Fix:** Replaced the shared variables with per-job equivalents and added a
boolean `enable_auto_scaling` flag (default `false`). When `true`, Glue's
managed auto-scaling treats `*_worker_count` as the worker ceiling rather than
a fixed allocation.

| Variable | Default |
|----------|---------|
| `silver_worker_type` | `G.1X` |
| `silver_worker_count` | 2 |
| `silver_timeout_minutes` | 60 |
| `gold_worker_type` | `G.1X` |
| `gold_worker_count` | 2 |
| `gold_timeout_minutes` | 30 |
| `ddb_timeout_minutes` | 30 |
| `enable_auto_scaling` | `false` |

**Commit:** `fad7c7a` · **Files:** `glue-jobs/variables.tf`, `glue-jobs/main.tf`

---

## Tier 3 — Security

### 3.1 Step Functions X-Ray policy was incomplete ✅ Fixed

**Gap:** The `step_functions_xray` policy granted only `PutTraceSegments` and
`PutTelemetryRecords`. Step Functions also calls `GetSamplingRules` and
`GetSamplingTargets` to decide which executions to trace; without them, the
tracer silently falls back to sampling every execution.

**Fix:** Added both sampling actions. A comment explains why the resource must
remain `"*"` (X-Ray trace operations are not resource-scopable in IAM).

**Commit:** `01e0556`

---

### 3.2 Archiver Lambda S3 policy was broader than necessary ✅ Fixed

**Gap:** `ReadDeleteBronze` allowed `s3:ListBucket` on the entire bronze bucket
and object-level actions on `streams/*`, giving the archiver read/delete access
to the reference data prefix (`reference/songs/`, `reference/users/`).

**Fix:** Split into two statements:
- `ListBronzeStreams`: `s3:ListBucket` on the bucket with a `StringLike`
  condition on `s3:prefix = "streams/landing_date=*"`
- `ReadDeleteBronzeStreams`: object-level actions on
  `bronze/streams/landing_date=*` only

**Commit:** `01e0556`

---

### 3.3 DDB ETL Gold reader policy allowed access to any Gold prefix ✅ Fixed

**Gap:** `ReadGold` granted `s3:GetObject` on `gold/*`, allowing the DDB ETL
role to read any path on the Gold bucket, including future datasets not intended
for DynamoDB loading.

**Fix:** Restricted to the three specific date-partitioned prefixes the job
actually reads:
- `gold/genre_kpis_daily/date=*`
- `gold/top_songs_by_genre_daily/date=*`
- `gold/top_genres_daily/date=*`

**Commit:** `01e0556`

---

## Known remaining limitations

These gaps were not closed in this cycle. Each has a documented rationale.

### L.1 No VPC ⚠️ Accepted

All pipeline services communicate over AWS-managed endpoints. There is no NAT
Gateway, no PrivateLink, and no Glue connection object. This is **intentional
design** — not a gap. See README "Why no VPC?" for the full rationale.

---

### L.2 `AWSGlueServiceRole` grants broad S3 access ⚠️ Accepted

The `AWSGlueServiceRole` managed policy (attached to all three Glue roles)
includes `s3:GetObject`/`s3:PutObject`/`s3:DeleteObject` on `*` and
`s3:ListBucket` broadly. This means the custom least-privilege S3 policies on
these roles are defense-in-depth rather than the only enforcement layer.

Replacing `AWSGlueServiceRole` with a fully custom policy would require
replicating all its CloudWatch Logs, EC2 network interface, and Glue service
permissions — a substantial maintenance burden with low marginal security benefit
in a single-account setup where the Glue execution role is already confined to
the pipeline account. Accepted; revisit if a shared Glue environment is
introduced.

---

### L.3 Glue auto-scaling disabled by default 🔮 Future

`enable_auto_scaling = false` by default. Enable it for a specific environment
by setting the variable in `terraform.tfvars`. At current volumes (< 34k
events/day, 2 workers), Glue auto-scaling provides no benefit. Re-evaluate when
daily event volume exceeds ~500k rows or when Silver job duration exceeds 5
minutes.

---

### L.4 PySpark tests require Java 11 and are skipped in CI without it 🔮 Future

The GitHub Actions workflow does not install a JDK, so the 12 PySpark tests are
auto-skipped (`pytest.importorskip("pyspark")`). To run them in CI, add a
`uses: actions/setup-java` step with `distribution: temurin, java-version: 11`
before the pytest step. Deferred because the CI runner's cold-start time is a
cost/speed trade-off for a student project.

---

### L.5 Single-region deployment — no multi-region DR 🔮 Future

The pipeline runs in one AWS region. Bronze S3 has versioning enabled, and
Silver/Gold are fully recomputable from Bronze. DynamoDB PITR provides a 35-day
point-in-time restore window. Cross-region S3 replication and a standby state
machine would reduce RTO below the current ~10–20 min per-day reprocess time.
Not warranted at the current scale.

---

### L.6 No S3 object tagging strategy 🔮 Future

Buckets are not tagged at the object level with sensitivity, owner, or retention
classification. This would be the prerequisite for Lake Formation column-level
access control or fine-grained S3 lifecycle rules. Defer until a multi-team
access model is required.

---

### L.7 CloudWatch DDB alarms not deployed for each KPI table 🔮 Future

`runbooks.md §8` recommends a `SystemErrors > 0` alarm per KPI table, but these
alarms are not yet wired in `terraform/modules/observability/main.tf`. Add three
per-table `aws_cloudwatch_metric_alarm` resources if DDB throttling becomes a
concern in production.

---

### L.8 No per-query Athena cost guardrail 🔮 Future

The Athena workgroup has no `bytes_scanned_cutoff_per_query`. A runaway Athena
query on an unpartitioned scan of Silver could generate unexpected cost. Add a
cutoff (e.g., 10 GB) to the workgroup in `terraform/modules/athena/` when the
dataset grows large enough for this to matter.
