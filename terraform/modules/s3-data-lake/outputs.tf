output "bucket_ids" {
  description = "Map of S3 bucket IDs by layer"
  value = {
    for k, b in aws_s3_bucket.this : k => b.id
  }
}

output "bucket_arns" {
  description = "Map of S3 bucket ARNs by layer"
  value = {
    for k, b in aws_s3_bucket.this : k => b.arn
  }
}

output "bronze_bucket_id" {
  description = "ID of the Bronze bucket"
  value       = aws_s3_bucket.this["bronze"].id
}

output "silver_bucket_id" {
  description = "ID of the Silver bucket"
  value       = aws_s3_bucket.this["silver"].id
}

output "gold_bucket_id" {
  description = "ID of the Gold bucket"
  value       = aws_s3_bucket.this["gold"].id
}

output "archive_bucket_id" {
  description = "ID of the Archive bucket"
  value       = aws_s3_bucket.this["archive"].id
}

output "glue_scripts_bucket_id" {
  description = "ID of the Glue scripts bucket"
  value       = aws_s3_bucket.this["glue_scripts"].id
}

output "athena_results_bucket_id" {
  description = "ID of the Athena results bucket"
  value       = aws_s3_bucket.this["athena_results"].id
}

output "bronze_bucket_arn" {
  description = "ARN of the Bronze bucket"
  value       = aws_s3_bucket.this["bronze"].arn
}

output "silver_bucket_arn" {
  description = "ARN of the Silver bucket"
  value       = aws_s3_bucket.this["silver"].arn
}

output "gold_bucket_arn" {
  description = "ARN of the Gold bucket"
  value       = aws_s3_bucket.this["gold"].arn
}

output "archive_bucket_arn" {
  description = "ARN of the Archive bucket"
  value       = aws_s3_bucket.this["archive"].arn
}
