resource "aws_cloudwatch_event_rule" "bronze_s3_put" {
  name        = "${var.environment}-bronze-s3-put"
  description = "Capture S3 PutObject events on the Bronze bucket"

  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail = {
      bucket = {
        name = [var.bronze_bucket_id]
      }
      object = {
        key = [
          { prefix = "streams/landing_date=" }
        ]
      }
    }
  })

  tags = merge(local.common_tags, { Name = "${var.environment}-bronze-s3-put" })
}

resource "aws_cloudwatch_event_target" "event_router" {
  rule      = aws_cloudwatch_event_rule.bronze_s3_put.name
  target_id = "EventRouterLambda"
  arn       = var.event_router_lambda_arn
  role_arn  = var.eventbridge_role_arn

  # Retry delivery, then dead-letter rather than drop the event.
  retry_policy {
    maximum_retry_attempts       = 2
    maximum_event_age_in_seconds = 3600
  }

  dead_letter_config {
    arn = var.dlq_arn
  }
}
