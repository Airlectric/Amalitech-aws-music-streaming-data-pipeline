variable "environment" {
  description = "Environment name"
  type        = string
  default     = "music-dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}





variable "bucket_suffix" {
  description = "Unique suffix for S3 bucket names (e.g., account ID or project name)"
  type        = string
}

variable "sns_alert_emails" {
  description = "List of email addresses for SNS alert subscriptions"
  type        = list(string)
  default     = []
}

