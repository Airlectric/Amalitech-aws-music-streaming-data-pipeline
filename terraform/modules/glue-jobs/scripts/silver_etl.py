import sys
from datetime import datetime
from awsglue.utils import getResolvedOptions
from pyspark.sql import SparkSession, functions as F
from pyspark.sql.types import StructType, StructField, StringType, LongType, IntegerType

args = getResolvedOptions(sys.argv, ["bronze_path", "silver_path"])
bronze_path = args["bronze_path"]
silver_path = args["silver_path"]

spark = SparkSession.builder.appName("SilverETL").getOrCreate()
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")

raw_schema = StructType([
    StructField("event_id", StringType()),
    StructField("user_id", StringType()),
    StructField("track_id", StringType()),
    StructField("title", StringType()),
    StructField("artist", StringType()),
    StructField("album", StringType()),
    StructField("genre", StringType()),
    StructField("duration_s", IntegerType()),
    StructField("listen_time_s", IntegerType()),
    StructField("timestamp", StringType()),
    StructField("region", StringType()),
    StructField("device", StringType()),
    StructField("subscription_tier", StringType()),
])

df = spark.read.schema(raw_schema).json(bronze_path)

df_cleaned = (
    df
    .dropDuplicates(["event_id"])
    .withColumn("artist", F.trim(F.col("artist")))
    .withColumn("title", F.trim(F.col("title")))
    .withColumn("album", F.trim(F.col("album")))
    .withColumn("genre", F.lower(F.trim(F.col("genre"))))
    .withColumn("device", F.lower(F.trim(F.col("device"))))
    .withColumn("region", F.upper(F.trim(F.col("region"))))
    .withColumn("processed_at", F.lit(datetime.utcnow().isoformat()))
    .withColumn("year", F.year(F.to_timestamp("timestamp")).cast("int"))
    .withColumn("month", F.month(F.to_timestamp("timestamp")).cast("int"))
    .withColumn("day", F.dayofmonth(F.to_timestamp("timestamp")).cast("int"))
    .withColumn("hour", F.hour(F.to_timestamp("timestamp")).cast("int"))
)

df_cleaned.write.mode("overwrite").partitionBy("year", "month", "day", "hour").parquet(silver_path)

spark.stop()
