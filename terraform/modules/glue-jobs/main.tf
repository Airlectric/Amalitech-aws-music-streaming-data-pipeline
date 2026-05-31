# ────────────────────────────────────────────
# VPC CONNECTION
# A NETWORK connection makes the Glue jobs run inside the private subnet so all
# traffic reaches AWS services via the VPC gateway/interface endpoints.
# ────────────────────────────────────────────
resource "aws_glue_connection" "network" {
  name            = "${var.environment}-glue-network"
  connection_type = "NETWORK"

  physical_connection_requirements {
    availability_zone      = var.glue_subnet_az
    subnet_id              = var.private_subnet_id
    security_group_id_list = [var.security_group_glue_id]
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-glue-network" })
}

# ────────────────────────────────────────────
# SCRIPT UPLOADS
# ────────────────────────────────────────────
resource "aws_s3_object" "silver_etl_script" {
  bucket = var.glue_scripts_bucket_id
  key    = "${local.script_key}/silver_etl.py"
  source = "${path.module}/scripts/silver_etl.py"
  etag   = filemd5("${path.module}/scripts/silver_etl.py")
}

resource "aws_s3_object" "gold_etl_script" {
  bucket = var.glue_scripts_bucket_id
  key    = "${local.script_key}/gold_etl.py"
  source = "${path.module}/scripts/gold_etl.py"
  etag   = filemd5("${path.module}/scripts/gold_etl.py")
}

resource "aws_s3_object" "ddb_etl_script" {
  bucket = var.glue_scripts_bucket_id
  key    = "${local.script_key}/ddb_etl.py"
  source = "${path.module}/scripts/ddb_etl.py"
  etag   = filemd5("${path.module}/scripts/ddb_etl.py")
}

# ────────────────────────────────────────────
# SILVER ETL: bronze JSON → silver Parquet
# ────────────────────────────────────────────
resource "aws_glue_job" "silver_etl" {
  name        = "${var.environment}-silver-etl"
  role_arn    = var.glue_silver_role_arn
  connections = [aws_glue_connection.network.name]

  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = var.worker_count

  max_retries = var.max_retries
  timeout     = var.timeout_minutes

  command {
    name            = "glueetl"
    script_location = "s3://${var.glue_scripts_bucket_id}/${local.script_key}/silver_etl.py"
    python_version  = "3.9"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-disable" # orchestrator passes the run partition explicitly and the job overwrites it; bookmarks would be dead config
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"                   = "true"
    "--TempDir"                          = "s3://${var.glue_scripts_bucket_id}/temp/${var.environment}/silver/"
  }

  execution_property {
    max_concurrent_runs = 1
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-silver-etl" })
}

# ────────────────────────────────────────────
# GOLD ETL: silver Parquet → gold aggregated Parquet
# ────────────────────────────────────────────
resource "aws_glue_job" "gold_etl" {
  name        = "${var.environment}-gold-etl"
  role_arn    = var.glue_gold_role_arn
  connections = [aws_glue_connection.network.name]

  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = var.worker_count

  max_retries = var.max_retries
  timeout     = var.timeout_minutes

  command {
    name            = "glueetl"
    script_location = "s3://${var.glue_scripts_bucket_id}/${local.script_key}/gold_etl.py"
    python_version  = "3.9"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-disable" # orchestrator passes the run partition explicitly and the job overwrites it; bookmarks would be dead config
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"                   = "true"
    "--TempDir"                          = "s3://${var.glue_scripts_bucket_id}/temp/${var.environment}/gold/"
  }

  execution_property {
    max_concurrent_runs = 1
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-gold-etl" })
}

# ────────────────────────────────────────────
# DDB LOAD: gold Parquet → DynamoDB KPI tables
#
# This is a Python Shell job (NOT Spark): the load is a lightweight pyarrow +
# boto3 batch-write of small daily aggregates, so Spark workers add only cold-start
# latency and DPU cost with no benefit. Running it as `pythonshell` at 1 DPU also
# satisfies the brief's requirement to use "PySpark and Python Shell jobs".
#
# It is intentionally NOT attached to the Glue NETWORK connection: it installs
# pyarrow via --additional-python-modules (needs PyPI), and the private subnet has
# no NAT/internet egress. It only reaches S3 and DynamoDB over TLS, so running it
# outside the VPC is both necessary and sufficient.
# ────────────────────────────────────────────
resource "aws_glue_job" "ddb_etl" {
  name     = "${var.environment}-ddb-etl"
  role_arn = var.glue_ddb_role_arn

  # Python Shell jobs are sized with max_capacity (0.0625 or 1.0 DPU);
  # worker_type / number_of_workers / glue_version are Spark-only and omitted here.
  max_capacity = 1.0

  max_retries = var.max_retries
  timeout     = var.timeout_minutes

  command {
    name            = "pythonshell"
    script_location = "s3://${var.glue_scripts_bucket_id}/${local.script_key}/ddb_etl.py"
    python_version  = "3.9"
  }

  default_arguments = {
    "--job-language"   = "python"
    "--enable-metrics" = "true"
    # pyarrow is not guaranteed in the Python Shell image; pull it explicitly.
    "--additional-python-modules" = "pyarrow"
  }

  execution_property {
    # Serialize runs: each pipeline execution loads one run_date partition; concurrent
    # runs would race on the same DynamoDB items. Intentional, not a throughput bug.
    max_concurrent_runs = 1
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-ddb-etl" })
}
