# Music Streaming Data Pipeline

A production-ready, event-driven serverless ETL pipeline on AWS that ingests music streaming events at unpredictable intervals, validates and transforms them through a medallion architecture, and serves daily KPIs to downstream applications via DynamoDB and to analysts via Athena.

## Architecture

**Pattern:** Event-driven serverless ETL with medallion layering (Bronze → Silver → Gold).

![Music Streaming ETL Pipeline Architecture](docs/pipeline-architecture-v3.png)

### Diagram Walkthrough

The numbered annotations in the diagram represent the main pipeline flow:

1. **Landing in Bronze:** The producer uploads raw music-streaming CSV files into the Bronze S3 bucket, which acts as the immutable raw landing zone.
2. **Event-driven orchestration:** The S3 object creation event is routed through EventBridge to Step Functions, which starts the ETL workflow.
3. **Silver curation:** The Silver Glue job validates records, applies schema and type casting, removes duplicates, and prepares analytics-friendly curated data.
4. **Silver serving layer:** The curated Silver output is written to Silver S3 and registered in the Glue Data Catalog so downstream query engines can discover it.
5. **Gold + KPI serving:** Downstream Glue jobs build Gold aggregates and load the final KPI-serving dataset into DynamoDB for application access.
6. **Archival path:** The Archiver Lambda stores long-term or replay-safe copies of pipeline artifacts in Archive S3.
7. **Application consumption:** App clients query DynamoDB for fast operational KPI lookups after the ETL outputs have been materialized.
8. **Alerting flow:** CloudWatch alarms trigger the Alert Enricher Lambda, which publishes enriched notifications to SNS for on-call response.

- **Ingestion:** S3 PutObject → EventBridge → Step Functions
- **Bronze:** Raw CSV preserved in original format (immutable source of truth)
- **Silver:** Validated, type-cast, deduplicated, dimension-joined Parquet
- **Gold:** Daily KPI aggregates (genre listen counts, top songs/genre, top genres)
- **Serving:** DynamoDB (hot point lookups) + Athena (analyst SQL over Silver/Gold)
- **Quality:** Quarantine zone for bad records + per-run DQ reports with declarative rules
- **Alerting:** Amazon SNS, tiered topics (critical/warning/info) with email subscriptions

## Tech Stack

| Layer | Service |
|---|---|
| Orchestration | AWS Step Functions (Standard) |
| Transformation | AWS Glue (PySpark + Python Shell), Glue Catalog |
| Storage | Amazon S3 (Parquet + CSV), DynamoDB (on-demand, PITR) |
| Eventing | Amazon EventBridge |
| Compute | AWS Lambda (Python 3.12, ARM64) |
| Analytics | Amazon Athena |
| Security | KMS (CMKs), IAM (PoLP), VPC + PrivateLink endpoints |
| Observability | CloudWatch (logs/metrics/alarms/dashboards), CloudTrail, X-Ray |
| Notifications | Amazon SNS (email subscriptions) |
| IaC | Terraform 1.7+, modular composition |
| CI/CD | GitHub Actions, `terraform test`, pytest (chispa + moto) |

## Status

In design — implementation not yet started. The full architecture and implementation plan (modules, IAM roles, DQ rules, alerting topology, build sequence, verification steps) has been agreed and will be ported into this repository's `docs/` folder as the build begins.

## Repository Layout (planned)

```
terraform/
├── bootstrap/        # State backend (S3 + DynamoDB + KMS)
├── envs/dev/         # Root composition for dev environment
├── modules/          # Reusable modules (networking, kms, s3-data-lake, dynamodb-kpi, glue-*, lambdas-app, step-functions, eventbridge, athena, observability, iam-roles)
└── tests/            # .tftest.hcl files
glue-scripts/         # PySpark + Python Shell jobs
├── silver_curate.py
├── gold_aggregate.py
├── ddb_load.py
├── config/dq_rules.yaml
└── lib/dq.py
lambdas/              # Python source for Lambda functions
├── validator/
├── archiver/
├── event_router/
└── alert_enricher/
.github/workflows/    # CI/CD pipelines
docs/                 # Architecture and design docs
```
