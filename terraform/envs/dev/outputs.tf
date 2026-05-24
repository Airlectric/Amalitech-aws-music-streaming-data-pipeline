output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = module.networking.private_subnet_id
}

output "kms_key_arns" {
  description = "Map of KMS key ARNs by domain"
  value       = module.kms.key_arns
}

output "security_group_glue_id" {
  description = "ID of the Glue security group"
  value       = module.networking.security_group_glue_id
}

output "security_group_lambda_id" {
  description = "ID of the Lambda security group"
  value       = module.networking.security_group_lambda_id
}

output "bronze_bucket_id" {
  description = "ID of the Bronze S3 bucket"
  value       = module.s3_data_lake.bronze_bucket_id
}

output "silver_bucket_id" {
  description = "ID of the Silver S3 bucket"
  value       = module.s3_data_lake.silver_bucket_id
}

output "gold_bucket_id" {
  description = "ID of the Gold S3 bucket"
  value       = module.s3_data_lake.gold_bucket_id
}

output "glue_scripts_bucket_id" {
  description = "ID of the Glue scripts S3 bucket"
  value       = module.s3_data_lake.glue_scripts_bucket_id
}

output "s3_bucket_arns" {
  description = "Map of all S3 bucket ARNs by layer"
  value       = module.s3_data_lake.bucket_arns
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge S3 rule"
  value       = module.eventbridge.event_rule_arn
}

output "step_functions_arn" {
  description = "ARN of the medallion pipeline state machine"
  value       = module.step_functions.state_machine_arn
}

output "lambda_event_validator_arn" {
  description = "ARN of the event-validator Lambda function"
  value       = module.lambda_functions.event_validator_arn
}

output "lambda_stream_archiver_arn" {
  description = "ARN of the stream-archiver Lambda function"
  value       = module.lambda_functions.stream_archiver_arn
}

output "lambda_event_router_arn" {
  description = "ARN of the event-router Lambda function"
  value       = module.lambda_functions.event_router_arn
}

output "glue_silver_etl_job_name" {
  description = "Name of the Silver ETL Glue job"
  value       = module.glue_jobs.silver_etl_job_name
}

output "glue_gold_etl_job_name" {
  description = "Name of the Gold ETL Glue job"
  value       = module.glue_jobs.gold_etl_job_name
}

output "glue_ddb_etl_job_name" {
  description = "Name of the DDB ETL Glue job"
  value       = module.glue_jobs.ddb_etl_job_name
}

output "glue_bronze_database_name" {
  description = "Name of the Bronze Glue database"
  value       = module.glue_catalog.bronze_database_name
}

output "glue_silver_database_name" {
  description = "Name of the Silver Glue database"
  value       = module.glue_catalog.silver_database_name
}

output "glue_gold_database_name" {
  description = "Name of the Gold Glue database"
  value       = module.glue_catalog.gold_database_name
}

output "dynamodb_kpi_table_arns_map" {
  description = "Map of DynamoDB KPI table names to ARNs"
  value       = module.dynamodb_kpi.table_arns_map
}

output "dynamodb_kpi_table_names" {
  description = "List of DynamoDB KPI table names"
  value       = module.dynamodb_kpi.table_names
}

output "iam_role_arns" {
  description = "Map of all IAM role ARNs by name"
  value       = module.iam_roles.role_arns
}

output "glue_role_arns" {
  description = "List of all Glue job role ARNs"
  value       = module.iam_roles.glue_role_arns
}

output "glue_silver_role_arn" {
  description = "ARN of the Glue Silver ETL role"
  value       = module.iam_roles.glue_silver_role_arn
}

output "glue_gold_role_arn" {
  description = "ARN of the Glue Gold ETL role"
  value       = module.iam_roles.glue_gold_role_arn
}

output "glue_ddb_role_arn" {
  description = "ARN of the Glue DDB ETL role"
  value       = module.iam_roles.glue_ddb_role_arn
}

output "lambda_validator_role_arn" {
  description = "ARN of the Lambda event-validator role"
  value       = module.iam_roles.lambda_validator_role_arn
}

output "lambda_archiver_role_arn" {
  description = "ARN of the Lambda stream-archiver role"
  value       = module.iam_roles.lambda_archiver_role_arn
}

output "lambda_event_router_role_arn" {
  description = "ARN of the Lambda event-router role"
  value       = module.iam_roles.lambda_event_router_role_arn
}

output "step_functions_role_arn" {
  description = "ARN of the Step Functions role"
  value       = module.iam_roles.step_functions_role_arn
}

output "athena_workgroup_name" {
  description = "Name of the Athena analytics workgroup"
  value       = module.athena.workgroup_name
}

output "eventbridge_role_arn" {
  description = "ARN of the EventBridge role"
  value       = module.iam_roles.eventbridge_role_arn
}
