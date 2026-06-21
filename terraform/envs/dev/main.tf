data "aws_caller_identity" "current" {}

resource "aws_sns_topic" "alerts" {
  name = "${var.environment}-pipeline-alerts"

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Name        = "${var.environment}-pipeline-alerts"
  }
}

resource "aws_sns_topic_subscription" "alerts_email" {
  for_each = { for idx, email in var.sns_alert_emails : idx => email }

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

module "kms" {
  source      = "../../modules/kms"
  environment = var.environment
}


module "s3_data_lake" {
  source      = "../../modules/s3-data-lake"
  environment = var.environment

  bucket_suffix      = var.bucket_suffix
  kms_key_arn        = module.kms.s3_data_lake_key_arn
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

  glue_silver_role_arn     = module.iam_roles.glue_silver_role_arn
  glue_gold_role_arn       = module.iam_roles.glue_gold_role_arn
  glue_ddb_role_arn        = module.iam_roles.glue_ddb_role_arn
  dynamodb_kpi_table_names = module.dynamodb_kpi.table_names_map

}

module "lambda_functions" {
  source      = "../../modules/lambda-functions"
  environment = var.environment

  bronze_bucket_id     = module.s3_data_lake.bronze_bucket_id
  archive_bucket_id    = module.s3_data_lake.archive_bucket_id
  quarantine_bucket_id = module.s3_data_lake.quarantine_bucket_id
  dq_table_name        = module.dynamodb_kpi.dq_table_name

  lambda_validator_role_arn    = module.iam_roles.lambda_validator_role_arn
  lambda_archiver_role_arn     = module.iam_roles.lambda_archiver_role_arn
  lambda_event_router_role_arn = module.iam_roles.lambda_event_router_role_arn
  lambda_quarantiner_role_arn  = module.iam_roles.lambda_quarantiner_role_arn
}

module "step_functions" {
  source      = "../../modules/step-functions"
  environment = var.environment

  lambda_validator_arn   = module.lambda_functions.event_validator_arn
  lambda_quarantiner_arn = module.lambda_functions.quarantine_handler_arn
  lambda_archiver_arn    = module.lambda_functions.stream_archiver_arn

  glue_silver_job_name = module.glue_jobs.silver_etl_job_name
  glue_gold_job_name   = module.glue_jobs.gold_etl_job_name
  glue_ddb_job_name    = module.glue_jobs.ddb_etl_job_name

  step_functions_role_arn = module.iam_roles.step_functions_role_arn
  sns_alert_topic_arn     = aws_sns_topic.alerts.arn
  bronze_bucket_id        = module.s3_data_lake.bronze_bucket_id
  silver_bucket_id        = module.s3_data_lake.silver_bucket_id
  gold_bucket_id          = module.s3_data_lake.gold_bucket_id
  genre_kpis_table_name   = module.dynamodb_kpi.table_names_map["genre-kpis-daily"]
  top_songs_table_name    = module.dynamodb_kpi.table_names_map["top-songs-by-genre-daily"]
  top_genres_table_name   = module.dynamodb_kpi.table_names_map["top-genres-daily"]
}

module "eventbridge" {
  source      = "../../modules/eventbridge"
  environment = var.environment

  bronze_bucket_id        = module.s3_data_lake.bronze_bucket_id
  event_router_lambda_arn = module.lambda_functions.event_router_arn
  eventbridge_role_arn    = module.iam_roles.eventbridge_role_arn
  dlq_arn                 = module.lambda_functions.pipeline_dlq_arn
}

module "athena" {
  source      = "../../modules/athena"
  environment = var.environment

  athena_results_bucket_id = module.s3_data_lake.athena_results_bucket_id
  kms_key_arn              = module.kms.s3_data_lake_key_arn
}

module "observability" {
  source      = "../../modules/observability"
  environment = var.environment

  lambda_function_names            = module.lambda_functions.function_names
  glue_job_names                   = module.glue_jobs.job_names
  step_functions_state_machine_arn = module.step_functions.state_machine_arn
  eventbridge_rule_name            = module.eventbridge.event_rule_name
  sns_topic_arn                    = aws_sns_topic.alerts.arn
  s3_bronze_bucket_name            = module.s3_data_lake.bronze_bucket_id
  dlq_name                         = module.lambda_functions.pipeline_dlq_name
}

module "iam_roles" {
  source      = "../../modules/iam-roles"
  environment = var.environment
  aws_region  = var.aws_region

  bucket_arns  = module.s3_data_lake.bucket_arns
  kms_key_arns = module.kms.key_arns

  dynamodb_kpi_table_arns = module.dynamodb_kpi.table_arns
  dynamodb_dq_table_arn   = module.dynamodb_kpi.dq_table_arn
  quarantine_bucket_arn   = module.s3_data_lake.quarantine_bucket_arn
  sns_alert_topic_arn     = aws_sns_topic.alerts.arn
}
