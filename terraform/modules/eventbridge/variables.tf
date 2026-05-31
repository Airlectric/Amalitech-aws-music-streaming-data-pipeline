variable "environment" {
  description = "Environment name"
  type        = string
}

variable "bronze_bucket_id" {
  description = "Bronze S3 bucket ID"
  type        = string
}

variable "event_router_lambda_arn" {
  description = "ARN of the event-router Lambda function"
  type        = string
}

variable "eventbridge_role_arn" {
  description = "ARN of the EventBridge IAM role"
  type        = string
}

variable "dlq_arn" {
  description = "ARN of the SQS dead-letter queue for failed rule deliveries"
  type        = string
}
