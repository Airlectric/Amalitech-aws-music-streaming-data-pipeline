# ────────────────────────────────────────────
# SCRIPT UPLOADS
# ────────────────────────────────────────────
resource "aws_s3_object" "silver_etl_script" {
  bucket  = var.glue_scripts_bucket_id
  key     = "${local.script_key}/silver_etl.py"
  source  = "${path.module}/scripts/silver_etl.py"
  etag    = filemd5("${path.module}/scripts/silver_etl.py")
}

resource "aws_s3_object" "gold_etl_script" {
  bucket  = var.glue_scripts_bucket_id
  key     = "${local.script_key}/gold_etl.py"
  source  = "${path.module}/scripts/gold_etl.py"
  etag    = filemd5("${path.module}/scripts/gold_etl.py")
}

resource "aws_s3_object" "ddb_etl_script" {
  bucket  = var.glue_scripts_bucket_id
  key     = "${local.script_key}/ddb_etl.py"
  source  = "${path.module}/scripts/ddb_etl.py"
  etag    = filemd5("${path.module}/scripts/ddb_etl.py")
}

# ────────────────────────────────────────────
# SILVER ETL: bronze JSON → silver Parquet
# ────────────────────────────────────────────
resource "aws_glue_job" "silver_etl" {
  name     = "${var.environment}-silver-etl"
  role_arn = var.glue_silver_role_arn

  glue_version = "4.0"
  worker_type   = "G.1X"
  number_of_workers = var.worker_count

  max_retries = var.max_retries
  timeout     = var.timeout_minutes

  command {
    name            = "glueetl"
    script_location = "s3://${var.glue_scripts_bucket_id}/${local.script_key}/silver_etl.py"
    python_version  = "3.9"
  }

  default_arguments = {
    "--job-language"          = "python"
    "--job-bookmark-option"   = "job-bookmark-enable"
    "--enable-spark-ui"       = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"        = "true"
    "--TempDir"               = "s3://${var.glue_scripts_bucket_id}/temp/${var.environment}/silver/"
    "--extra-py-files"        = ""
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
  name     = "${var.environment}-gold-etl"
  role_arn = var.glue_gold_role_arn

  glue_version = "4.0"
  worker_type   = "G.1X"
  number_of_workers = var.worker_count

  max_retries = var.max_retries
  timeout     = var.timeout_minutes

  command {
    name            = "glueetl"
    script_location = "s3://${var.glue_scripts_bucket_id}/${local.script_key}/gold_etl.py"
    python_version  = "3.9"
  }

  default_arguments = {
    "--job-language"          = "python"
    "--job-bookmark-option"   = "job-bookmark-enable"
    "--enable-spark-ui"       = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"        = "true"
    "--TempDir"               = "s3://${var.glue_scripts_bucket_id}/temp/${var.environment}/gold/"
    "--extra-py-files"        = ""
  }

  execution_property {
    max_concurrent_runs = 1
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-gold-etl" })
}

# ────────────────────────────────────────────
# DDB ETL: gold Parquet → DynamoDB KPI tables
# ────────────────────────────────────────────
resource "aws_glue_job" "ddb_etl" {
  name     = "${var.environment}-ddb-etl"
  role_arn = var.glue_ddb_role_arn

  glue_version = "4.0"
  worker_type   = "G.1X"
  number_of_workers = var.worker_count

  max_retries = var.max_retries
  timeout     = var.timeout_minutes

  command {
    name            = "glueetl"
    script_location = "s3://${var.glue_scripts_bucket_id}/${local.script_key}/ddb_etl.py"
    python_version  = "3.9"
  }

  default_arguments = {
    "--job-language"          = "python"
    "--job-bookmark-option"   = "job-bookmark-disable"
    "--enable-spark-ui"       = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"        = "true"
    "--TempDir"               = "s3://${var.glue_scripts_bucket_id}/temp/${var.environment}/ddb/"
    "--extra-py-files"        = ""

    "--dynamodb.splits"       = "10"
    "--dynamodb.throughput.write.percent" = "0.5"
  }

  execution_property {
    max_concurrent_runs = 1
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-ddb-etl" })
}
