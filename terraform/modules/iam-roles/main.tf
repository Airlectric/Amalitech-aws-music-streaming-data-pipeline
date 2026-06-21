data "aws_caller_identity" "current" {}

# ────────────────────────────────────────────
# GLUE SILVER ROLE: bronze → silver
# ────────────────────────────────────────────
resource "aws_iam_role" "glue_silver" {
  name = "${var.environment}-glue-silver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Name = "${var.environment}-glue-silver" })
}

resource "aws_iam_role_policy_attachment" "glue_silver_service_role" {
  role       = aws_iam_role.glue_silver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_silver_s3" {
  name = "${var.environment}-glue-silver-s3"
  role = aws_iam_role.glue_silver.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadBronze"
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = [
          "${var.bucket_arns["bronze"]}/*",
          "${var.bucket_arns["bronze"]}/reference/*",
        ]
      },
      {
        Sid      = "WriteSilver"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = ["${var.bucket_arns["silver"]}/*"]
      },
      {
        Sid      = "ReadGlueScripts"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${var.bucket_arns["glue_scripts"]}/*"]
      },
      {
        Sid      = "WriteGlueTemp"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${var.bucket_arns["glue_scripts"]}/temp/*"]
      },
    ]
  })
}

resource "aws_iam_role_policy" "glue_silver_kms" {
  name = "${var.environment}-glue-silver-kms"
  role = aws_iam_role.glue_silver.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = local.kms_decrypt
      Resource = [var.kms_key_arns["s3-data-lake"]]
    }]
  })
}

resource "aws_iam_role_policy" "glue_silver_cloudwatch" {
  name = "${var.environment}-glue-silver-cloudwatch"
  role = aws_iam_role.glue_silver.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["cloudwatch:PutMetricData"]
      Resource = ["*"]
      Condition = {
        StringEquals = { "cloudwatch:namespace" = "MusicPipeline/DQ" }
      }
    }]
  })
}

# ────────────────────────────────────────────
# GLUE GOLD ROLE: silver → gold
# ────────────────────────────────────────────
resource "aws_iam_role" "glue_gold" {
  name = "${var.environment}-glue-gold"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Name = "${var.environment}-glue-gold" })
}

resource "aws_iam_role_policy_attachment" "glue_gold_service_role" {
  role       = aws_iam_role.glue_gold.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_gold_s3" {
  name = "${var.environment}-glue-gold-s3"
  role = aws_iam_role.glue_gold.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadSilver"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${var.bucket_arns["silver"]}/*"]
      },
      {
        Sid      = "WriteGold"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = ["${var.bucket_arns["gold"]}/*"]
      },
      {
        Sid      = "ReadGlueScripts"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${var.bucket_arns["glue_scripts"]}/*"]
      },
      {
        Sid      = "WriteGlueTemp"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${var.bucket_arns["glue_scripts"]}/temp/*"]
      },
    ]
  })
}

resource "aws_iam_role_policy" "glue_gold_kms" {
  name = "${var.environment}-glue-gold-kms"
  role = aws_iam_role.glue_gold.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = local.kms_decrypt
      Resource = [var.kms_key_arns["s3-data-lake"]]
    }]
  })
}

resource "aws_iam_role_policy" "glue_gold_cloudwatch" {
  name = "${var.environment}-glue-gold-cloudwatch"
  role = aws_iam_role.glue_gold.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["cloudwatch:PutMetricData"]
      Resource = ["*"]
      Condition = {
        StringEquals = { "cloudwatch:namespace" = "MusicPipeline/DQ" }
      }
    }]
  })
}

# ────────────────────────────────────────────
# GLUE DDB ROLE: gold → DynamoDB KPI tables
# ────────────────────────────────────────────
resource "aws_iam_role" "glue_ddb" {
  name = "${var.environment}-glue-ddb"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Name = "${var.environment}-glue-ddb" })
}

resource "aws_iam_role_policy_attachment" "glue_ddb_service_role" {
  role       = aws_iam_role.glue_ddb.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_ddb_s3" {
  name = "${var.environment}-glue-ddb-s3"
  role = aws_iam_role.glue_ddb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadGold"
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = [
          "${var.bucket_arns["gold"]}/genre_kpis_daily/date=*",
          "${var.bucket_arns["gold"]}/top_songs_by_genre_daily/date=*",
          "${var.bucket_arns["gold"]}/top_genres_daily/date=*",
        ]
      },
      {
        Sid      = "ReadGlueScripts"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${var.bucket_arns["glue_scripts"]}/*"]
      },
      {
        Sid      = "WriteGlueTemp"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${var.bucket_arns["glue_scripts"]}/temp/*"]
      },
    ]
  })
}

resource "aws_iam_role_policy" "glue_ddb_dynamodb" {
  count = length(var.dynamodb_kpi_table_arns) > 0 ? 1 : 0
  name  = "${var.environment}-glue-ddb-dynamodb"
  role  = aws_iam_role.glue_ddb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "WriteKpiTables"
      Effect = "Allow"
      Action = [
        "dynamodb:BatchWriteItem",
        "dynamodb:PutItem",
      ]
      Resource = var.dynamodb_kpi_table_arns
    }]
  })
}

resource "aws_iam_role_policy" "glue_ddb_kms" {
  name = "${var.environment}-glue-ddb-kms"
  role = aws_iam_role.glue_ddb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "KmsS3DataLake"
        Effect   = "Allow"
        Action   = local.kms_decrypt
        Resource = [var.kms_key_arns["s3-data-lake"]]
      },
      {
        Sid      = "KmsDynamoDB"
        Effect   = "Allow"
        Action   = local.kms_encrypt_decrypt
        Resource = [var.kms_key_arns["dynamodb"]]
      },
    ]
  })
}

resource "aws_iam_role_policy" "glue_ddb_cloudwatch" {
  name = "${var.environment}-glue-ddb-cloudwatch"
  role = aws_iam_role.glue_ddb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["cloudwatch:PutMetricData"]
      Resource = ["*"]
      Condition = {
        StringEquals = { "cloudwatch:namespace" = "MusicPipeline/DQ" }
      }
    }]
  })
}

# ────────────────────────────────────────────
# LAMBDA VALIDATOR ROLE
# ────────────────────────────────────────────
resource "aws_iam_role" "lambda_validator" {
  name = "${var.environment}-lambda-validator"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Name = "${var.environment}-lambda-validator" })
}

resource "aws_iam_role_policy" "lambda_validator_logs" {
  name = "${var.environment}-lambda-validator-logs"
  role = aws_iam_role.lambda_validator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ]
      Resource = ["arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${var.environment}-event-validator:*"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_validator_xray" {
  role       = aws_iam_role.lambda_validator.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}


resource "aws_iam_role_policy" "lambda_validator_s3" {
  name = "${var.environment}-lambda-validator-s3"
  role = aws_iam_role.lambda_validator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadBronzeStreams"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${var.bucket_arns["bronze"]}/streams/*"]
      },
      {
        Sid      = "TagStreamObjects"
        Effect   = "Allow"
        Action   = ["s3:PutObjectTagging"]
        Resource = ["${var.bucket_arns["bronze"]}/streams/*"]
      },
      {
        Sid      = "WriteManifests"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${var.bucket_arns["bronze"]}/streams/manifests/*"]
      },
    ]
  })
}

resource "aws_iam_role_policy" "lambda_validator_kms" {
  name = "${var.environment}-lambda-validator-kms"
  role = aws_iam_role.lambda_validator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KmsS3DataLake"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
        ]
        Resource = [var.kms_key_arns["s3-data-lake"]]
      },
      {
        Sid    = "KmsDynamoDB"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:Encrypt",
        ]
        Resource = [var.kms_key_arns["dynamodb"]]
      },
    ]
  })
}

resource "aws_iam_role_policy" "lambda_validator_dq" {
  name = "${var.environment}-lambda-validator-dq"
  role = aws_iam_role.lambda_validator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteDQReports"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:BatchWriteItem",
        ]
        Resource = [var.dynamodb_dq_table_arn]
      },
    ]
  })
}

# ────────────────────────────────────────────
# LAMBDA QUARANTINE HANDLER ROLE
# ────────────────────────────────────────────
resource "aws_iam_role" "lambda_quarantiner" {
  name = "${var.environment}-lambda-quarantiner"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Name = "${var.environment}-lambda-quarantiner" })
}

resource "aws_iam_role_policy" "lambda_quarantiner_logs" {
  name = "${var.environment}-lambda-quarantiner-logs"
  role = aws_iam_role.lambda_quarantiner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ]
      Resource = ["arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${var.environment}-quarantine-handler:*"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_quarantiner_xray" {
  role       = aws_iam_role.lambda_quarantiner.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}


resource "aws_iam_role_policy" "lambda_quarantiner_s3" {
  name = "${var.environment}-lambda-quarantiner-s3"
  role = aws_iam_role.lambda_quarantiner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadBronzeQuarantine"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObjectTagging",
        ]
        Resource = ["${var.bucket_arns["bronze"]}/streams/*"]
      },
      {
        Sid      = "WriteQuarantine"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${var.quarantine_bucket_arn}/*"]
      },
    ]
  })
}

resource "aws_iam_role_policy" "lambda_quarantiner_kms" {
  name = "${var.environment}-lambda-quarantiner-kms"
  role = aws_iam_role.lambda_quarantiner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = local.kms_encrypt_decrypt
      Resource = [var.kms_key_arns["s3-data-lake"]]
    }]
  })
}

# ────────────────────────────────────────────
# LAMBDA ARCHIVER ROLE
# ────────────────────────────────────────────
resource "aws_iam_role" "lambda_archiver" {
  name = "${var.environment}-lambda-archiver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Name = "${var.environment}-lambda-archiver" })
}

resource "aws_iam_role_policy" "lambda_archiver_logs" {
  name = "${var.environment}-lambda-archiver-logs"
  role = aws_iam_role.lambda_archiver.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ]
      Resource = ["arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${var.environment}-stream-archiver:*"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_archiver_xray" {
  role       = aws_iam_role.lambda_archiver.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}


resource "aws_iam_role_policy" "lambda_archiver_s3" {
  name = "${var.environment}-lambda-archiver-s3"
  role = aws_iam_role.lambda_archiver.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListBronzeStreams"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [var.bucket_arns["bronze"]]
        Condition = {
          StringLike = { "s3:prefix" = ["streams/landing_date=*"] }
        }
      },
      {
        Sid    = "ReadDeleteBronzeStreams"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectTagging",
          "s3:DeleteObject",
        ]
        Resource = ["${var.bucket_arns["bronze"]}/streams/landing_date=*"]
      },
      {
        Sid      = "WriteArchive"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:PutObjectTagging"]
        Resource = ["${var.bucket_arns["archive"]}/*"]
      },
    ]
  })
}

resource "aws_iam_role_policy" "lambda_archiver_kms" {
  name = "${var.environment}-lambda-archiver-kms"
  role = aws_iam_role.lambda_archiver.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = local.kms_encrypt_decrypt
      Resource = [var.kms_key_arns["s3-data-lake"]]
    }]
  })
}

# ────────────────────────────────────────────
# LAMBDA EVENT ROUTER ROLE
# ────────────────────────────────────────────
resource "aws_iam_role" "lambda_event_router" {
  name = "${var.environment}-lambda-event-router"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Name = "${var.environment}-lambda-event-router" })
}

resource "aws_iam_role_policy" "lambda_event_router_logs" {
  name = "${var.environment}-lambda-event-router-logs"
  role = aws_iam_role.lambda_event_router.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ]
      Resource = ["arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${var.environment}-event-router:*"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_event_router_xray" {
  role       = aws_iam_role.lambda_event_router.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_iam_role_policy" "lambda_event_router_sfn" {
  name = "${var.environment}-lambda-event-router-sfn"
  role = aws_iam_role.lambda_event_router.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StartStateMachine"
        Effect   = "Allow"
        Action   = ["states:StartExecution"]
        Resource = [local.step_functions_arn]
      },
      {
        Sid      = "SendToDeadLetterQueue"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = [local.pipeline_dlq_arn]
      },
    ]
  })
}

# ────────────────────────────────────────────
# STEP FUNCTIONS ROLE
# ────────────────────────────────────────────
resource "aws_iam_role" "step_functions" {
  name = "${var.environment}-step-functions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Name = "${var.environment}-step-functions" })
}

resource "aws_iam_role_policy" "step_functions_glue" {
  name = "${var.environment}-sfn-glue"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StartGlueJobs"
        Effect = "Allow"
        Action = [
          "glue:StartJobRun",
          "glue:GetJobRun",
          "glue:GetJobRuns",
          "glue:BatchStopJobRun",
        ]
        Resource = [
          "arn:aws:glue:${var.aws_region}:${local.account_id}:job/${var.environment}-silver-etl",
          "arn:aws:glue:${var.aws_region}:${local.account_id}:job/${var.environment}-gold-etl",
          "arn:aws:glue:${var.aws_region}:${local.account_id}:job/${var.environment}-ddb-etl",
        ]
      },
      {
        Sid    = "PassRoleGlue"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          aws_iam_role.glue_silver.arn,
          aws_iam_role.glue_gold.arn,
          aws_iam_role.glue_ddb.arn,
        ]
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "glue.amazonaws.com"
          }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "step_functions_lambda" {
  name = "${var.environment}-sfn-lambda"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InvokeValidator"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = [local.lambda_validator_arn]
      },
      {
        Sid      = "InvokeArchiver"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = [local.lambda_archiver_arn]
      },
      {
        Sid      = "InvokeQuarantiner"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = [local.lambda_quarantiner_arn]
      },
    ]
  })
}

resource "aws_iam_role_policy" "step_functions_sns" {
  name = "${var.environment}-sfn-sns"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "PublishAlerts"
      Effect   = "Allow"
      Action   = ["sns:Publish"]
      Resource = [var.sns_alert_topic_arn]
    }]
  })
}

resource "aws_iam_role_policy" "step_functions_xray" {
  name = "${var.environment}-sfn-xray"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords",
        # Required for X-Ray sampling: SFN fetches the current sampling rules at
        # the start of each execution to decide which traces to record.
        "xray:GetSamplingRules",
        "xray:GetSamplingTargets",
      ]
      # X-Ray trace operations are not resource-scoped in IAM; the service
      # requires "*" for all four actions above.
      Resource = ["*"]
    }]
  })
}

# ────────────────────────────────────────────
# EVENTBRIDGE ROLE
# ────────────────────────────────────────────
resource "aws_iam_role" "eventbridge" {
  name = "${var.environment}-eventbridge"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.common_tags, { Name = "${var.environment}-eventbridge" })
}

resource "aws_iam_role_policy" "eventbridge_lambda" {
  name = "${var.environment}-eventbridge-lambda"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "InvokeEventRouter"
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = [local.lambda_event_router_arn]
    }]
  })
}
