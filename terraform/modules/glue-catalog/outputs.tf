output "bronze_database_name" {
  description = "Name of the Bronze Glue database"
  value       = aws_glue_catalog_database.bronze.name
}

output "silver_database_name" {
  description = "Name of the Silver Glue database"
  value       = aws_glue_catalog_database.silver.name
}

output "gold_database_name" {
  description = "Name of the Gold Glue database"
  value       = aws_glue_catalog_database.gold.name
}

output "bronze_table_name" {
  description = "Name of the bronze streams table"
  value       = aws_glue_catalog_table.bronze_streams.name
}

output "silver_table_name" {
  description = "Name of the silver curated streams table"
  value       = aws_glue_catalog_table.silver_streams_curated.name
}

output "gold_table_name" {
  description = "Name of the primary gold genre KPI table"
  value       = aws_glue_catalog_table.gold_genre_kpis_daily.name
}
