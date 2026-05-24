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
  alarm_description   = "Step Functions execution failures"
  alarm_actions       = [var.sns_topic_arn]

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
  alarm_description   = "Glue job ${each.value} failed"
  alarm_actions       = [var.sns_topic_arn]

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
  alarm_description   = "Lambda function ${each.value} errors"
  alarm_actions       = [var.sns_topic_arn]

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

  dimensions = {
    RuleName = var.eventbridge_rule_name
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-eventbridge-no-invocations" })
}
