variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.0.10.0/24"
}

variable "availability_zone" {
  description = "Availability zone for the private subnet"
  type        = string
  default     = "us-east-1a"
}

variable "bucket_suffix" {
  description = "Unique suffix for S3 bucket names (e.g., account ID or project name)"
  type        = string
}

variable "step_functions_arn" {
  description = "ARN of the Step Functions state machine"
  type        = string
  default     = null
}

variable "lambda_validator_arn" {
  description = "ARN of the event-validator Lambda function"
  type        = string
  default     = null
}

variable "lambda_archiver_arn" {
  description = "ARN of the stream-archiver Lambda function"
  type        = string
  default     = null
}

variable "lambda_event_router_arn" {
  description = "ARN of the event-router Lambda function"
  type        = string
  default     = null
}

variable "sns_alert_topic_arn" {
  description = "ARN of the SNS alert topic"
  type        = string
  default     = null
}

