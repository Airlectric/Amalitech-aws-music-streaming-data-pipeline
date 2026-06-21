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




variable "max_retries" {
  description = "Maximum number of retries for Glue jobs"
  type        = number
  default     = 1
}

# ── Silver ETL (Spark) ────────────────────────────────────────────────────────

variable "silver_worker_type" {
  description = "Glue worker type for the Silver ETL Spark job (G.1X, G.2X, G.4X, G.8X)"
  type        = string
  default     = "G.1X"
}

variable "silver_worker_count" {
  description = "Number of workers for Silver ETL; treated as the maximum when enable_auto_scaling is true"
  type        = number
  default     = 10
}

variable "silver_timeout_minutes" {
  description = "Timeout in minutes for the Silver ETL job"
  type        = number
  default     = 60
}

# ── Gold ETL (Spark) ──────────────────────────────────────────────────────────

variable "gold_worker_type" {
  description = "Glue worker type for the Gold ETL Spark job (G.1X, G.2X, G.4X, G.8X)"
  type        = string
  default     = "G.1X"
}

variable "gold_worker_count" {
  description = "Number of workers for Gold ETL; treated as the maximum when enable_auto_scaling is true"
  type        = number
  default     = 10
}

variable "gold_timeout_minutes" {
  description = "Timeout in minutes for the Gold ETL job"
  type        = number
  default     = 30
}

# ── DDB ETL (Python Shell) ────────────────────────────────────────────────────

variable "ddb_timeout_minutes" {
  description = "Timeout in minutes for the DDB ETL Python Shell job"
  type        = number
  default     = 30
}

# ── Auto-scaling (Spark jobs only) ────────────────────────────────────────────

variable "enable_auto_scaling" {
  description = "Enable Glue auto-scaling for the Silver and Gold Spark jobs. When true, *_worker_count is used as the maximum number of workers."
  type        = bool
  default     = true
}
