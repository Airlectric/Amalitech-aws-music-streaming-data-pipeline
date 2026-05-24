import sys
from datetime import datetime
from awsglue.utils import getResolvedOptions
from pyspark.sql import SparkSession, functions as F
from pyspark.sql.types import (
    StructType,
    StructField,
    StringType,
    LongType,
    IntegerType,
    BooleanType,
)

args = getResolvedOptions(sys.argv, ["bronze_path", "silver_path"])
bronze_path = args["bronze_path"]
silver_path = args["silver_path"]

spark = SparkSession.builder.appName("SilverETL").getOrCreate()
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")
spark._jsc.hadoopConfiguration().set(
    "mapreduce.input.fileinputformat.input.dir.recursive", "true"
)

raw_schema = StructType(
    [
        StructField("event_id", StringType()),
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
    ]
)

df = (
    spark.read.schema(raw_schema)
    .option("recursiveFileLookup", "true")
    .json(bronze_path)
)

df_cleaned = (
    df.dropDuplicates(["event_id"])
    .withColumn("artist_id", F.trim(F.col("artist_id")))
    .withColumn("artist_name", F.trim(F.col("artist_name")))
    .withColumn("title", F.trim(F.col("title")))
    .withColumn("album", F.trim(F.col("album")))
    .withColumn("genre", F.lower(F.trim(F.col("genre"))))
    .withColumn("user_country", F.trim(F.col("user_country")))
    .withColumn("platform", F.lower(F.trim(F.col("platform"))))
    .withColumn("processed_at", F.lit(datetime.utcnow().isoformat()))
    .withColumn(
        "year",
        F.year(F.to_timestamp("event_timestamp", "yyyy-MM-dd HH:mm:ss")).cast("int"),
    )
    .withColumn(
        "month",
        F.month(F.to_timestamp("event_timestamp", "yyyy-MM-dd HH:mm:ss")).cast("int"),
    )
    .withColumn(
        "day",
        F.dayofmonth(F.to_timestamp("event_timestamp", "yyyy-MM-dd HH:mm:ss")).cast(
            "int"
        ),
    )
    .withColumn(
        "hour",
        F.hour(F.to_timestamp("event_timestamp", "yyyy-MM-dd HH:mm:ss")).cast("int"),
    )
)

df_cleaned.write.mode("overwrite").partitionBy("year", "month", "day", "hour").parquet(
    silver_path
)

spark.stop()
