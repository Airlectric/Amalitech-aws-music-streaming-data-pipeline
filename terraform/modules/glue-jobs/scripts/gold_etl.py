import sys
from datetime import datetime
from pyspark.sql import SparkSession, functions as F

SILVER_PATH = sys.argv[1]
GOLD_PATH = sys.argv[2]

spark = SparkSession.builder.appName("GoldETL").getOrCreate()
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")

df = spark.read.parquet(SILVER_PATH)

agg = (
    df
    .groupBy(
        "artist_id",
        "artist_name",
        "year",
        "month",
        "day",
        "hour",
    )
    .agg(
        F.count("*").alias("total_streams"),
        F.countDistinct("user_id").alias("unique_listeners"),
        F.avg("play_duration_seconds").alias("avg_play_duration_seconds"),
        F.avg(F.when(F.col("skipped") == True, 1).otherwise(0)).alias("skip_rate"),
    )
    .withColumn("window_start", F.concat_ws(
        "-",
        F.col("year").cast("string"),
        F.lpad(F.col("month").cast("string"), 2, "0"),
        F.lpad(F.col("day").cast("string"), 2, "0"),
        F.lit("T"),
        F.lpad(F.col("hour").cast("string"), 2, "0"),
        F.lit(":00:00"),
    ))
    .withColumn("processing_timestamp", F.lit(datetime.utcnow().isoformat()))
)

agg.write.mode("overwrite").partitionBy("year", "month", "day", "hour").parquet(GOLD_PATH)

spark.stop()
