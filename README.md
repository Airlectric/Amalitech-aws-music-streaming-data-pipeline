# Music Streaming Data Pipeline

A production-ready, event-driven serverless ETL pipeline on AWS that ingests music streaming events, validates them, transforms them through a medallion architecture (Bronze → Silver → Gold), and serves KPIs via DynamoDB and Athena.

---

## Architecture

![Music Streaming ETL Pipeline Architecture](docs/pipeline-architecture-v3.png)

> The architecture is fully serverless and intentionally does **not** attach Lambda or Glue jobs to a VPC. EventBridge, Lambda, Step Functions, Glue, S3, DynamoDB, Athena, CloudWatch, SNS, SQS, IAM, and KMS communicate through AWS-managed service endpoints with least-privilege IAM and KMS encryption — no NAT Gateway, no PrivateLink endpoints, no Glue connection object. The numbered badges in the diagram track the event-driven medallion flow below.

### Diagram Walkthrough

The numbered badges in the diagram correspond to the main pipeline flow steps:

1. **Raw landing:** The producer uploads raw music-streaming CSV files into the Bronze S3 bucket — the immutable source of truth. An S3 Object Created event is emitted automatically.
2. **Event routing:** EventBridge captures the S3 `Object Created` event and invokes the **Event Router Lambda**. If delivery fails after retries, the event is captured in the **SQS dead-letter queue** so nothing is silently lost.
3. **Orchestration trigger:** The Event Router calls Step Functions `StartExecution`, handing off the payload (bucket + key + run date). Step Functions (Standard) orchestrates every subsequent step.
4. **Validation:** The **Validator Lambda** inspects the file for required fields and schema. Invalid files are routed to the **Quarantine Lambda**, which moves them to Quarantine S3 and fires an SNS alert.
5. **Silver curation:** The **Silver Glue PySpark job** reads Bronze, applies explicit schemas, cleanses, deduplicates, type-casts, and writes partitioned Parquet to Silver S3. Results are registered in the Glue Data Catalog.
6. **Gold aggregation:** The **Gold Glue PySpark job** reads Silver and computes the daily KPIs: listen counts, unique listeners, total/avg listening time per genre, top 3 songs per genre per day, and top 5 genres per day. Output is partitioned Parquet in Gold S3.
7. **KPI serving:** The **DDB-Load Glue Python Shell job** reads the Gold Parquet files (pyarrow) and batch-writes the KPIs into DynamoDB tables for low-latency application lookups.
8. **Archival:** The **Archiver Lambda** moves processed Bronze files to Archive S3 (Glacier Deep Archive). It fails loud on any error so Step Functions can `Catch` and alert rather than report a false success.

### Data Flow

| Layer  | Format  | Description                                       |
|--------|---------|---------------------------------------------------|
| Bronze | CSV     | Raw streaming events, immutable source of truth   |
| Silver | Parquet | Cleaned, typed, deduplicated, dimension-enriched  |
| Gold   | Parquet | Aggregated KPIs (listens by genre, top songs, etc)|
| DDB    | DynamoDB| Hot-path KPI serving for application consumption  |

### Pipeline Stages

1. **Ingestion** — S3 PutObject on bronze bucket → EventBridge → Event Router Lambda → Step Functions
2. **Validation** — Validator Lambda checks required fields, detects schema drift, writes DQ reports to DynamoDB
3. **Quarantine** — Invalid files are copied to quarantine bucket and tagged; SNS notification is sent
4. **Silver ETL** — Glue PySpark job cleanses, deduplicates, type-casts, and partitions data
5. **Gold ETL** — Glue PySpark job aggregates daily KPIs (genre counts, top 3 songs/genre, top 5 genres)
6. **DDB Load** — Glue **Python Shell** job (pyarrow + boto3) batch-writes gold aggregates into DynamoDB tables for low-latency queries
7. **Archive** — Archiver Lambda moves processed bronze files to long-term archive (Glacier Deep Archive)
8. **Alerting & DLQ** — SNS notifications on validation/pipeline failures; failed EventBridge→router deliveries and async router failures are captured in an SQS dead-letter queue with bounded retries

---

## Tech Stack

| Layer | Service |
|---|---|
| Orchestration | AWS Step Functions (Standard) |
| Transformation | AWS Glue (PySpark + Python Shell), Glue Data Catalog |
| Storage | Amazon S3 (JSON, Parquet), DynamoDB (on-demand) |
| Eventing | Amazon EventBridge, Amazon SQS (dead-letter queue) |
| Compute | AWS Lambda (Python 3.11) — no VPC attachment; AWS-managed endpoints only |
| Analytics | Amazon Athena |
| Security | KMS (CMKs), IAM least privilege, S3 public access blocks, TLS-only bucket policies |
| Observability | CloudWatch (logs, metrics, alarms, dashboard), X-Ray |
| Notifications | Amazon SNS |
| IaC | Terraform 1.7+, modular composition |
| CI/CD | GitHub Actions (terraform validate + plan, pytest; least-privilege OIDC role) |

---

## Repository Layout

```
music-streaming-data-pipeline/
├── terraform/
│   ├── bootstrap/              # State backend (S3 + DynamoDB + KMS + GitHub OIDC)
│   ├── envs/dev/               # Root Terraform composition for dev environment
│   └── modules/
│       ├── athena/             # Athena workgroup for ad-hoc analytics
│       ├── dynamodb-kpi/       # KPI DynamoDB tables (hourly/daily/monthly + DQ reports)
│       ├── eventbridge/        # EventBridge rule: S3 PutObject → Lambda
│       ├── glue-catalog/       # Glue Data Catalog databases and tables
│       ├── glue-jobs/          # Glue job defs + PySpark (silver/gold) & Python Shell (ddb) scripts
│       ├── iam-roles/          # All IAM roles and policies (least privilege)
│       ├── kms/                # KMS CMKs for S3, DynamoDB, Glue, logs
│       ├── lambda-functions/   # Lambda functions + handler code
│       ├── observability/      # CloudWatch dashboard and metric alarms
│       ├── s3-data-lake/       # S3 buckets (bronze/silver/gold/quarantine/archive/glue-scripts/athena-results/access-logs)
│       └── step-functions/     # Step Functions state machine definition
├── scripts/
│   ├── produce_streams.py      # Simulates streaming data ingestion
│   └── produce_example.sh      # Example script invocations
├── tests/
│   ├── conftest.py                # Pytest config (sys.path, SparkSession fixture, markers)
│   ├── requirements.txt           # Test dependencies (incl. pyspark, chispa)
│   ├── test_event_validator.py    # Validator Lambda tests
│   ├── test_event_router.py       # Event Router Lambda tests
│   ├── test_quarantine_handler.py # Quarantine Handler Lambda tests
│   ├── test_stream_archiver.py    # Stream Archiver Lambda tests
│   ├── test_ddb_etl.py            # DDB-load job tests (partition parse, decimal, poison-partition)
│   ├── test_silver_etl.py         # Silver ETL PySpark tests (requires Java 11+)
│   └── test_gold_etl.py           # Gold ETL PySpark tests (requires Java 11+)
├── data/                       # Sample data (users.csv, songs.csv, streams*.csv)
├── .github/workflows/
│   └── terraform.yml           # CI/CD pipeline (pytest + terraform validate + plan)
├── config/                     # Backend config templates
│   └── backend-dev.hcl.example
└── README.md
```

---

## Setup

### Prerequisites

- AWS Account with admin permissions
- Terraform 1.7+
- Python 3.12+
- GitHub repository (for CI/CD)

### 1. Bootstrap State Backend

Creates the S3 bucket, DynamoDB lock table (or S3 lock), KMS key, and GitHub OIDC provider:

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init && terraform apply
```

### 2. Set GitHub Secrets

| Secret | Description |
|---|---|
| `AWS_TERRAFORM_ROLE_ARN` | From bootstrap output (e.g., `arn:aws:iam::123456789012:role/music-dev-github-actions-terraform`) |
| `AWS_ACCOUNT_ID` | Your AWS account ID |

### 3. Deploy Dev Environment

```bash
cd terraform/envs/dev
cp backend.hcl.example backend.hcl
# Edit backend.hcl with your bucket name
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

### 4. Produce Test Data

Simulate streaming events into the bronze bucket:

```bash
# Upload 50 random events
python scripts/produce_streams.py bronze-108782069549 --count 50

# Upload all 34k events in unpredictable batches
python scripts/produce_streams.py bronze-108782069549 --all

# Burst upload everything at once
python scripts/produce_streams.py bronze-108782069549 --burst
```

### 5. Monitor

- **CloudWatch Dashboard**: `music-dev-pipeline-overview`
- **Step Functions executions**: AWS console → Step Functions → `music-dev-medallion-pipeline`
- **SNS alerts**: Check your email for pipeline notifications

---

## Testing

Lambda handlers and Glue ETL scripts have unit and integration tests. Most tests run without AWS credentials or Java. PySpark tests require Java 11+ and are auto-skipped when absent:

```bash
pip install -r tests/requirements.txt
python -m pytest tests/ -v              # 35 tests (PySpark auto-skipped without Java)
python -m pytest tests/ -m "not spark" # 35 non-Spark tests only
python -m pytest tests/ -m spark        # PySpark tests only (requires Java 11+)
```

Test coverage:
- **event_validator**: CSV parsing, field validation, schema drift detection, S3/DDB interactions, error handling
- **event_router**: S3 event routing, skip logic, SFN execution, execution ID format
- **stream_archiver**: Key-based archiving, bucket listing, manifest skip; fails loud on partial failure so Step Functions can Catch and alert
- **quarantine_handler**: Copy + tag operations, missing key handling, S3 error handling
- **ddb_etl**: S3 partition path parsing, decimal coercion, paginated Parquet read/merge, poison-partition guard (raises RuntimeError on corrupt file), multi-file bad-key accumulation
- **silver_etl** *(PySpark)*: `clean_streams` null-drop, dedup, bad-timestamp handling; `build_curated` inner-join drops unmatched tracks, left-join keeps missing users, genre lowercase/trim, `listen_seconds`, `event_date`; `_extract_run_date` edge cases
- **gold_etl** *(PySpark)*: genre KPI counts, unique listeners, total/avg listen seconds; top-songs ranking, `track_id` tiebreak, n-limit, `genre_date` composite key; top-genres ranking, genre tiebreak, n-limit

---

## Design Decisions

### Why no VPC?
The pipeline does not provision a VPC, subnets, NAT Gateway, VPC endpoints, or Glue connection
objects. All pipeline services — Lambda, Glue, Step Functions, S3, DynamoDB, EventBridge, SNS, SQS,
CloudWatch, Athena — are fully managed and reach each other over AWS-internal networks via
service endpoints. Security is enforced through least-privilege IAM roles and KMS CMKs, not network
perimeter controls. Omitting the VPC eliminates NAT Gateway cost, PrivateLink endpoint cost, and an
entire class of Glue networking failure modes (subnet capacity, ENI limits, DNS resolution) with no
loss of data security.

### Why hardcoded schemas instead of Glue API?
The current approach uses hardcoded expected fields in the Lambda code for reliability and fast
validation. The Glue Catalog still registers the Bronze, Silver, and Gold tables for analytics, but
the validator does not need to call Glue before deciding whether a newly uploaded object is valid.

### Why standard Step Functions vs Express?
Standard workflows are used because the pipeline runs for minutes (Glue jobs take time) and needs exactly-once execution semantics. Express workflows would be cheaper for high-volume short executions but don't guarantee exactly-once.

### Why DynamoDB on-demand instead of provisioned capacity?
The pipeline writes ~462 DynamoDB items per daily run (≈ 114 genre KPIs + 342 top-song rankings + 5 top-genre rankings + 1 DQ report) in a single burst with `BatchWriteItem`. On-demand billing absorbs the burst instantly with no warm-up period. The daily write cost at current volume is under $0.001. Provisioned capacity + auto-scaling is only cheaper at steady, predictable multi-million-WCU-per-day loads. Given that writes happen once per day and read traffic is low-frequency application lookups against small result sets (≤ 5 items per query), on-demand is the correct billing model for this workload and should remain so until daily write volume exceeds several million items or the application read throughput reaches tens of thousands of requests per second. See runbook §8 for the switch-over criteria.

### Medallion architecture benefits
- **Bronze** preserves the original data immutably for reprocessing
- **Silver** provides a clean, analytics-ready layer
- **Gold** delivers pre-computed KPIs for fast application access
- Each layer can be rebuilt independently from the layer below

---

## Outputs

After `terraform apply`, the following outputs are available:

| Output | Description |
|---|---|
| `bronze_bucket_id` | Bronze S3 bucket (raw CSV landing) |
| `silver_bucket_id` | Silver S3 bucket (cleaned Parquet) |
| `gold_bucket_id` | Gold S3 bucket (aggregated Parquet) |
| `quarantine_bucket_id` | Quarantine S3 bucket (invalid data) |
| `dq_table_name` | DQ reports DynamoDB table |
| `step_functions_arn` | State machine ARN |
| `sns_topic_arn` | SNS alert topic |
| `lambda_event_validator_arn` | Validator Lambda function |
| `glue_bronze_database_name` | Glue catalog database for bronze layer |

---

## Querying the KPIs (Sample DynamoDB Queries)

The pipeline serves KPIs from DynamoDB (table names shown for the `music-dev` environment).
`date` and `rank` are DynamoDB reserved words, so the examples alias them with
`--expression-attribute-names`.

**Daily genre KPIs** — `music-dev-genre-kpis-daily` (PK `genre`, SK `date`)

```bash
# All days for a genre
aws dynamodb query --table-name music-dev-genre-kpis-daily \
  --key-condition-expression "genre = :g" \
  --expression-attribute-values '{":g":{"S":"pop"}}'

# A single genre+day
aws dynamodb get-item --table-name music-dev-genre-kpis-daily \
  --key '{"genre":{"S":"pop"},"date":{"S":"2024-06-25"}}'
```

**Top 3 songs per genre per day** — `music-dev-top-songs-by-genre-daily` (PK `genre_date`, SK `rank`)

```bash
aws dynamodb query --table-name music-dev-top-songs-by-genre-daily \
  --key-condition-expression "genre_date = :gd" \
  --expression-attribute-values '{":gd":{"S":"pop#2024-06-25"}}'
```

**Top 5 genres per day** — `music-dev-top-genres-daily` (PK `date`, SK `rank`)

```bash
aws dynamodb query --table-name music-dev-top-genres-daily \
  --key-condition-expression "#d = :date" \
  --expression-attribute-names '{"#d":"date"}' \
  --expression-attribute-values '{":date":{"S":"2024-06-25"}}'
```

**boto3 (Python)** — top 5 genres for a day, ordered by rank:

```python
import boto3
from boto3.dynamodb.conditions import Key

table = boto3.resource("dynamodb").Table("music-dev-top-genres-daily")
resp = table.query(KeyConditionExpression=Key("date").eq("2024-06-25"))
for row in resp["Items"]:
    print(row["rank"], row["genre"], row["listen_count"])
```

---

## Cleanup

```bash
cd terraform/envs/dev
terraform destroy
```

Note: S3 buckets with versioning enabled may need to be emptied manually before `terraform destroy` succeeds.
