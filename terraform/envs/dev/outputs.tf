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
