import sys
from datetime import datetime, timezone
from pyspark.sql import SparkSession, functions as F
from pyspark.sql.types import StringType

GOLD_PATH = sys.argv[1]
TABLE_HOURLY = sys.argv[2]
TABLE_DAILY = sys.argv[3]
TABLE_MONTHLY = sys.argv[4]

spark = SparkSession.builder.appName("DDBETL").getOrCreate()
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")

df = spark.read.parquet(GOLD_PATH)

hourly = df.withColumn("hour_ts", F.concat_ws(
    "-",
    F.col("year").cast("string"),
    F.lpad(F.col("month").cast("string"), 2, "0"),
    F.lpad(F.col("day").cast("string"), 2, "0"),
    F.lit("T"),
    F.lpad(F.col("hour").cast("string"), 2, "0"),
    F.lit(":00:00"),
)).withColumn(
    "ttl_expires_at",
    F.unix_timestamp(F.lit(datetime.now(timezone.utc).isoformat())) + (90 * 86400)
).select(
    "artist_id",
    F.col("hour_ts").alias("hour_ts"),
    "total_streams",
    "unique_listeners",
    "avg_play_duration_seconds",
    "skip_rate",
    "ttl_expires_at",
)

daily = df.groupBy(
    "artist_id",
    "year",
    "month",
    "day",
).agg(
    F.sum("total_streams").alias("total_streams"),
    F.sum("unique_listeners").alias("unique_listeners"),
    F.avg("avg_play_duration_seconds").alias("avg_play_duration_seconds"),
    F.avg("skip_rate").alias("skip_rate"),
).withColumn("date", F.concat_ws(
    "-",
    F.col("year").cast("string"),
    F.lpad(F.col("month").cast("string"), 2, "0"),
    F.lpad(F.col("day").cast("string"), 2, "0"),
)).withColumn(
    "ttl_expires_at",
    F.unix_timestamp(F.lit(datetime.now(timezone.utc).isoformat())) + (365 * 86400)
).select(
    "artist_id",
    "date",
    "total_streams",
    "unique_listeners",
    "avg_play_duration_seconds",
    "skip_rate",
    "ttl_expires_at",
)

monthly = df.groupBy(
    "artist_id",
    "year",
    "month",
).agg(
    F.sum("total_streams").alias("total_streams"),
    F.sum("unique_listeners").alias("unique_listeners"),
    F.avg("avg_play_duration_seconds").alias("avg_play_duration_seconds"),
    F.avg("skip_rate").alias("skip_rate"),
).withColumn("month_str", F.concat_ws(
    "-",
    F.col("year").cast("string"),
    F.lpad(F.col("month").cast("string"), 2, "0"),
)).select(
    F.col("artist_id").alias("artist_id"),
    F.col("month_str").alias("month"),
    "total_streams",
    "unique_listeners",
    "avg_play_duration_seconds",
    "skip_rate",
)

now = datetime.now(timezone.utc).isoformat()

hourly.write.mode("append").format("dynamodb").option("tableName", TABLE_HOURLY).option("writeBatchSize", 25).save()
daily.write.mode("append").format("dynamodb").option("tableName", TABLE_DAILY).option("writeBatchSize", 25).save()
monthly.write.mode("append").format("dynamodb").option("tableName", TABLE_MONTHLY).option("writeBatchSize", 25).save()

spark.stop()
