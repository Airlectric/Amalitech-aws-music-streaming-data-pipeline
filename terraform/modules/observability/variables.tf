variable "environment" {
  description = "Environment name"
  type        = string
}

variable "lambda_function_names" {
  description = "Map of Lambda function names"
  type        = map(string)
}

variable "glue_job_names" {
  description = "Map of Glue job names"
  type        = map(string)
}

variable "step_functions_state_machine_arn" {
  description = "ARN of the Step Functions state machine"
  type        = string
}

variable "eventbridge_rule_name" {
  description = "Name of the EventBridge rule"
  type        = string
}

variable "sns_topic_arn" {
  description = "ARN of the SNS alert topic"
  type        = string
}

variable "s3_bronze_bucket_name" {
  description = "Name of the Bronze S3 bucket"
  type        = string
}

variable "dlq_name" {
  description = "Name of the pipeline dead-letter SQS queue (used as CloudWatch SQS dimension)"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt CloudTrail logs at rest (SSE-KMS)"
  type        = string
}
