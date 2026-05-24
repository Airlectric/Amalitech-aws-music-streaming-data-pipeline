variable "environment" {
  description = "Environment name"
  type        = string
}

variable "lambda_validator_arn" {
  description = "ARN of the event-validator Lambda function"
  type        = string
}

variable "lambda_archiver_arn" {
  description = "ARN of the stream-archiver Lambda function"
  type        = string
}

variable "glue_silver_job_name" {
  description = "Name of the Silver ETL Glue job"
  type        = string
}

variable "glue_gold_job_name" {
  description = "Name of the Gold ETL Glue job"
  type        = string
}

variable "glue_ddb_job_name" {
  description = "Name of the DDB ETL Glue job"
  type        = string
}

variable "step_functions_role_arn" {
  description = "ARN of the Step Functions IAM role"
  type        = string
}

variable "sns_alert_topic_arn" {
  description = "ARN of the SNS alert topic"
  type        = string
  default     = null
}
