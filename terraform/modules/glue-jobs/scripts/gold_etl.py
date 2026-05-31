import sys

from awsglue.utils import getResolvedOptions
from pyspark.sql import SparkSession, Window
from pyspark.sql import functions as F

args = getResolvedOptions(sys.argv, ["silver_path", "gold_path", "run_date"])
silver_path = args["silver_path"].rstrip("/")
gold_path = args["gold_path"].rstrip("/")
run_date = args["run_date"]

spark = SparkSession.builder.appName("GoldETL").getOrCreate()
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")

silver_df = spark.read.parquet(f"{silver_path}/streams_curated").filter(
    F.col("event_date") == F.to_date(F.lit(run_date))
)

genre_kpis_df = (
    silver_df.groupBy("genre", "event_date")
    .agg(
        F.count("*").alias("listen_count"),
        F.countDistinct("user_id").alias("unique_listeners"),
        F.sum("listen_seconds").alias("total_listen_seconds"),
        F.avg("listen_seconds").alias("avg_listen_seconds_per_user"),
    )
    .withColumn("date", F.date_format("event_date", "yyyy-MM-dd"))
    .drop("event_date")
)

song_window = Window.partitionBy("genre", "event_date").orderBy(
    F.desc("play_count"), F.asc("track_id")
)
top_songs_df = (
    silver_df.groupBy("genre", "event_date", "track_id", "track_name")
    .agg(F.count("*").alias("play_count"))
    .withColumn("rank", F.row_number().over(song_window))
    .filter(F.col("rank") <= 3)
    .withColumn("date", F.date_format("event_date", "yyyy-MM-dd"))
    .withColumn("genre_date", F.concat_ws("#", "genre", "date"))
    .drop("event_date")
)

genre_window = Window.partitionBy("event_date").orderBy(
    F.desc("listen_count"), F.asc("genre")
)
top_genres_df = (
    silver_df.groupBy("event_date", "genre")
    .agg(F.count("*").alias("listen_count"))
    .withColumn("rank", F.row_number().over(genre_window))
    .filter(F.col("rank") <= 5)
    .withColumn("date", F.date_format("event_date", "yyyy-MM-dd"))
    .drop("event_date")
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
