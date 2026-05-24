locals {
  account_id = data.aws_caller_identity.current.account_id

  step_functions_arn = "arn:aws:states:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.environment}-medallion-pipeline"

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
