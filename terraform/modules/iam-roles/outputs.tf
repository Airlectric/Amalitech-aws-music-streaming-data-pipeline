output "role_arns" {
  description = "Map of all IAM role ARNs by name"
  value = {
    glue_silver        = aws_iam_role.glue_silver.arn
    glue_gold          = aws_iam_role.glue_gold.arn
    glue_ddb           = aws_iam_role.glue_ddb.arn
    lambda_validator   = aws_iam_role.lambda_validator.arn
    lambda_archiver    = aws_iam_role.lambda_archiver.arn
    lambda_event_router = aws_iam_role.lambda_event_router.arn
    step_functions     = aws_iam_role.step_functions.arn
    eventbridge        = aws_iam_role.eventbridge.arn
  }
}

output "role_names" {
  description = "Map of all IAM role names by name"
  value = {
    glue_silver        = aws_iam_role.glue_silver.name
    glue_gold          = aws_iam_role.glue_gold.name
    glue_ddb           = aws_iam_role.glue_ddb.name
    lambda_validator   = aws_iam_role.lambda_validator.name
    lambda_archiver    = aws_iam_role.lambda_archiver.name
    lambda_event_router = aws_iam_role.lambda_event_router.name
    step_functions     = aws_iam_role.step_functions.name
    eventbridge        = aws_iam_role.eventbridge.name
  }
}

output "glue_silver_role_arn" {
  description = "ARN of the Glue Silver ETL role"
  value       = aws_iam_role.glue_silver.arn
}

output "glue_gold_role_arn" {
  description = "ARN of the Glue Gold ETL role"
  value       = aws_iam_role.glue_gold.arn
}

output "glue_ddb_role_arn" {
  description = "ARN of the Glue DDB ETL role"
  value       = aws_iam_role.glue_ddb.arn
}

output "glue_role_arns" {
  description = "List of all Glue job role ARNs"
  value = [
    aws_iam_role.glue_silver.arn,
    aws_iam_role.glue_gold.arn,
    aws_iam_role.glue_ddb.arn,
  ]
}

output "lambda_validator_role_arn" {
  description = "ARN of the Lambda event-validator role"
  value       = aws_iam_role.lambda_validator.arn
}

output "lambda_archiver_role_arn" {
  description = "ARN of the Lambda stream-archiver role"
  value       = aws_iam_role.lambda_archiver.arn
}

output "lambda_event_router_role_arn" {
  description = "ARN of the Lambda event-router role"
  value       = aws_iam_role.lambda_event_router.arn
}

output "lambda_role_arns" {
  description = "List of all Lambda role ARNs"
  value = [
    aws_iam_role.lambda_validator.arn,
    aws_iam_role.lambda_archiver.arn,
    aws_iam_role.lambda_event_router.arn,
  ]
}

output "step_functions_role_arn" {
  description = "ARN of the Step Functions role"
  value       = aws_iam_role.step_functions.arn
}

output "eventbridge_role_arn" {
  description = "ARN of the EventBridge role"
  value       = aws_iam_role.eventbridge.arn
}
