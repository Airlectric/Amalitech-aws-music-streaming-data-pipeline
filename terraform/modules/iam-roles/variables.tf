variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "bucket_arns" {
  description = "Map of S3 bucket ARNs by layer (bronze, silver, gold, archive, glue_scripts)"
  type        = map(string)
}

variable "kms_key_arns" {
  description = "Map of KMS key ARNs by domain (s3_data_lake, dynamodb, logs, secrets)"
  type        = map(string)
}

variable "dynamodb_kpi_table_arns" {
  description = "ARNs of the DynamoDB KPI tables (populated after DDB module is created)"
  type        = list(string)
  default     = []
}

variable "sns_alert_topic_arn" {
  description = "ARN of the SNS alert topic"
  type        = string
  default     = null
}

variable "dynamodb_dq_table_arn" {
  description = "ARN of the DQ reports DynamoDB table"
  type        = string
  default     = ""
}

variable "quarantine_bucket_arn" {
  description = "ARN of the Quarantine S3 bucket"
  type        = string
  default     = ""
}
