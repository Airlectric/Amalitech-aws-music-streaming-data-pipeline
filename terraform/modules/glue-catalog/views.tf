# ─────────────────────────────────────────────────────────────────────────────
# ATHENA VIEWS OVER GOLD TABLES
#
# These VIRTUAL_VIEW tables are stored in the Glue Catalog and queried by
# Athena (Presto engine). They expose only the analyst-facing columns of the
# three gold KPI tables, hiding internal ingestion metadata
# (ingested_at, source_execution_id, genre_date).
#
# Column types use the Presto type system (varchar, bigint, double, integer)
# because Athena views are compiled and stored by the Presto/Trino engine.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  _gold_db = aws_glue_catalog_database.gold.name

  # ── v_genre_kpis ─────────────────────────────────────────────────────────
  _v_genre_kpis_sql = join(" ", [
    "SELECT",
    "genre,",
    "date,",
    "listen_count,",
    "unique_listeners,",
    "round(total_listen_seconds / 3600.0, 2) AS total_listen_hours,",
    "round(avg_listen_seconds_per_user, 1) AS avg_listen_secs_per_user",
    "FROM \"${local._gold_db}\".\"genre_kpis_daily\"",
  ])

  _v_genre_kpis_encoded = base64encode(jsonencode({
    originalSql = local._v_genre_kpis_sql
    catalog     = "awsdatacatalog"
    schema      = local._gold_db
    columns = [
      { name = "genre", type = "varchar" },
      { name = "date", type = "varchar" },
      { name = "listen_count", type = "bigint" },
      { name = "unique_listeners", type = "bigint" },
      { name = "total_listen_hours", type = "double" },
      { name = "avg_listen_secs_per_user", type = "double" },
    ]
  }))

  # ── v_top_songs ───────────────────────────────────────────────────────────
  _v_top_songs_sql = join(" ", [
    "SELECT",
    "genre,",
    "date,",
    "rank,",
    "track_id,",
    "track_name,",
    "play_count",
    "FROM \"${local._gold_db}\".\"top_songs_by_genre_daily\"",
  ])

  _v_top_songs_encoded = base64encode(jsonencode({
    originalSql = local._v_top_songs_sql
    catalog     = "awsdatacatalog"
    schema      = local._gold_db
    columns = [
      { name = "genre", type = "varchar" },
      { name = "date", type = "varchar" },
      { name = "rank", type = "integer" },
      { name = "track_id", type = "varchar" },
      { name = "track_name", type = "varchar" },
      { name = "play_count", type = "bigint" },
    ]
  }))

  # ── v_top_genres ──────────────────────────────────────────────────────────
  _v_top_genres_sql = join(" ", [
    "SELECT",
    "date,",
    "rank,",
    "genre,",
    "listen_count",
    "FROM \"${local._gold_db}\".\"top_genres_daily\"",
  ])

  _v_top_genres_encoded = base64encode(jsonencode({
    originalSql = local._v_top_genres_sql
    catalog     = "awsdatacatalog"
    schema      = local._gold_db
    columns = [
      { name = "date", type = "varchar" },
      { name = "rank", type = "integer" },
      { name = "genre", type = "varchar" },
      { name = "listen_count", type = "bigint" },
    ]
  }))
}

# ── v_genre_kpis ─────────────────────────────────────────────────────────────
resource "aws_glue_catalog_table" "view_genre_kpis" {
  name          = "v_genre_kpis"
  database_name = aws_glue_catalog_database.gold.name
  table_type    = "VIRTUAL_VIEW"

  view_original_text = "/* Presto View: ${local._v_genre_kpis_encoded} */"
  view_expanded_text = "/* Presto View */"

  storage_descriptor {
    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"
    }

    columns {
      name = "genre"
      type = "varchar"
    }
    columns {
      name = "date"
      type = "varchar"
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
      name = "total_listen_hours"
      type = "double"
    }
    columns {
      name = "avg_listen_secs_per_user"
      type = "double"
    }
  }
}

# ── v_top_songs ───────────────────────────────────────────────────────────────
resource "aws_glue_catalog_table" "view_top_songs" {
  name          = "v_top_songs"
  database_name = aws_glue_catalog_database.gold.name
  table_type    = "VIRTUAL_VIEW"

  view_original_text = "/* Presto View: ${local._v_top_songs_encoded} */"
  view_expanded_text = "/* Presto View */"

  storage_descriptor {
    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"
    }

    columns {
      name = "genre"
      type = "varchar"
    }
    columns {
      name = "date"
      type = "varchar"
    }
    columns {
      name = "rank"
      type = "int"
    }
    columns {
      name = "track_id"
      type = "varchar"
    }
    columns {
      name = "track_name"
      type = "varchar"
    }
    columns {
      name = "play_count"
      type = "bigint"
    }
  }
}

# ── v_top_genres ──────────────────────────────────────────────────────────────
resource "aws_glue_catalog_table" "view_top_genres" {
  name          = "v_top_genres"
  database_name = aws_glue_catalog_database.gold.name
  table_type    = "VIRTUAL_VIEW"

  view_original_text = "/* Presto View: ${local._v_top_genres_encoded} */"
  view_expanded_text = "/* Presto View */"

  storage_descriptor {
    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"
    }

    columns {
      name = "date"
      type = "varchar"
    }
    columns {
      name = "rank"
      type = "int"
    }
    columns {
      name = "genre"
      type = "varchar"
    }
    columns {
      name = "listen_count"
      type = "bigint"
    }
  }
}
