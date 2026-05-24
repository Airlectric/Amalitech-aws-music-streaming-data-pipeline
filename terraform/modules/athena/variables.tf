variable "environment" {
  description = "Environment name"
  type        = string
}

variable "athena_results_bucket_id" {
  description = "ID (name) of the Athena results S3 bucket"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for encrypting results"
  type        = string
}
