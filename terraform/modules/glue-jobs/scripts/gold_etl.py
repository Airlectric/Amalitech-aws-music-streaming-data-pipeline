import sys

from pyspark.sql import SparkSession, Window
from pyspark.sql import functions as F


def _get_arg_default(key, default):
    """Return an optional Glue job arg value, falling back to default if absent."""
    for i, token in enumerate(sys.argv):
        if token == f"--{key}" and i + 1 < len(sys.argv):
            return sys.argv[i + 1]
    return default


def compute_genre_kpis(df):
    """Aggregate listen counts, unique listeners, and listening time by genre per day."""
    return (
        df.groupBy("genre", "event_date")
        .agg(
            F.count("*").alias("listen_count"),
            F.countDistinct("user_id").alias("unique_listeners"),
            F.sum("listen_seconds").alias("total_listen_seconds"),
            F.avg("listen_seconds").alias("avg_listen_seconds_per_user"),
        )
        .withColumn("date", F.date_format("event_date", "yyyy-MM-dd"))
        .drop("event_date")
    )


def compute_top_songs(df, n=3):
    """Rank the top-n songs per genre per day by play count (track_id as tie-break)."""
    song_window = Window.partitionBy("genre", "event_date").orderBy(
        F.desc("play_count"), F.asc("track_id")
    )
    return (
        df.groupBy("genre", "event_date", "track_id", "track_name")
        .agg(F.count("*").alias("play_count"))
        .withColumn("rank", F.row_number().over(song_window))
        .filter(F.col("rank") <= n)
        .withColumn("date", F.date_format("event_date", "yyyy-MM-dd"))
        .withColumn("genre_date", F.concat_ws("#", "genre", "date"))
        .drop("event_date")
    )


def compute_top_genres(df, n=5):
    """Rank the top-n genres per day by listen count (genre name as tie-break)."""
    genre_window = Window.partitionBy("event_date").orderBy(
        F.desc("listen_count"), F.asc("genre")
    )
    return (
        df.groupBy("event_date", "genre")
        .agg(F.count("*").alias("listen_count"))
        .withColumn("rank", F.row_number().over(genre_window))
        .filter(F.col("rank") <= n)
        .withColumn("date", F.date_format("event_date", "yyyy-MM-dd"))
        .drop("event_date")
    )


def main():
    from awsglue.utils import getResolvedOptions

    args = getResolvedOptions(sys.argv, ["silver_path", "gold_path", "run_date"])
    silver_path = args["silver_path"].rstrip("/")
    gold_path = args["gold_path"].rstrip("/")
    run_date = args["run_date"]
    execution_start_time = _get_arg_default("execution_start_time", "unknown")
    execution_id = _get_arg_default("execution_id", "unknown")

    spark = SparkSession.builder.appName("GoldETL").getOrCreate()
    spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")

    # Read only the single-day partition rather than the whole table.
    # basePath tells Spark the Hive root so it re-materialises the `event_date`
    # column from the directory name (partitionBy strips it from Parquet files).
    partition_path = f"{silver_path}/streams_curated/event_date={run_date}"
    try:
        silver_df = (
            spark.read
            .option("basePath", f"{silver_path}/streams_curated")
            .parquet(partition_path)
        )
        if not silver_df.head(1):
            raise ValueError(
                f"Silver partition for run_date={run_date} is empty at {partition_path}. "
                "Verify that silver_etl completed successfully before running gold_etl."
            )
    except ValueError:
        raise
    except Exception as exc:
        raise RuntimeError(
            f"Cannot read Silver partition for run_date={run_date} at {partition_path}. "
            f"Ensure silver_etl completed successfully before running gold_etl. "
            f"Original error: {exc}"
        ) from exc

    genre_kpis_df = (
        compute_genre_kpis(silver_df)
        .withColumn("ingested_at", F.lit(execution_start_time))
        .withColumn("source_execution_id", F.lit(execution_id))
    )
    top_songs_df = (
        compute_top_songs(silver_df)
        .withColumn("ingested_at", F.lit(execution_start_time))
        .withColumn("source_execution_id", F.lit(execution_id))
    )
    top_genres_df = (
        compute_top_genres(silver_df)
        .withColumn("ingested_at", F.lit(execution_start_time))
        .withColumn("source_execution_id", F.lit(execution_id))
    )

    genre_kpis_df.write.mode("overwrite").partitionBy("date").parquet(
        f"{gold_path}/genre_kpis_daily"
    )
    top_songs_df.write.mode("overwrite").partitionBy("date").parquet(
        f"{gold_path}/top_songs_by_genre_daily"
    )
    top_genres_df.write.mode("overwrite").partitionBy("date").parquet(
        f"{gold_path}/top_genres_daily"
    )

    spark.stop()


if __name__ == "__main__":
    main()
