data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_cloudwatch_dashboard" "pipeline" {
  dashboard_name = "${var.environment}-pipeline-overview"
  dashboard_body = jsonencode({
    widgets = local.dashboard_widgets
  })
}

resource "aws_cloudwatch_metric_alarm" "step_functions_failed" {
  alarm_name          = "${var.environment}-step-functions-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  treat_missing_data  = "notBreaching"
  alarm_description   = "Step Functions execution failures"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    StateMachineArn = var.step_functions_state_machine_arn
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-step-functions-failed" })
}

resource "aws_cloudwatch_metric_alarm" "glue_job_failed" {
  for_each = var.glue_job_names

  alarm_name          = "${var.environment}-glue-${each.value}-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FailedRuns"
  namespace           = "AWS/Glue"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  treat_missing_data  = "notBreaching"
  alarm_description   = "Glue job ${each.value} failed"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    JobName = each.value
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-glue-${each.value}-failed" })
}

resource "aws_cloudwatch_metric_alarm" "lambda_error" {
  for_each = var.lambda_function_names

  alarm_name          = "${var.environment}-lambda-${each.value}-error"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  treat_missing_data  = "notBreaching"
  alarm_description   = "Lambda function ${each.value} errors"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    FunctionName = each.value
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-lambda-${each.value}-error" })
}

resource "aws_cloudwatch_metric_alarm" "eventbridge_no_invocations" {
  alarm_name          = "${var.environment}-eventbridge-no-invocations"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Invocations"
  namespace           = "AWS/Events"
  period              = "86400"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "No EventBridge invocations in the last 24 hours"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    RuleName = var.eventbridge_rule_name
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-eventbridge-no-invocations" })
}

# ---------------------------------------------------------------------------
# DLQ depth — fire immediately when any event lands in the dead-letter queue.
# Even one message means a trigger event was dropped; needs manual replay.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  alarm_name          = "${var.environment}-pipeline-dlq-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "0"
  treat_missing_data  = "notBreaching"
  alarm_description   = "Messages in pipeline DLQ — at least one S3 trigger event was not processed. Inspect the queue and replay manually."
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    QueueName = var.dlq_name
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-pipeline-dlq-depth" })
}

# ---------------------------------------------------------------------------
# SLA / data-freshness — fire when the pipeline has not completed a successful
# execution within the last 25 hours (one day + 1 hour buffer).
# treat_missing_data = "breaching" so an entirely stalled pipeline also alarms.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "pipeline_sla" {
  alarm_name          = "${var.environment}-pipeline-sla-breach"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ExecutionsSucceeded"
  namespace           = "AWS/States"
  period              = "90000"
  statistic           = "Sum"
  threshold           = "1"
  treat_missing_data  = "breaching"
  alarm_description   = "No successful pipeline execution in the last 25 hours — downstream KPIs may be stale."
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    StateMachineArn = var.step_functions_state_machine_arn
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-pipeline-sla-breach" })
}

# ---------------------------------------------------------------------------
# DQ drop-rate — fire when silver_etl drops more than 10 % of incoming rows.
# DropRatePct is emitted by silver_etl.py with dimension Job=silver_etl only
# (not RunDate) so this alarm can track it across every run.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "dq_drop_rate" {
  alarm_name          = "${var.environment}-silver-dq-drop-rate-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "DropRatePct"
  namespace           = "MusicPipeline/DQ"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "10"
  treat_missing_data  = "notBreaching"
  alarm_description   = "Silver ETL dropped more than 10 % of raw rows — check reference-data coverage and upstream CSV quality."
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    Job = "silver_etl"
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-silver-dq-drop-rate-high" })
}

# ---------------------------------------------------------------------------
# DDB load count alarms — fire when any KPI table load produces zero rows.
# GenreKpisLoaded, TopSongsLoaded, TopGenresLoaded are emitted by ddb_etl
# with dimension Job=ddb_etl (no RunDate) for alarm-friendly tracking.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "ddb_genre_kpis_zero" {
  alarm_name          = "${var.environment}-ddb-genre-kpis-zero"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "GenreKpisLoaded"
  namespace           = "MusicPipeline/DQ"
  period              = "86400"
  statistic           = "Sum"
  threshold           = "1"
  treat_missing_data  = "notBreaching"
  alarm_description   = "DDB ETL loaded zero genre KPI rows — gold_etl may have produced an empty partition."
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    Job = "ddb_etl"
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-ddb-genre-kpis-zero" })
}

resource "aws_cloudwatch_metric_alarm" "ddb_top_songs_zero" {
  alarm_name          = "${var.environment}-ddb-top-songs-zero"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "TopSongsLoaded"
  namespace           = "MusicPipeline/DQ"
  period              = "86400"
  statistic           = "Sum"
  threshold           = "1"
  treat_missing_data  = "notBreaching"
  alarm_description   = "DDB ETL loaded zero top-songs rows — gold_etl may have produced an empty partition."
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    Job = "ddb_etl"
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-ddb-top-songs-zero" })
}

resource "aws_cloudwatch_metric_alarm" "ddb_top_genres_zero" {
  alarm_name          = "${var.environment}-ddb-top-genres-zero"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "TopGenresLoaded"
  namespace           = "MusicPipeline/DQ"
  period              = "86400"
  statistic           = "Sum"
  threshold           = "1"
  treat_missing_data  = "notBreaching"
  alarm_description   = "DDB ETL loaded zero top-genres rows — gold_etl may have produced an empty partition."
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    Job = "ddb_etl"
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-ddb-top-genres-zero" })
}

# ────────────────────────────────────────────────────────────────────────────
# CLOUDTRAIL — audit trail for S3, Glue, Lambda, and Step Functions API calls
# ────────────────────────────────────────────────────────────────────────────
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket        = "${var.environment}-pipeline-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = false

  tags = merge(local.common_tags, { Name = "${var.environment}-cloudtrail-logs" })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket                  = aws_s3_bucket.cloudtrail_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter { prefix = "" }

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
    ]
  })
}

resource "aws_cloudtrail" "pipeline" {
  name                          = "${var.environment}-pipeline-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true
  kms_key_id                    = var.kms_key_arn

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::${var.s3_bronze_bucket_name}/"]
    }
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-pipeline-trail" })

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]
}
