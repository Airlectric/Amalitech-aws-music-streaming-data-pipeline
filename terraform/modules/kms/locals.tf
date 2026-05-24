locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "kms"
  }

  keys = {
    s3-data-lake = {
      description        = "KMS CMK for S3 data lake encryption"
      service_principals = ["s3.amazonaws.com"]
      role_arns          = var.s3_data_lake_bucket_arns
      alias_name         = "${var.environment}/s3-data-lake"
    }
    dynamodb = {
      description        = "KMS CMK for DynamoDB table encryption"
      service_principals = ["dynamodb.amazonaws.com"]
      role_arns          = var.dynamodb_kpi_table_arns
      alias_name         = "${var.environment}/dynamodb"
    }
    logs = {
      description        = "KMS CMK for CloudWatch log group encryption"
      service_principals = ["logs.amazonaws.com", "logs.us-east-1.amazonaws.com"]
      role_arns          = []
      alias_name         = "${var.environment}/logs"
    }
    glue = {
      description        = "KMS CMK for Glue job encryption (bookmarks, logs, S3)"
      service_principals = ["glue.amazonaws.com"]
      role_arns          = var.glue_job_role_arns
      alias_name         = "${var.environment}/glue"
    }
    secrets = {
      description        = "KMS CMK for Secrets Manager encryption"
      service_principals = ["secretsmanager.amazonaws.com"]
      role_arns          = []
      alias_name         = "${var.environment}/secrets"
    }
  }
}
