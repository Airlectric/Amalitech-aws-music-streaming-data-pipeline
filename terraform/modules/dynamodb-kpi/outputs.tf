output "table_arns" {
  description = "List of all DynamoDB KPI table ARNs"
  value       = [for t in aws_dynamodb_table.this : t.arn]
}

output "table_names" {
  description = "List of all DynamoDB KPI table names"
  value       = [for t in aws_dynamodb_table.this : t.name]
}

output "table_arns_map" {
  description = "Map of table short-name to ARN (hourly, daily, monthly)"
  value = {
    for k, t in aws_dynamodb_table.this : k => t.arn
  }
}

output "table_names_map" {
  description = "Map of table short-name to full name"
  value = {
    for k, t in aws_dynamodb_table.this : k => t.name
  }
}
