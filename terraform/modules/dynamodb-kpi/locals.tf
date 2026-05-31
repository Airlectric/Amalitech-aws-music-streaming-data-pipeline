locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "dynamodb-kpi"
  }

  tables = {
    "genre-kpis-daily" = {
      pk          = "genre"
      pk_type     = "S"
      sk          = "date"
      sk_type     = "S"
      ttl_days    = 90
      description = "Daily genre-level KPIs"
    }
    "top-songs-by-genre-daily" = {
      pk          = "genre_date"
      pk_type     = "S"
      sk          = "rank"
      sk_type     = "N"
      ttl_days    = 365
      description = "Top songs per genre per day"
    }
    "top-genres-daily" = {
      pk          = "date"
      pk_type     = "S"
      sk          = "rank"
      sk_type     = "N"
      ttl_days    = 365
      description = "Top genres per day"
    }
    "dq-reports" = {
      pk          = "batch_id"
      pk_type     = "S"
      sk          = "event_date"
      sk_type     = "S"
      ttl_days    = 30
      description = "Data quality validation reports per batch"
    }
  }
}
