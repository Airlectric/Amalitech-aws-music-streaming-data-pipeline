# Music Streaming Data Pipeline

A production-ready, event-driven serverless ETL pipeline on AWS that ingests music streaming events, validates them, transforms them through a medallion architecture (Bronze → Silver → Gold), and serves KPIs via DynamoDB and Athena.

---

## Architecture

```
                  ┌──────────────┐
                  │  Producer    │  (scripts/produce_streams.py)
                  └──────┬───────┘
                         │ CSV → bronze-format JSON
                         ▼
              ┌──────────────────────┐
              │   Bronze S3 Bucket   │  Raw JSON landing zone
              └──────────┬───────────┘
                         │ S3 PutObject event
                         ▼
              ┌──────────────────────┐
              │    EventBridge       │  Rule: dev-bronze-s3-put
              └──────────┬───────────┘
                         │ Invokes
                         ▼
              ┌──────────────────────┐
              │   Event Router Lambda │  Routes to Step Functions
              └──────────┬───────────┘
                         │ StartExecution
                         ▼
              ┌─────────────────────────────────────────────┐
              │        Step Functions State Machine         │
              │         dev-medallion-pipeline              │
              │                                             │
              │  ValidateEvent → CheckValidation            │
              │       │ valid          │ invalid            │
              │       ▼                ▼                    │
              │  RunSilverETL    QuarantineFile             │
              │       ▼                ▼                    │
              │  RunGoldETL     NotifyValidationFailure     │
              │       ▼                                     │
              │  RunDDBETL                                  │
              │       ▼                                     │
              │  ArchiveFiles                               │
              │                                             │
              │  Any failure → NotifyFailure (SNS)          │
              └─────────────────────────────────────────────┘
                         │
          ┌──────────────┼──────────────────┐
          ▼              ▼                  ▼
    ┌──────────┐  ┌──────────┐  ┌──────────────────┐
    │  Silver  │  │   Gold   │  │   DynamoDB KPI   │
    │   S3     │  │   S3     │  │   (hourly/daily/  │
    │  Parquet │  │  Parquet │  │    monthly)       │
    └──────────┘  └──────────┘  └──────────────────┘
                         │
          ┌──────────────┴──────────────┐
          ▼                             ▼
    ┌──────────┐               ┌──────────────────┐
    │  Athena  │               │  Archive S3      │
    │  SQL     │               │  (long-term)     │
    └──────────┘               └──────────────────┘
```

### Data Flow

| Layer  | Format  | Description                                       |
|--------|---------|---------------------------------------------------|
| Bronze | JSON    | Raw streaming events, immutable source of truth   |
| Silver | Parquet | Cleaned, typed, deduplicated, dimension-enriched  |
| Gold   | Parquet | Aggregated KPIs (listens by genre, top songs, etc)|
| DDB    | DynamoDB| Hot-path KPI serving for application consumption  |

### Pipeline Stages

1. **Ingestion** — S3 PutObject on bronze bucket → EventBridge → Event Router Lambda → Step Functions
2. **Validation** — Validator Lambda checks required fields, detects schema drift, writes DQ reports to DynamoDB
3. **Quarantine** — Invalid files are copied to quarantine bucket and tagged; SNS notification is sent
4. **Silver ETL** — Glue PySpark job cleanses, deduplicates, type-casts, and partitions data
5. **Gold ETL** — Glue PySpark job aggregates daily KPIs (genre counts, top songs, top genres)
6. **DDB ETL** — Glue PySpark job loads gold aggregates into DynamoDB tables for low-latency queries
7. **Archive** — Archiver Lambda moves processed bronze files to long-term archive (Glacier Deep Archive)
8. **Alerting** — SNS notifications on validation failures or pipeline errors

---

## Tech Stack

| Layer | Service |
|---|---|
| Orchestration | AWS Step Functions (Standard) |
| Transformation | AWS Glue (PySpark), Glue Data Catalog |
| Storage | Amazon S3 (JSON, Parquet), DynamoDB (on-demand) |
| Eventing | Amazon EventBridge |
| Compute | AWS Lambda (Python 3.11, VPC-attached) |
| Analytics | Amazon Athena |
| Security | KMS (CMKs), IAM (least privilege), VPC + PrivateLink endpoints |
| Observability | CloudWatch (logs, metrics, alarms, dashboard), X-Ray |
| Notifications | Amazon SNS |
| IaC | Terraform 1.7+, modular composition |
| CI/CD | GitHub Actions (terraform validate + plan, pytest) |

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
│       ├── glue-jobs/          # Glue ETL job definitions + PySpark scripts
│       ├── iam-roles/          # All IAM roles and policies (least privilege)
│       ├── kms/                # KMS CMKs for S3, DynamoDB, Glue, logs
│       ├── lambda-functions/   # Lambda functions + handler code
│       ├── networking/         # VPC, subnets, security groups, VPC endpoints
│       ├── observability/      # CloudWatch dashboard and metric alarms
│       ├── s3-data-lake/       # S3 buckets (bronze/silver/gold/quarantine/archive/glue-scripts/athena-results/access-logs)
│       └── step-functions/     # Step Functions state machine definition
├── scripts/
│   ├── produce_streams.py      # Simulates streaming data ingestion
│   └── produce_example.sh      # Example script invocations
├── tests/
│   ├── conftest.py             # Pytest configuration (sys.path, fixtures)
│   ├── requirements.txt        # Test dependencies
│   ├── test_event_validator.py # Validator Lambda tests (30 tests)
│   ├── test_event_router.py    # Event Router Lambda tests (6 tests)
│   ├── test_quarantine_handler.py # Quarantine Handler Lambda tests (4 tests)
│   └── test_stream_archiver.py # Stream Archiver Lambda tests (5 tests)
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
| `AWS_TERRAFORM_ROLE_ARN` | From bootstrap output (e.g., `arn:aws:iam::123456789012:role/dev-github-actions-terraform`) |
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

- **CloudWatch Dashboard**: `dev-pipeline-overview`
- **Step Functions executions**: AWS console → Step Functions → `dev-medallion-pipeline`
- **SNS alerts**: Check your email for pipeline notifications

---

## Testing

All Lambda handlers have unit tests using `unittest.mock` (no AWS credentials required):

```bash
pip install -r tests/requirements.txt
python -m pytest tests/ -v
```

Test coverage:
- **event_validator**: JSON parsing, field validation, schema drift detection, S3/DDB interactions, error handling
- **event_router**: S3 event routing, skip logic, SFn execution, execution ID format
- **stream_archiver**: Key-based archiving, bucket listing, manifest skip, partial failure handling
- **quarantine_handler**: Copy + tag operations, missing key handling, S3 error handling

---

## Design Decisions

### Why VPC-attached Lambdas?
The validator, quarantiner, and archiver Lambdas run inside a VPC with VPC endpoints (S3 gateway, DynamoDB gateway, Glue/STS/KMS interface endpoints) to avoid traversing the public internet. The event router is intentionally VPC-external because it only calls Step Functions via the AWS API.

### Why hardcoded schemas instead of Glue API?
The initial validator called `glue:GetTable` to fetch the expected schema dynamically, but Glue API calls timed out from within the VPC (Glue interface endpoint connectivity issue). The current approach uses hardcoded expected fields in the Lambda code for reliability.

### Why standard Step Functions vs Express?
Standard workflows are used because the pipeline runs for minutes (Glue jobs take time) and needs exactly-once execution semantics. Express workflows would be cheaper for high-volume short executions but don't guarantee exactly-once.

### Medallion architecture benefits
- **Bronze** preserves the original data immutably for reprocessing
- **Silver** provides a clean, analytics-ready layer
- **Gold** delivers pre-computed KPIs for fast application access
- Each layer can be rebuilt independently from the layer below

---

## VPC Endpoints

The pipeline uses a private VPC with the following VPC endpoints:

**Gateway Endpoints:**
- S3 (route table association in private subnet)
- DynamoDB (route table association in private subnet)

**Interface Endpoints:**
- Glue
- KMS
- SNS
- CloudWatch Logs
- EC2 (for SSM)
- STS
- Step Functions
- ECR (API + DKR)

---

## Outputs

After `terraform apply`, the following outputs are available:

| Output | Description |
|---|---|
| `bronze_bucket_id` | Bronze S3 bucket (raw JSON landing) |
| `silver_bucket_id` | Silver S3 bucket (cleaned Parquet) |
| `gold_bucket_id` | Gold S3 bucket (aggregated Parquet) |
| `quarantine_bucket_id` | Quarantine S3 bucket (invalid data) |
| `dq_table_name` | DQ reports DynamoDB table |
| `step_functions_arn` | State machine ARN |
| `sns_topic_arn` | SNS alert topic |
| `lambda_event_validator_arn` | Validator Lambda function |
| `vpc_id` | VPC ID |
| `glue_bronze_database_name` | Glue catalog database for bronze layer |

---

## Cleanup

```bash
cd terraform/envs/dev
terraform destroy
```

Note: S3 buckets with versioning enabled may need to be emptied manually before `terraform destroy` succeeds.
