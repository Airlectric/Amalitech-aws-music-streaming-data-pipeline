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
