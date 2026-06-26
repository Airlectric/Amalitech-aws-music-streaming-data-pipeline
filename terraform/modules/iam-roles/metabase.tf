# ─────────────────────────────────────────────────────────────────────────────
# METABASE READ-ONLY IAM USER
#
# Grants the minimum permissions needed for Metabase (running outside AWS,
# e.g. on Oracle Cloud) to query the gold Athena views via the analytics
# workgroup and read the underlying Parquet data from the gold S3 bucket.
#
# Access keys must be created manually after apply — do NOT generate them
# via Terraform (the secret would be stored in plain text in Terraform state).
#
# Post-apply steps:
#   1. aws iam create-access-key --user-name <name shown in output>
#   2. Add the key ID + secret to Metabase under Settings → Databases → Athena.
#   3. Set the Athena workgroup to the value in output.athena_workgroup_name.
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_user" "metabase" {
  name = "${var.environment}-metabase"
  path = "/analytics/"

  tags = merge(local.common_tags, { Name = "${var.environment}-metabase" })
}

resource "aws_iam_policy" "metabase" {
  name        = "${var.environment}-metabase-athena-readonly"
  description = "Allows Metabase to run Athena queries against the gold database"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ── Athena: execute queries in the analytics workgroup ────────────────
      {
        Sid    = "AthenaWorkgroup"
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:StopQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:BatchGetQueryExecution",
          "athena:GetWorkGroup",
          "athena:ListWorkGroups",
          "athena:ListNamedQueries",
          "athena:GetNamedQuery",
        ]
        Resource = [
          "arn:aws:athena:${var.aws_region}:${data.aws_caller_identity.current.account_id}:workgroup/${var.athena_workgroup_name}",
        ]
      },
      # ── Glue Catalog: read the gold database schema ────────────────────────
      {
        Sid    = "GlueCatalogRead"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:BatchGetPartition",
        ]
        Resource = [
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:database/${var.environment}_gold_db",
          "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.environment}_gold_db/*",
        ]
      },
      # ── S3: read gold Parquet data ─────────────────────────────────────────
      {
        Sid    = "S3GoldRead"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
        ]
        Resource = ["${var.bucket_arns["gold"]}/*"]
      },
      {
        Sid      = "S3GoldList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [var.bucket_arns["gold"]]
      },
      # ── S3: read/write Athena query results ────────────────────────────────
      {
        Sid    = "S3AthenaResults"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectVersion",
        ]
        Resource = ["${var.bucket_arns["athena_results"]}/*"]
      },
      {
        Sid      = "S3AthenaResultsList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [var.bucket_arns["athena_results"]]
      },
      # ── KMS: decrypt gold + Athena results buckets ─────────────────────────
      {
        Sid    = "KmsDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
        ]
        Resource = [var.kms_key_arns["s3-data-lake"]]
      },
    ]
  })

  tags = merge(local.common_tags, { Name = "${var.environment}-metabase-athena-readonly" })
}

resource "aws_iam_user_policy_attachment" "metabase" {
  user       = aws_iam_user.metabase.name
  policy_arn = aws_iam_policy.metabase.arn
}
