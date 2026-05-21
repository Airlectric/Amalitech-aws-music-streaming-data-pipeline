# Music Streaming Data Pipeline

A production-ready, event-driven serverless ETL pipeline on AWS that ingests music streaming events at unpredictable intervals, validates and transforms them through a medallion architecture, and serves daily KPIs to downstream applications via DynamoDB and to analysts via Athena.

## Architecture

**Pattern:** Event-driven serverless ETL with medallion layering (Bronze → Silver → Gold).

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
