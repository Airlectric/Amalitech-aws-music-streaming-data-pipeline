variable "environment" {
  description = "Environment name"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the DynamoDB KMS CMK"
  type        = string
}
