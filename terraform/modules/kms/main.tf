locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "kms"
  }

  keys = {
    s3-data-lake = {
      description      = "KMS CMK for S3 data lake encryption"
      service_principals = ["s3.amazonaws.com"]
      role_arns        = var.s3_data_lake_bucket_arns
      alias_name       = "${var.environment}/s3-data-lake"
    }
    dynamodb = {
      description      = "KMS CMK for DynamoDB table encryption"
      service_principals = ["dynamodb.amazonaws.com"]
      role_arns        = var.dynamodb_kpi_table_arns
      alias_name       = "${var.environment}/dynamodb"
    }
    logs = {
      description      = "KMS CMK for CloudWatch log group encryption"
      service_principals = ["logs.amazonaws.com", "logs.us-east-1.amazonaws.com"]
      role_arns        = []
      alias_name       = "${var.environment}/logs"
    }
    glue = {
      description      = "KMS CMK for Glue job encryption (bookmarks, logs, S3)"
      service_principals = ["glue.amazonaws.com"]
      role_arns        = var.glue_job_role_arns
      alias_name       = "${var.environment}/glue"
    }
    secrets = {
      description      = "KMS CMK for Secrets Manager encryption"
      service_principals = ["secretsmanager.amazonaws.com"]
      role_arns        = []
      alias_name       = "${var.environment}/secrets"
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "this" {
  for_each = local.keys

  description              = each.value.description
  deletion_window_in_days  = 30
  enable_key_rotation      = true
  is_enabled              = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid    = "EnableAdminFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowServicePrincipalAccess"
        Effect = "Allow"
        Principal = {
          Service = each.value.service_principals
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ], length(each.value.role_arns) > 0 ? [
      {
        Sid    = "AllowRoleAccess"
        Effect = "Allow"
        Principal = {
          AWS = each.value.role_arns
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ] : [])
  })

  tags = merge(local.common_tags, { Name = each.key })
}

resource "aws_kms_alias" "this" {
  for_each = aws_kms_key.this

  name          = "alias/${each.value.tags_all["Name"]}"
  target_key_id = each.value.key_id
}
