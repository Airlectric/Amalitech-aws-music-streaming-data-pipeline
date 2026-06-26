locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "observability"
  }

  dashboard_widgets = [
    # ── Row 1: Step Functions ─────────────────────────────────────────────────
    {
      type   = "metric"
      width  = 12
      height = 6
      properties = {
        title  = "Step Functions – Executions"
        view   = "singleValue"
        region = "us-east-1"
        period = 300
        metrics = [
          ["AWS/States", "ExecutionsStarted", "StateMachineArn", var.step_functions_state_machine_arn, { stat = "Sum", label = "Started" }],
          ["AWS/States", "ExecutionsSucceeded", "StateMachineArn", var.step_functions_state_machine_arn, { stat = "Sum", label = "Succeeded" }],
          ["AWS/States", "ExecutionsFailed", "StateMachineArn", var.step_functions_state_machine_arn, { stat = "Sum", label = "Failed" }],
          ["AWS/States", "ExecutionsTimedOut", "StateMachineArn", var.step_functions_state_machine_arn, { stat = "Sum", label = "TimedOut" }],
        ]
      }
    },
    # ── Row 1: DLQ depth ─────────────────────────────────────────────────────
    {
      type   = "metric"
      width  = 12
      height = 6
      properties = {
        title  = "Pipeline DLQ – Visible Messages"
        view   = "timeSeries"
        region = "us-east-1"
        period = 60
        metrics = [
          ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.dlq_name, { stat = "Maximum", label = "DLQ Depth" }],
        ]
        yAxis = { left = { min = 0, showUnits = false } }
        annotations = {
          horizontal = [{ value = 1, label = "Alert threshold", color = "#ff6961" }]
        }
      }
    },
    # ── Row 2: Lambda invocations / errors / duration ─────────────────────────
    {
      type   = "metric"
      width  = 12
      height = 6
      properties = {
        title  = "Lambda – Invocations and Errors"
        view   = "singleValue"
        region = "us-east-1"
        period = 300
        metrics = [
          ["AWS/Lambda", "Invocations", "FunctionName", var.lambda_function_names["validator"], { stat = "Sum", label = "Validator Invocations" }],
          ["AWS/Lambda", "Errors", "FunctionName", var.lambda_function_names["validator"], { stat = "Sum", label = "Validator Errors" }],
          ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_names["validator"], { stat = "Average", label = "Validator Duration (ms)" }],
          ["AWS/Lambda", "Invocations", "FunctionName", var.lambda_function_names["archiver"], { stat = "Sum", label = "Archiver Invocations" }],
          ["AWS/Lambda", "Errors", "FunctionName", var.lambda_function_names["archiver"], { stat = "Sum", label = "Archiver Errors" }],
          ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_names["archiver"], { stat = "Average", label = "Archiver Duration (ms)" }],
          ["AWS/Lambda", "Invocations", "FunctionName", var.lambda_function_names["event_router"], { stat = "Sum", label = "Router Invocations" }],
          ["AWS/Lambda", "Errors", "FunctionName", var.lambda_function_names["event_router"], { stat = "Sum", label = "Router Errors" }],
          ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_names["event_router"], { stat = "Average", label = "Router Duration (ms)" }],
        ]
      }
    },
    # ── Row 2: Glue jobs ─────────────────────────────────────────────────────
    {
      type   = "metric"
      width  = 12
      height = 6
      properties = {
        title  = "Glue Jobs – Runs"
        view   = "singleValue"
        region = "us-east-1"
        period = 300
        metrics = [
          ["AWS/Glue", "SuccessfulRuns", "JobName", var.glue_job_names["silver"], { stat = "Sum", label = "Silver Success" }],
          ["AWS/Glue", "FailedRuns", "JobName", var.glue_job_names["silver"], { stat = "Sum", label = "Silver Failed" }],
          ["AWS/Glue", "SuccessfulRuns", "JobName", var.glue_job_names["gold"], { stat = "Sum", label = "Gold Success" }],
          ["AWS/Glue", "FailedRuns", "JobName", var.glue_job_names["gold"], { stat = "Sum", label = "Gold Failed" }],
          ["AWS/Glue", "SuccessfulRuns", "JobName", var.glue_job_names["ddb"], { stat = "Sum", label = "DDB Success" }],
          ["AWS/Glue", "FailedRuns", "JobName", var.glue_job_names["ddb"], { stat = "Sum", label = "DDB Failed" }],
        ]
      }
    },
    # ── Row 3: DQ drop-rate (Silver ETL custom metric) ────────────────────────
    {
      type   = "metric"
      width  = 12
      height = 6
      properties = {
        title  = "Silver ETL – DQ Drop Rate (%)"
        view   = "timeSeries"
        region = "us-east-1"
        period = 300
        metrics = [
          ["MusicPipeline/DQ", "DropRatePct", "Job", "silver_etl", { stat = "Maximum", label = "Drop Rate %" }],
        ]
        yAxis = { left = { min = 0, max = 100, showUnits = false } }
        annotations = {
          horizontal = [{ value = 10, label = "Alert threshold (10%)", color = "#ff6961" }]
        }
      }
    },
    # ── Row 3: EventBridge ingest activity ───────────────────────────────────
    {
      type   = "metric"
      width  = 12
      height = 6
      properties = {
        title  = "EventBridge – Rule Invocations"
        view   = "timeSeries"
        region = "us-east-1"
        period = 300
        metrics = [
          ["AWS/Events", "Invocations", "RuleName", var.eventbridge_rule_name, { stat = "Sum", label = "Invocations" }],
          ["AWS/Events", "FailedInvocations", "RuleName", var.eventbridge_rule_name, { stat = "Sum", label = "Failed" }],
        ]
        yAxis = { left = { min = 0, showUnits = false } }
      }
    },
    # ── Row 4: Alarm state panel ──────────────────────────────────────────────
    {
      type   = "alarm"
      width  = 24
      height = 6
      properties = {
        title = "Alarm States"
        alarms = [
          "arn:aws:cloudwatch:us-east-1:${data.aws_caller_identity.current.account_id}:alarm:${var.environment}-step-functions-failed",
          "arn:aws:cloudwatch:us-east-1:${data.aws_caller_identity.current.account_id}:alarm:${var.environment}-pipeline-dlq-depth",
          "arn:aws:cloudwatch:us-east-1:${data.aws_caller_identity.current.account_id}:alarm:${var.environment}-pipeline-sla-breach",
          "arn:aws:cloudwatch:us-east-1:${data.aws_caller_identity.current.account_id}:alarm:${var.environment}-silver-dq-drop-rate-high",
        ]
      }
    },
  ]
}
