locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "observability"
  }

  dashboard_widgets = [
    {
      type = "metric"
      properties = {
        title  = "Pipeline Overview"
        view   = "singleValue"
        region = "us-east-1"
        period = 300
        metrics = [
          ["AWS/States", "ExecutionsStarted", { stat = "Sum", label = "SM Started" }],
          ["AWS/States", "ExecutionsSucceeded", { stat = "Sum", label = "SM Succeeded" }],
          ["AWS/States", "ExecutionsFailed", { stat = "Sum", label = "SM Failed" }],
        ]
      }
    },
    {
      type = "metric"
      properties = {
        title  = "Lambda Functions"
        view   = "singleValue"
        region = "us-east-1"
        period = 300
        metrics = [
          ["AWS/Lambda", "Invocations", "FunctionName", var.lambda_function_names["validator"], { stat = "Sum", label = "Validator Invocations" }],
          ["AWS/Lambda", "Errors", "FunctionName", var.lambda_function_names["validator"], { stat = "Sum", label = "Validator Errors" }],
          ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_names["validator"], { stat = "Average", label = "Validator Duration" }],
          ["AWS/Lambda", "Invocations", "FunctionName", var.lambda_function_names["archiver"], { stat = "Sum", label = "Archiver Invocations" }],
          ["AWS/Lambda", "Errors", "FunctionName", var.lambda_function_names["archiver"], { stat = "Sum", label = "Archiver Errors" }],
          ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_names["archiver"], { stat = "Average", label = "Archiver Duration" }],
          ["AWS/Lambda", "Invocations", "FunctionName", var.lambda_function_names["event_router"], { stat = "Sum", label = "Router Invocations" }],
          ["AWS/Lambda", "Errors", "FunctionName", var.lambda_function_names["event_router"], { stat = "Sum", label = "Router Errors" }],
          ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_names["event_router"], { stat = "Average", label = "Router Duration" }],
        ]
      }
    },
    {
      type = "metric"
      properties = {
        title  = "Glue Jobs"
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
    {
      type = "metric"
      properties = {
        title  = "S3 Events (Bronze)"
        view   = "timeSeries"
        region = "us-east-1"
        period = 300
        metrics = [
          ["AWS/S3", "PutRequests", "BucketName", var.s3_bronze_bucket_name, { stat = "Sum" }],
        ]
        yAxis = { left = { min = 0, showUnits = false } }
      }
    },
  ]
}
