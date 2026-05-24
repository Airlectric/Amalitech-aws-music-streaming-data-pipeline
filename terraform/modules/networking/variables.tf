variable "environment" {
  description = "Environment name"
  type        = string
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

variable "kms_key_arn" {
  description = "ARN of the KMS CMK for CloudWatch log encryption"
  type        = string
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs to CloudWatch"
  type        = bool
  default     = true
}

variable "retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}
