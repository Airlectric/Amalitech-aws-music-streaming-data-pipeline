locals {
  account_id = data.aws_caller_identity.current.account_id

  step_functions_arn = "arn:aws:states:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.environment}-medallion-pipeline"

  lambda_validator_arn    = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.environment}-event-validator"
  lambda_archiver_arn     = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.environment}-stream-archiver"
  lambda_event_router_arn = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.environment}-event-router"
  lambda_quarantiner_arn  = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.environment}-quarantine-handler"

  # Pipeline dead-letter queue (created in the lambda-functions module). Referenced by
  # ARN convention here to avoid an iam-roles <-> lambda-functions dependency cycle.
  pipeline_dlq_arn = "arn:aws:sqs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${var.environment}-pipeline-dlq"

  kms_decrypt = [
    "kms:Decrypt",
    "kms:GenerateDataKey*",
    "kms:DescribeKey",
  ]

  kms_encrypt_decrypt = [
    "kms:Encrypt",
    "kms:Decrypt",
    "kms:GenerateDataKey*",
    "kms:ReEncrypt*",
    "kms:DescribeKey",
  ]

  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "iam"
  }
}
