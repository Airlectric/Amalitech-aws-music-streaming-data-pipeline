locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "dynamodb-kpi"
  }

  tables = {
    "kpi-hourly-streams" = {
      pk          = "artist_id"
      sk          = "hour_ts"
      ttl_days    = 90
      description = "Stream count per artist per hour"
    }
    "kpi-daily-streams" = {
      pk          = "artist_id"
      sk          = "date"
      ttl_days    = 365
      description = "Stream count per artist per day"
    }
    "kpi-monthly-streams" = {
      pk          = "artist_id"
      sk          = "month"
      ttl_days    = null
      description = "Stream count per artist per month (never expires)"
    }
  }
}
