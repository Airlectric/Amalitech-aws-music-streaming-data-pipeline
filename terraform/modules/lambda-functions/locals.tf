locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "lambda-functions"
  }

  step_functions_arn = "arn:aws:states:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.environment}-medallion-pipeline"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}
