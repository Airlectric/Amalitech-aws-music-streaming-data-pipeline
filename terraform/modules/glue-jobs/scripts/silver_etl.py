import sys

from awsglue.utils import getResolvedOptions
from pyspark.sql import SparkSession, functions as F
from pyspark.sql.types import IntegerType, LongType, StringType, StructField, StructType

args = getResolvedOptions(
    sys.argv,
    ["bronze_bucket", "stream_key", "silver_path"],
)

bronze_bucket = args["bronze_bucket"]
stream_key = args["stream_key"]
silver_path = args["silver_path"].rstrip("/")

stream_path = f"s3://{bronze_bucket}/{stream_key}"
songs_path = f"s3://{bronze_bucket}/reference/songs/"
users_path = f"s3://{bronze_bucket}/reference/users/"

spark = SparkSession.builder.appName("SilverETL").getOrCreate()
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")

streams_schema = StructType(
    [
        StructField("user_id", IntegerType(), False),
        StructField("track_id", StringType(), False),
        StructField("listen_time", StringType(), False),
    ]
)

songs_schema = StructType(
    [
        StructField("id", IntegerType(), True),
        StructField("track_id", StringType(), False),
        StructField("artists", StringType(), True),
        StructField("album_name", StringType(), True),
        StructField("track_name", StringType(), True),
        StructField("popularity", IntegerType(), True),
        StructField("duration_ms", LongType(), True),
        StructField("explicit", StringType(), True),
        StructField("danceability", StringType(), True),
        StructField("energy", StringType(), True),
        StructField("key", StringType(), True),
        StructField("loudness", StringType(), True),
        StructField("mode", StringType(), True),
        StructField("speechiness", StringType(), True),
        StructField("acousticness", StringType(), True),
        StructField("instrumentalness", StringType(), True),
        StructField("liveness", StringType(), True),
        StructField("valence", StringType(), True),
        StructField("tempo", StringType(), True),
        StructField("time_signature", StringType(), True),
        StructField("track_genre", StringType(), True),
    ]
)

users_schema = StructType(
    [
        StructField("user_id", IntegerType(), False),
        StructField("user_name", StringType(), True),
        StructField("user_age", IntegerType(), True),
        StructField("user_country", StringType(), True),
        StructField("created_at", StringType(), True),
    ]
)

streams_df = (
    spark.read.option("header", "true")
    .schema(streams_schema)
    .csv(stream_path)
    .dropna(subset=["user_id", "track_id", "listen_time"])
    .dropDuplicates(["user_id", "track_id", "listen_time"])
    .withColumn("listen_ts", F.to_timestamp("listen_time", "yyyy-MM-dd HH:mm:ss"))
    .dropna(subset=["listen_ts"])
)

songs_df = (
    spark.read.option("header", "true")
    .schema(songs_schema)
    .csv(songs_path)
    .select(
        "track_id",
        "artists",
        "album_name",
        "track_name",
        "duration_ms",
        "track_genre",
    )
)

users_df = (
    spark.read.option("header", "true")
    .schema(users_schema)
    .csv(users_path)
    .select("user_id", "user_country")
)

curated_df = (
    streams_df.join(songs_df, on="track_id", how="inner")
    .join(users_df, on="user_id", how="left")
    .withColumn("event_date", F.to_date("listen_ts"))
    .withColumn("genre", F.lower(F.trim(F.col("track_genre"))))
    .withColumn("listen_seconds", F.col("duration_ms") / F.lit(1000.0))
    .withColumn("source_file", F.lit(stream_path))
    .select(
        "user_id",
        "track_id",
        "track_name",
        "artists",
        "album_name",
        "genre",
        "listen_time",
        "listen_ts",
        "event_date",
        "duration_ms",
        "listen_seconds",
        "user_country",
        "source_file",
    )
)

(
    curated_df.write.mode("overwrite")
    .partitionBy("event_date")
    .parquet(f"{silver_path}/streams_curated")
)

spark.stop()
