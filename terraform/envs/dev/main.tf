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

module "s3_data_lake" {
  source      = "../../modules/s3-data-lake"
  environment = var.environment

  bucket_suffix    = var.bucket_suffix
  kms_key_arn      = module.kms.s3_data_lake_key_arn
  log_retention_days = 365
}

module "dynamodb_kpi" {
  source      = "../../modules/dynamodb-kpi"
  environment = var.environment

  kms_key_arn = module.kms.dynamodb_key_arn
}

module "glue_catalog" {
  source      = "../../modules/glue-catalog"
  environment = var.environment

  bronze_bucket_id = module.s3_data_lake.bronze_bucket_id
  silver_bucket_id = module.s3_data_lake.silver_bucket_id
  gold_bucket_id   = module.s3_data_lake.gold_bucket_id
}

module "glue_jobs" {
  source      = "../../modules/glue-jobs"
  environment = var.environment

  glue_scripts_bucket_id = module.s3_data_lake.glue_scripts_bucket_id
  bronze_bucket_id       = module.s3_data_lake.bronze_bucket_id
  silver_bucket_id       = module.s3_data_lake.silver_bucket_id
  gold_bucket_id         = module.s3_data_lake.gold_bucket_id

  glue_silver_role_arn    = module.iam_roles.glue_silver_role_arn
  glue_gold_role_arn      = module.iam_roles.glue_gold_role_arn
  glue_ddb_role_arn       = module.iam_roles.glue_ddb_role_arn
  dynamodb_kpi_table_names = module.dynamodb_kpi.table_names_map

  private_subnet_id       = module.networking.private_subnet_id
  security_group_glue_id  = module.networking.security_group_glue_id
}

module "lambda_functions" {
  source      = "../../modules/lambda-functions"
  environment = var.environment

  bronze_bucket_id  = module.s3_data_lake.bronze_bucket_id
  archive_bucket_id = module.s3_data_lake.archive_bucket_id

  lambda_validator_role_arn    = module.iam_roles.lambda_validator_role_arn
  lambda_archiver_role_arn     = module.iam_roles.lambda_archiver_role_arn
  lambda_event_router_role_arn = module.iam_roles.lambda_event_router_role_arn
  step_functions_arn           = var.step_functions_arn

  private_subnet_ids       = [module.networking.private_subnet_id]
  security_group_lambda_id = module.networking.security_group_lambda_id
}

module "iam_roles" {
  source      = "../../modules/iam-roles"
  environment = var.environment
  aws_region  = var.aws_region

  bucket_arns   = module.s3_data_lake.bucket_arns
  kms_key_arns  = module.kms.key_arns

  dynamodb_kpi_table_arns = module.dynamodb_kpi.table_arns
  step_functions_arn      = var.step_functions_arn
  lambda_validator_arn    = var.lambda_validator_arn
  lambda_archiver_arn     = var.lambda_archiver_arn
  lambda_event_router_arn = var.lambda_event_router_arn
  sns_alert_topic_arn     = var.sns_alert_topic_arn
}
