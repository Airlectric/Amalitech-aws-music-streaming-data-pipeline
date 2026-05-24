variable "environment" {
  description = "Environment name"
  type        = string
}

variable "glue_scripts_bucket_id" {
  description = "S3 bucket ID for Glue scripts and temp files"
  type        = string
}

variable "bronze_bucket_id" {
  description = "Bronze S3 bucket ID"
  type        = string
}

variable "silver_bucket_id" {
  description = "Silver S3 bucket ID"
  type        = string
}

variable "gold_bucket_id" {
  description = "Gold S3 bucket ID"
  type        = string
}

variable "glue_silver_role_arn" {
  description = "ARN of the Glue Silver ETL IAM role"
  type        = string
}

variable "glue_gold_role_arn" {
  description = "ARN of the Glue Gold ETL IAM role"
  type        = string
}

variable "glue_ddb_role_arn" {
  description = "ARN of the Glue DDB ETL IAM role"
  type        = string
}

variable "dynamodb_kpi_table_names" {
  description = "Map of DynamoDB KPI table names (hourly, daily, monthly)"
  type        = map(string)
}

variable "private_subnet_id" {
  description = "Private subnet ID for Glue jobs"
  type        = string
}

variable "security_group_glue_id" {
  description = "Security group ID for Glue jobs"
  type        = string
}

variable "max_retries" {
  description = "Maximum number of retries for Glue jobs"
  type        = number
  default     = 1
}

variable "timeout_minutes" {
  description = "Timeout in minutes for Glue jobs"
  type        = number
  default     = 60
}

variable "worker_count" {
  description = "Number of G.1X workers for Glue jobs"
  type        = number
  default     = 2
}
