# ────────────────────────────────────────────
# DEPLOYMENT PACKAGES
# ────────────────────────────────────────────
data "archive_file" "validator" {
  type        = "zip"
  source_file = "${path.module}/handlers/event_validator.py"
  output_path = "${path.module}/builds/event_validator.zip"
}

data "archive_file" "archiver" {
  type        = "zip"
  source_file = "${path.module}/handlers/stream_archiver.py"
  output_path = "${path.module}/builds/stream_archiver.zip"
}

data "archive_file" "event_router" {
  type        = "zip"
  source_file = "${path.module}/handlers/event_router.py"
  output_path = "${path.module}/builds/event_router.zip"
}

# ────────────────────────────────────────────
# EVENT VALIDATOR
# ────────────────────────────────────────────
resource "aws_lambda_function" "event_validator" {
  filename         = data.archive_file.validator.output_path
  source_code_hash = data.archive_file.validator.output_base64sha256
  function_name    = "${var.environment}-event-validator"
  role             = var.lambda_validator_role_arn
  handler          = "event_validator.lambda_handler"
  runtime          = "python3.11"
  timeout          = 90
  memory_size      = 256

  # This function only calls AWS service APIs. Keeping it outside the VPC avoids
  # ENI startup and endpoint routing delays during the validation step.

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      BRONZE_BUCKET = var.bronze_bucket_id
      DQ_TABLE_NAME = var.dq_table_name
    }
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-event-validator" })
}

# ────────────────────────────────────────────
# QUARANTINE HANDLER
# ────────────────────────────────────────────
data "archive_file" "quarantiner" {
  type        = "zip"
  source_file = "${path.module}/handlers/quarantine_handler.py"
  output_path = "${path.module}/builds/quarantine_handler.zip"
}

resource "aws_lambda_function" "quarantine_handler" {
  filename         = data.archive_file.quarantiner.output_path
  source_code_hash = data.archive_file.quarantiner.output_base64sha256
  function_name    = "${var.environment}-quarantine-handler"
  role             = var.lambda_quarantiner_role_arn
  handler          = "quarantine_handler.lambda_handler"
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 256

  # This function only calls AWS service APIs. Keeping it outside the VPC avoids
  # ENI startup and endpoint routing delays during the remediation step.

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      BRONZE_BUCKET     = var.bronze_bucket_id
      QUARANTINE_BUCKET = var.quarantine_bucket_id
    }
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-quarantine-handler" })
}

# ────────────────────────────────────────────
# STREAM ARCHIVER
# ────────────────────────────────────────────
resource "aws_lambda_function" "stream_archiver" {
  filename         = data.archive_file.archiver.output_path
  source_code_hash = data.archive_file.archiver.output_base64sha256
  function_name    = "${var.environment}-stream-archiver"
  role             = var.lambda_archiver_role_arn
  handler          = "stream_archiver.lambda_handler"
  runtime          = "python3.11"
  timeout          = 300
  memory_size      = 256

  # This function only calls AWS service APIs. Keeping it outside the VPC avoids
  # ENI startup and endpoint routing delays during the archive step.

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      BRONZE_BUCKET  = var.bronze_bucket_id
      ARCHIVE_BUCKET = var.archive_bucket_id
    }
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-stream-archiver" })
}

# ────────────────────────────────────────────
# EVENT ROUTER
# ────────────────────────────────────────────
resource "aws_lambda_function" "event_router" {
  filename         = data.archive_file.event_router.output_path
  source_code_hash = data.archive_file.event_router.output_base64sha256
  function_name    = "${var.environment}-event-router"
  role             = var.lambda_event_router_role_arn
  handler          = "event_router.lambda_handler"
  runtime          = "python3.11"
  timeout          = 30
  memory_size      = 128

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      STATE_MACHINE_ARN = local.step_functions_arn
    }
  }

  # Async invocations (from EventBridge) that still fail after retries are captured
  # in the DLQ instead of being silently dropped.
  dead_letter_config {
    target_arn = aws_sqs_queue.pipeline_dlq.arn
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-event-router" })
}

# Bound the async retry behaviour for the router (EventBridge -> Lambda is async).
resource "aws_lambda_function_event_invoke_config" "event_router" {
  function_name                = aws_lambda_function.event_router.function_name
  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 3600
}

# ────────────────────────────────────────────
# LAMBDA PERMISSIONS
# ────────────────────────────────────────────
resource "aws_lambda_permission" "event_router_from_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.event_router.function_name
  principal     = "events.amazonaws.com"
  source_arn    = "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/${var.environment}-bronze-s3-put"
}

# ────────────────────────────────────────────
# PIPELINE DEAD-LETTER QUEUE
# Captures (a) EventBridge -> router deliveries that exhaust retries and
# (b) router async-invoke failures, so no trigger event is lost.
# ────────────────────────────────────────────
resource "aws_sqs_queue" "pipeline_dlq" {
  name                      = "${var.environment}-pipeline-dlq"
  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = true    # encryption at rest (SSE-SQS)

  tags = merge(local.common_tags, { Name = "${var.environment}-pipeline-dlq" })
}

# Allow the EventBridge rule to deliver failed events to the DLQ (target dead-letter).
resource "aws_sqs_queue_policy" "pipeline_dlq" {
  queue_url = aws_sqs_queue.pipeline_dlq.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgeDLQ"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.pipeline_dlq.arn
      Condition = {
        ArnEquals = {
          "aws:SourceArn" = "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/${var.environment}-bronze-s3-put"
        }
      }
    }]
  })
}
