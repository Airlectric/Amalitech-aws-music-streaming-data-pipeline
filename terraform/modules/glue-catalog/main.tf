resource "aws_glue_catalog_database" "bronze" {
  name         = "${var.environment}_bronze_db"
  description  = "Raw landing and reference data"
  location_uri = "s3://${var.bronze_bucket_id}/"
}

resource "aws_glue_catalog_database" "silver" {
  name         = "${var.environment}_silver_db"
  description  = "Curated streaming data"
  location_uri = "s3://${var.silver_bucket_id}/"
}

resource "aws_glue_catalog_database" "gold" {
  name         = "${var.environment}_gold_db"
  description  = "Serving-ready KPI datasets"
  location_uri = "s3://${var.gold_bucket_id}/"
}

resource "aws_glue_catalog_table" "bronze_streams" {
  name          = "streams"
  database_name = aws_glue_catalog_database.bronze.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                                = "TRUE"
    classification                          = "csv"
    "projection.enabled"                    = "true"
    "projection.landing_date.type"          = "date"
    "projection.landing_date.range"         = "2024-01-01,NOW"
    "projection.landing_date.format"        = "yyyy-MM-dd"
    "projection.landing_date.interval"      = "1"
    "projection.landing_date.interval.unit" = "DAYS"
    "skip.header.line.count"                = "1"
    "storage.location.template"             = "s3://${var.bronze_bucket_id}/streams/landing_date=$${landing_date}/"
  }

  storage_descriptor {
    location      = "s3://${var.bronze_bucket_id}/streams/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.OpenCSVSerde"
    }

    columns {
      name = "user_id"
      type = "int"
    }

    columns {
      name = "track_id"
      type = "string"
    }

    columns {
      name = "listen_time"
      type = "string"
    }
  }

  partition_keys {
    name = "landing_date"
    type = "string"
  }
}

resource "aws_glue_catalog_table" "bronze_songs" {
  name          = "songs"
  database_name = aws_glue_catalog_database.bronze.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                 = "TRUE"
    classification           = "csv"
    "skip.header.line.count" = "1"
  }

  storage_descriptor {
    location      = "s3://${var.bronze_bucket_id}/reference/songs/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.OpenCSVSerde"
    }

    columns {
      name = "id"
      type = "int"
    }

    columns {
      name = "track_id"
      type = "string"
    }

    columns {
      name = "artists"
      type = "string"
    }

    columns {
      name = "album_name"
      type = "string"
    }

    columns {
      name = "track_name"
      type = "string"
    }

    columns {
      name = "popularity"
      type = "int"
    }

    columns {
      name = "duration_ms"
      type = "bigint"
    }

    columns {
      name = "explicit"
      type = "string"
    }

    columns {
      name = "danceability"
      type = "string"
    }

    columns {
      name = "energy"
      type = "string"
    }

    columns {
      name = "key"
      type = "string"
    }

    columns {
      name = "loudness"
      type = "string"
    }

    columns {
      name = "mode"
      type = "string"
    }

    columns {
      name = "speechiness"
      type = "string"
    }

    columns {
      name = "acousticness"
      type = "string"
    }

    columns {
      name = "instrumentalness"
      type = "string"
    }

    columns {
      name = "liveness"
      type = "string"
    }

    columns {
      name = "valence"
      type = "string"
    }

    columns {
      name = "tempo"
      type = "string"
    }

    columns {
      name = "time_signature"
      type = "string"
    }

    columns {
      name = "track_genre"
      type = "string"
    }
  }
}

resource "aws_glue_catalog_table" "bronze_users" {
  name          = "users"
  database_name = aws_glue_catalog_database.bronze.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                 = "TRUE"
    classification           = "csv"
    "skip.header.line.count" = "1"
  }

  storage_descriptor {
    location      = "s3://${var.bronze_bucket_id}/reference/users/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.OpenCSVSerde"
    }

    columns {
      name = "user_id"
      type = "int"
    }

    columns {
      name = "user_name"
      type = "string"
    }

    columns {
      name = "user_age"
      type = "int"
    }

    columns {
      name = "user_country"
      type = "string"
    }

    columns {
      name = "created_at"
      type = "string"
    }
  }
}

resource "aws_glue_catalog_table" "silver_streams_curated" {
  name          = "streams_curated"
  database_name = aws_glue_catalog_database.silver.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                              = "TRUE"
    classification                        = "parquet"
    "projection.enabled"                  = "true"
    "projection.event_date.type"          = "date"
    "projection.event_date.range"         = "2024-01-01,NOW"
    "projection.event_date.format"        = "yyyy-MM-dd"
    "projection.event_date.interval"      = "1"
    "projection.event_date.interval.unit" = "DAYS"
    "storage.location.template"           = "s3://${var.silver_bucket_id}/streams_curated/event_date=$${event_date}/"
  }

  storage_descriptor {
    location      = "s3://${var.silver_bucket_id}/streams_curated/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "user_id"
      type = "int"
    }

    columns {
      name = "track_id"
      type = "string"
    }

    columns {
      name = "track_name"
      type = "string"
    }

    columns {
      name = "artists"
      type = "string"
    }

    columns {
      name = "album_name"
      type = "string"
    }

    columns {
      name = "genre"
      type = "string"
    }

    columns {
      name = "listen_time"
      type = "string"
    }

    columns {
      name = "listen_ts"
      type = "timestamp"
    }

    columns {
      name = "duration_ms"
      type = "bigint"
    }

    columns {
      name = "listen_seconds"
      type = "double"
    }

    columns {
      name = "user_country"
      type = "string"
    }

    columns {
      name = "source_file"
      type = "string"
    }

    columns {
      name = "ingested_at"
      type = "string"
    }

    columns {
      name = "source_execution_id"
      type = "string"
    }
  }

  partition_keys {
    name = "event_date"
    type = "string"
  }
}

resource "aws_glue_catalog_table" "gold_genre_kpis_daily" {
  name          = "genre_kpis_daily"
  database_name = aws_glue_catalog_database.gold.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                        = "TRUE"
    classification                  = "parquet"
    "projection.enabled"            = "true"
    "projection.date.type"          = "date"
    "projection.date.range"         = "2024-01-01,NOW"
    "projection.date.format"        = "yyyy-MM-dd"
    "projection.date.interval"      = "1"
    "projection.date.interval.unit" = "DAYS"
    "storage.location.template"     = "s3://${var.gold_bucket_id}/genre_kpis_daily/date=$${date}/"
  }

  storage_descriptor {
    location      = "s3://${var.gold_bucket_id}/genre_kpis_daily/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "genre"
      type = "string"
    }

    columns {
      name = "listen_count"
      type = "bigint"
    }

    columns {
      name = "unique_listeners"
      type = "bigint"
    }

    columns {
      name = "total_listen_seconds"
      type = "double"
    }

    columns {
      name = "avg_listen_seconds_per_user"
      type = "double"
    }

    columns {
      name = "ingested_at"
      type = "string"
    }

    columns {
      name = "source_execution_id"
      type = "string"
    }
  }

  partition_keys {
    name = "date"
    type = "string"
  }
}

resource "aws_glue_catalog_table" "gold_top_songs_by_genre_daily" {
  name          = "top_songs_by_genre_daily"
  database_name = aws_glue_catalog_database.gold.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                        = "TRUE"
    classification                  = "parquet"
    "projection.enabled"            = "true"
    "projection.date.type"          = "date"
    "projection.date.range"         = "2024-01-01,NOW"
    "projection.date.format"        = "yyyy-MM-dd"
    "projection.date.interval"      = "1"
    "projection.date.interval.unit" = "DAYS"
    "storage.location.template"     = "s3://${var.gold_bucket_id}/top_songs_by_genre_daily/date=$${date}/"
  }

  storage_descriptor {
    location      = "s3://${var.gold_bucket_id}/top_songs_by_genre_daily/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "genre"
      type = "string"
    }

    columns {
      name = "genre_date"
      type = "string"
    }

    columns {
      name = "rank"
      type = "int"
    }

    columns {
      name = "track_id"
      type = "string"
    }

    columns {
      name = "track_name"
      type = "string"
    }

    columns {
      name = "play_count"
      type = "bigint"
    }

    columns {
      name = "ingested_at"
      type = "string"
    }

    columns {
      name = "source_execution_id"
      type = "string"
    }
  }

  partition_keys {
    name = "date"
    type = "string"
  }
}

resource "aws_glue_catalog_table" "gold_top_genres_daily" {
  name          = "top_genres_daily"
  database_name = aws_glue_catalog_database.gold.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL                        = "TRUE"
    classification                  = "parquet"
    "projection.enabled"            = "true"
    "projection.date.type"          = "date"
    "projection.date.range"         = "2024-01-01,NOW"
    "projection.date.format"        = "yyyy-MM-dd"
    "projection.date.interval"      = "1"
    "projection.date.interval.unit" = "DAYS"
    "storage.location.template"     = "s3://${var.gold_bucket_id}/top_genres_daily/date=$${date}/"
  }

  storage_descriptor {
    location      = "s3://${var.gold_bucket_id}/top_genres_daily/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "rank"
      type = "int"
    }

    columns {
      name = "genre"
      type = "string"
    }

    columns {
      name = "listen_count"
      type = "bigint"
    }

    columns {
      name = "ingested_at"
      type = "string"
    }

    columns {
      name = "source_execution_id"
      type = "string"
    }
  }

  partition_keys {
    name = "date"
    type = "string"
  }
}
