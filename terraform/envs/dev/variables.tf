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

variable "availability_zones" {
  description = "Availability zones for the private subnets (multi-AZ)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets, one per availability zone"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
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

