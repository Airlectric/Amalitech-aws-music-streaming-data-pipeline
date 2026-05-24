output "silver_etl_job_name" {
  description = "Name of the Silver ETL Glue job"
  value       = aws_glue_job.silver_etl.name
}

output "gold_etl_job_name" {
  description = "Name of the Gold ETL Glue job"
  value       = aws_glue_job.gold_etl.name
}

output "ddb_etl_job_name" {
  description = "Name of the DDB ETL Glue job"
  value       = aws_glue_job.ddb_etl.name
}

output "job_names" {
  description = "Map of Glue job names by layer"
  value = {
    silver = aws_glue_job.silver_etl.name
    gold   = aws_glue_job.gold_etl.name
    ddb    = aws_glue_job.ddb_etl.name
  }
}
