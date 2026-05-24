locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "s3-data-lake"
  }

  bucket_name = {
    bronze         = "bronze-${var.bucket_suffix}"
    silver         = "silver-${var.bucket_suffix}"
    gold           = "gold-${var.bucket_suffix}"
    quarantine     = "quarantine-${var.bucket_suffix}"
    archive        = "archive-${var.bucket_suffix}"
    glue_scripts   = "glue-scripts-${var.bucket_suffix}"
    athena_results = "athena-results-${var.bucket_suffix}"
    access_logs    = "s3-access-logs-${var.bucket_suffix}"
  }
}
