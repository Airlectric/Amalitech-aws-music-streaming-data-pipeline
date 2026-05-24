resource "aws_s3_bucket" "this" {
  for_each = local.bucket_name

  bucket        = each.value
  force_destroy = false

  tags = merge(local.common_tags, { Name = each.key })
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = { for k, v in local.bucket_name : k => v if k != "athena-results" }

  bucket = aws_s3_bucket.this[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = local.bucket_name

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = local.bucket_name

  bucket = aws_s3_bucket.this[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = local.bucket_name

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_policy" "tls_only" {
  for_each = local.bucket_name

  bucket = aws_s3_bucket.this[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureConnections"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.this[each.key].arn,
          "${aws_s3_bucket.this[each.key].arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_logging" "this" {
  for_each = { for k, v in local.bucket_name : k => v if k != "access_logs" }

  bucket = aws_s3_bucket.this[each.key].id

  target_bucket = aws_s3_bucket.this["access_logs"].id
  target_prefix = "logs/${each.key}/"
}

# Bronze lifecycle: Std -> IA @30d -> Glacier @90d -> Expire @365d
resource "aws_s3_bucket_lifecycle_configuration" "bronze" {
  bucket = aws_s3_bucket.this["bronze"].id

  rule {
    id     = "bronze-lifecycle"
    status = "Enabled"

    filter {
      prefix = "streams/"
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }

  rule {
    id     = "bronze-reference-noncurrent"
    status = "Enabled"

    filter {
      prefix = "reference/"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# Silver lifecycle: Std -> IA @60d -> Glacier @180d
resource "aws_s3_bucket_lifecycle_configuration" "silver" {
  bucket = aws_s3_bucket.this["silver"].id

  rule {
    id     = "silver-lifecycle"
    status = "Enabled"

    filter {}

    transition {
      days          = 60
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 180
      storage_class = "GLACIER"
    }
  }
}

# Gold lifecycle: Std -> IA @90d
resource "aws_s3_bucket_lifecycle_configuration" "gold" {
  bucket = aws_s3_bucket.this["gold"].id

  rule {
    id     = "gold-lifecycle"
    status = "Enabled"

    filter {}

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
  }
}

# Archive lifecycle: Direct to Glacier Deep Archive @1d, expire @7yr
resource "aws_s3_bucket_lifecycle_configuration" "archive" {
  bucket = aws_s3_bucket.this["archive"].id

  rule {
    id     = "archive-lifecycle"
    status = "Enabled"

    filter {}

    transition {
      days          = 1
      storage_class = "DEEP_ARCHIVE"
    }

    expiration {
      days = 2555
    }
  }
}

# Glue scripts: versioning only (no lifecycle transitions needed)
# Athena results: Expire @14d
resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  bucket = aws_s3_bucket.this["athena_results"].id

  rule {
    id     = "athena-results-expiration"
    status = "Enabled"

    filter {}

    expiration {
      days = 14
    }
  }
}

# Access logs: Expire @365d
resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.this["access_logs"].id

  rule {
    id     = "access-logs-expiration"
    status = "Enabled"

    filter {}

    expiration {
      days = var.log_retention_days
    }
  }
}

resource "aws_s3_bucket_notification" "bronze_events" {
  bucket = aws_s3_bucket.this["bronze"].id

  eventbridge = true
}

# Glue scripts bucket gets special CORS for console uploads
resource "aws_s3_bucket_cors_configuration" "glue_scripts" {
  bucket = aws_s3_bucket.this["glue_scripts"].id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST"]
    allowed_origins = ["https://*.amazonaws.com"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}
