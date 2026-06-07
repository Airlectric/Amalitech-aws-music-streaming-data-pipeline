variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  # Single AZ by default to minimize cost: each interface VPC endpoint is billed
  # per-AZ, so a second AZ would roughly double the endpoint spend for HA we don't
  # need in a course/dev context. Add more AZs here to scale out when needed.
  description = "Availability zones for the private subnets (single-AZ by default for cost)"
  type        = list(string)
  default     = ["us-east-1a"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets, one per availability zone"
  type        = list(string)
  default     = ["10.0.10.0/24"]
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
