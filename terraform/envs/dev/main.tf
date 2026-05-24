data "aws_caller_identity" "current" {}

module "kms" {
  source      = "../../modules/kms"
  environment = var.environment
}

module "networking" {
  source      = "../../modules/networking"
  environment = var.environment

  vpc_cidr             = var.vpc_cidr
  private_subnet_cidr  = var.private_subnet_cidr
  availability_zone    = var.availability_zone
  kms_key_arn          = module.kms.logs_key_arn
  enable_flow_logs     = true
  retention_days       = 30
}
