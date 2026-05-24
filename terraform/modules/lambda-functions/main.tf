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
  timeout          = 30
  memory_size      = 256

  tracing_config {
    mode = "PassThrough"
  }

  environment {
    variables = {
      EXPECTED_SCHEMA_TYPE = "music_stream"
      SSM_PARAM_PATH       = "/${var.environment}/validator/expected_schema"
      BRONZE_BUCKET        = var.bronze_bucket_id
      DQ_TABLE_NAME        = var.dq_table_name
      GLUE_DATABASE        = "${var.environment}_bronze_db"
      GLUE_TABLE           = "streams"
    }
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.security_group_lambda_id]
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

  tracing_config {
    mode = "PassThrough"
  }

  environment {
    variables = {
      BRONZE_BUCKET     = var.bronze_bucket_id
      QUARANTINE_BUCKET = var.quarantine_bucket_id
    }
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.security_group_lambda_id]
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

  tracing_config {
    mode = "PassThrough"
  }

  environment {
    variables = {
      BRONZE_BUCKET  = var.bronze_bucket_id
      ARCHIVE_BUCKET = var.archive_bucket_id
    }
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.security_group_lambda_id]
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
    mode = "PassThrough"
  }

  environment {
    variables = {
      STATE_MACHINE_ARN = local.step_functions_arn
    }
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-event-router" })
}

# ────────────────────────────────────────────
# LAMBDA PERMISSIONS
# ────────────────────────────────────────────
resource "aws_lambda_permission" "event_router_from_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.event_router.function_name
  principal     = "events.amazonaws.com"
}
