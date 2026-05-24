# ────────────────────────────────────────────
# DATABASES
# ────────────────────────────────────────────
resource "aws_glue_catalog_database" "bronze" {
  name        = "${var.environment}_bronze_db"
  description = "Raw ingested music streaming data"

  location_uri = "s3://${var.bronze_bucket_id}/streams/"
}

resource "aws_glue_catalog_database" "silver" {
  name        = "${var.environment}_silver_db"
  description = "Cleaned, deduplicated, and enriched music streaming data"

  location_uri = "s3://${var.silver_bucket_id}/"
}

resource "aws_glue_catalog_database" "gold" {
  name        = "${var.environment}_gold_db"
  description = "Aggregated KPI data for analytics"

  location_uri = "s3://${var.gold_bucket_id}/"
}

# ────────────────────────────────────────────
# BRONZE DB: streams table (raw JSON ingestion)
# ────────────────────────────────────────────
resource "aws_glue_catalog_table" "bronze_streams" {
  name          = "streams"
  database_name = aws_glue_catalog_database.bronze.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                        = "TRUE"
    "classification"                = "json"
    "projection.enabled"            = "true"
    "projection.event_date.type"    = "date"
    "projection.event_date.range"   = "2020-01-01,NOW"
    "projection.event_date.format"  = "yyyy/MM/dd"
    "projection.event_date.interval" = "1"
    "projection.event_date.interval.unit" = "DAYS"
    "storage.location.template"     = "s3://${var.bronze_bucket_id}/streams/$${event_date}/"
  }

  storage_descriptor {
    location      = "s3://${var.bronze_bucket_id}/streams/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.IgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "JsonSerDe"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"

      parameters = {
        "case.insensitive" = "TRUE"
      }
    }

    columns {
      name    = "artist_id"
      type    = "string"
      comment = "Artist identifier"
    }
    columns {
      name    = "artist_name"
      type    = "string"
      comment = "Artist name"
    }
    columns {
      name    = "title"
      type    = "string"
      comment = "Track title"
    }
    columns {
      name    = "album"
      type    = "string"
      comment = "Album name"
    }
    columns {
      name    = "duration_ms"
      type    = "bigint"
      comment = "Track duration in milliseconds"
    }
    columns {
      name    = "genre"
      type    = "string"
      comment = "Music genre"
    }
    columns {
      name    = "event_date"
      type    = "string"
      comment = "Partition date (yyyy/MM/dd)"
    }
    columns {
      name    = "event_timestamp"
      type    = "string"
      comment = "ISO 8601 timestamp of the listen event"
    }
    columns {
      name    = "user_id"
      type    = "string"
      comment = "Listener user identifier"
    }
    columns {
      name    = "user_country"
      type    = "string"
      comment = "Listener country code"
    }
    columns {
      name    = "platform"
      type    = "string"
      comment = "Streaming platform (mobile, web, api)"
    }
    columns {
      name    = "play_duration_seconds"
      type    = "int"
      comment = "Seconds actually played"
    }
    columns {
      name    = "skipped"
      type    = "boolean"
      comment = "Whether the track was skipped"
    }
    columns {
      name    = "event_id"
      type    = "string"
      comment = "Unique event identifier (UUID)"
    }
  }

  partition_keys {
    name = "event_date"
    type = "string"
  }
}

# ────────────────────────────────────────────
# SILVER DB: tracks table (cleaned Parquet)
# ────────────────────────────────────────────
resource "aws_glue_catalog_table" "silver_tracks" {
  name          = "tracks"
  database_name = aws_glue_catalog_database.silver.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                         = "TRUE"
    "classification"                 = "parquet"
    "projection.enabled"             = "true"
    "projection.year.type"           = "integer"
    "projection.year.range"          = "2020,2029"
    "projection.month.type"          = "integer"
    "projection.month.range"         = "1,12"
    "projection.day.type"            = "integer"
    "projection.day.range"           = "1,31"
    "projection.hour.type"           = "integer"
    "projection.hour.range"          = "0,23"
    "storage.location.template"      = "s3://${var.silver_bucket_id}/tracks/year=$${year}/month=$${month}/day=$${day}/hour=$${hour}/"
  }

  storage_descriptor {
    location      = "s3://${var.silver_bucket_id}/tracks/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "ParquetSerDe"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name    = "artist_id"
      type    = "string"
      comment = "Artist identifier"
    }
    columns {
      name    = "artist_name"
      type    = "string"
    }
    columns {
      name    = "title"
      type    = "string"
    }
    columns {
      name    = "album"
      type    = "string"
    }
    columns {
      name    = "duration_ms"
      type    = "bigint"
    }
    columns {
      name    = "genre"
      type    = "string"
    }
    columns {
      name    = "event_timestamp"
      type    = "string"
    }
    columns {
      name    = "user_id"
      type    = "string"
    }
    columns {
      name    = "user_country"
      type    = "string"
    }
    columns {
      name    = "platform"
      type    = "string"
    }
    columns {
      name    = "play_duration_seconds"
      type    = "int"
    }
    columns {
      name    = "skipped"
      type    = "boolean"
    }
    columns {
      name    = "processed_at"
      type    = "string"
      comment = "Timestamp when the Silver ETL processed this record"
    }
    columns {
      name    = "year"
      type    = "int"
    }
    columns {
      name    = "month"
      type    = "int"
    }
    columns {
      name    = "day"
      type    = "int"
    }
    columns {
      name    = "hour"
      type    = "int"
    }
    columns {
      name    = "event_id"
      type    = "string"
      comment = "Unique event identifier (UUID)"
    }
  }

  partition_keys {
    name = "year"
    type = "int"
  }
  partition_keys {
    name = "month"
    type = "int"
  }
  partition_keys {
    name = "day"
    type = "int"
  }
  partition_keys {
    name = "hour"
    type = "int"
  }
}

# ────────────────────────────────────────────
# GOLD DB: artist_streams table (aggregated Parquet)
# ────────────────────────────────────────────
resource "aws_glue_catalog_table" "gold_artist_streams" {
  name          = "artist_streams"
  database_name = aws_glue_catalog_database.gold.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                         = "TRUE"
    "classification"                 = "parquet"
    "projection.enabled"             = "true"
    "projection.year.type"           = "integer"
    "projection.year.range"          = "2020,2029"
    "projection.month.type"          = "integer"
    "projection.month.range"         = "1,12"
    "projection.day.type"            = "integer"
    "projection.day.range"           = "1,31"
    "projection.hour.type"           = "integer"
    "projection.hour.range"          = "0,23"
    "storage.location.template"      = "s3://${var.gold_bucket_id}/artist_streams/year=$${year}/month=$${month}/day=$${day}/hour=$${hour}/"
  }

  storage_descriptor {
    location      = "s3://${var.gold_bucket_id}/artist_streams/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "ParquetSerDe"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name    = "artist_id"
      type    = "string"
      comment = "Artist identifier (partition key for DDB)"
    }
    columns {
      name    = "artist_name"
      type    = "string"
    }
    columns {
      name    = "total_streams"
      type    = "bigint"
      comment = "Total stream count in the aggregation window"
    }
    columns {
      name    = "unique_listeners"
      type    = "bigint"
      comment = "Unique listener count in the aggregation window"
    }
    columns {
      name    = "avg_play_duration_seconds"
      type    = "double"
      comment = "Average play duration in the window"
    }
    columns {
      name    = "skip_rate"
      type    = "double"
      comment    = "Fraction of plays that were skipped"
    }
    columns {
      name    = "window_start"
      type    = "string"
      comment = "ISO 8601 start of the aggregation window"
    }
    columns {
      name    = "processing_timestamp"
      type    = "string"
      comment = "When this aggregation was computed"
    }
    columns {
      name    = "year"
      type    = "int"
    }
    columns {
      name    = "month"
      type    = "int"
    }
    columns {
      name    = "day"
      type    = "int"
    }
    columns {
      name    = "hour"
      type    = "int"
    }
  }

  partition_keys {
    name = "year"
    type = "int"
  }
  partition_keys {
    name = "month"
    type = "int"
  }
  partition_keys {
    name = "day"
    type = "int"
  }
  partition_keys {
    name = "hour"
    type = "int"
  }
}
