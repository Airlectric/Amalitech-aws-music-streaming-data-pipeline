variable "environment" {
  description = "Environment name"
  type        = string
}

variable "glue_job_role_arns" {
  description = "ARNs of Glue job IAM roles for key policy"
  type        = list(string)
  default     = []
}

variable "lambda_role_arns" {
  description = "ARNs of Lambda IAM roles for key policy"
  type        = list(string)
  default     = []
}

variable "step_functions_role_arn" {
  description = "ARN of the Step Functions IAM role"
  type        = string
  default     = null
}

variable "dynamodb_kpi_table_arns" {
  description = "ARNs of DynamoDB KPI tables"
  type        = list(string)
  default     = []
}

variable "s3_data_lake_bucket_arns" {
  description = "ARNs of S3 data lake buckets"
  type        = list(string)
  default     = []
}
