locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "networking"
  }

  vpc_endpoint_services = {
    glue           = { service = "glue", private_dns = false }
    states         = { service = "states", private_dns = true }
    kms            = { service = "kms", private_dns = true }
    logs           = { service = "logs", private_dns = true }
    monitoring     = { service = "monitoring", private_dns = true }
    sqs            = { service = "sqs", private_dns = false }
    sns            = { service = "sns", private_dns = true }
    secretsmanager = { service = "secretsmanager", private_dns = true }
    sts            = { service = "sts", private_dns = true }
    ecr_api        = { service = "ecr.api", private_dns = true }
    ecr_dkr        = { service = "ecr.dkr", private_dns = true }
    athena         = { service = "athena", private_dns = true }
  }

  gateway_endpoint_services = {
    s3       = { service = "s3" }
    dynamodb = { service = "dynamodb" }
  }
}
