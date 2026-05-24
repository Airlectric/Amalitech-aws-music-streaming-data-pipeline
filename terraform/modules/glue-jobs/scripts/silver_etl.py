import sys
from datetime import datetime
from pyspark.sql import SparkSession, functions as F
from pyspark.sql.types import StructType, StructField, StringType, LongType, IntegerType, BooleanType, DoubleType

BRONZE_PATH = sys.argv[1]
SILVER_PATH = sys.argv[2]

spark = SparkSession.builder.appName("SilverETL").getOrCreate()
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")

raw_schema = StructType([
    StructField("artist_id", StringType()),
    StructField("artist_name", StringType()),
    StructField("title", StringType()),
    StructField("album", StringType()),
    StructField("duration_ms", LongType()),
    StructField("genre", StringType()),
    StructField("event_date", StringType()),
    StructField("event_timestamp", StringType()),
    StructField("user_id", StringType()),
    StructField("user_country", StringType()),
    StructField("platform", StringType()),
    StructField("play_duration_seconds", IntegerType()),
    StructField("skipped", BooleanType()),
])

df = spark.read.schema(raw_schema).json(BRONZE_PATH)

df_cleaned = (
    df
    .dropDuplicates(["artist_id", "title", "event_timestamp", "user_id"])
    .withColumn("artist_name", F.trim(F.col("artist_name")))
    .withColumn("title", F.trim(F.col("title")))
    .withColumn("album", F.trim(F.col("album")))
    .withColumn("genre", F.lower(F.trim(F.col("genre"))))
    .withColumn("platform", F.lower(F.trim(F.col("platform"))))
    .withColumn("user_country", F.upper(F.trim(F.col("user_country"))))
    .withColumn("processed_at", F.lit(datetime.utcnow().isoformat()))
    .withColumn("year", F.year(F.to_timestamp("event_timestamp")).cast("int"))
    .withColumn("month", F.month(F.to_timestamp("event_timestamp")).cast("int"))
    .withColumn("day", F.dayofmonth(F.to_timestamp("event_timestamp")).cast("int"))
    .withColumn("hour", F.hour(F.to_timestamp("event_timestamp")).cast("int"))
)

df_cleaned.write.mode("overwrite").partitionBy("year", "month", "day", "hour").parquet(SILVER_PATH)

spark.stop()
