variable "environment" {
  description = "Environment name"
  type        = string
}

variable "bronze_bucket_id" {
  description = "Bronze S3 bucket ID"
  type        = string
}

variable "archive_bucket_id" {
  description = "Archive S3 bucket ID"
  type        = string
}

variable "lambda_validator_role_arn" {
  description = "ARN of the Lambda event-validator IAM role"
  type        = string
}

variable "lambda_archiver_role_arn" {
  description = "ARN of the Lambda stream-archiver IAM role"
  type        = string
}

variable "lambda_event_router_role_arn" {
  description = "ARN of the Lambda event-router IAM role"
  type        = string
}

variable "lambda_quarantiner_role_arn" {
  description = "ARN of the Lambda quarantine-handler IAM role"
  type        = string
}

variable "quarantine_bucket_id" {
  description = "Quarantine S3 bucket ID"
  type        = string
}

variable "dq_table_name" {
  description = "Name of the DQ reports DynamoDB table"
  type        = string
}

variable "security_group_lambda_id" {
  description = "Security group ID for Lambda functions"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for Lambda VPC config"
  type        = list(string)
}
