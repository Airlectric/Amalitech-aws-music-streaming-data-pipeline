output "event_validator_arn" {
  description = "ARN of the event-validator Lambda function"
  value       = aws_lambda_function.event_validator.arn
}

output "stream_archiver_arn" {
  description = "ARN of the stream-archiver Lambda function"
  value       = aws_lambda_function.stream_archiver.arn
}

output "event_router_arn" {
  description = "ARN of the event-router Lambda function"
  value       = aws_lambda_function.event_router.arn
}

output "function_names" {
  description = "Map of Lambda function names by role"
  value = {
    validator    = aws_lambda_function.event_validator.function_name
    archiver     = aws_lambda_function.stream_archiver.function_name
    event_router = aws_lambda_function.event_router.function_name
  }
}

output "function_arns" {
  description = "Map of Lambda function ARNs by name"
  value = {
    validator   = aws_lambda_function.event_validator.arn
    archiver    = aws_lambda_function.stream_archiver.arn
    event_router = aws_lambda_function.event_router.arn
  }
}
