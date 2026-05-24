variable "environment" {
  description = "Environment name"
  type        = string
}

variable "bucket_suffix" {
  description = "Unique suffix for S3 bucket names (e.g., account ID)"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS CMK for S3 data lake encryption"
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain access logs"
  type        = number
  default     = 365
}
