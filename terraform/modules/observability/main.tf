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
