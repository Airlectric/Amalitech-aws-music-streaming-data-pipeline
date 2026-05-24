locals {
  definition = jsonencode({
    Comment = "Music Streaming Medallion ETL Pipeline"
    StartAt = "ValidateEvent"
    States = {
      ValidateEvent = {
        Type          = "Task"
        Resource      = var.lambda_validator_arn
        Next          = "RunSilverETL"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "NotifyFailure"
            ResultPath  = "$.error_info"
          }
        ]
      }
      RunSilverETL = {
        Type          = "Task"
        Resource      = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = var.glue_silver_job_name
          Arguments = {
            "--bronze_path" = "s3://${var.environment == "dev" ? "bronze" : var.environment}-${var.environment}-data/"
            "--silver_path" = "s3://${var.environment == "dev" ? "silver" : var.environment}-${var.environment}-data/"
          }
        }
        Next = "RunGoldETL"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "NotifyFailure"
            ResultPath  = "$.error_info"
          }
        ]
      }
      RunGoldETL = {
        Type          = "Task"
        Resource      = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = var.glue_gold_job_name
          Arguments = {
            "--silver_path" = "s3://${var.environment == "dev" ? "silver" : var.environment}-${var.environment}-data/"
            "--gold_path"   = "s3://${var.environment == "dev" ? "gold" : var.environment}-${var.environment}-data/"
          }
        }
        Next = "RunDDBETL"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "NotifyFailure"
            ResultPath  = "$.error_info"
          }
        ]
      }
      RunDDBETL = {
        Type          = "Task"
        Resource      = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = var.glue_ddb_job_name
          Arguments = {}
        }
        Next = "ArchiveFiles"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "NotifyFailure"
            ResultPath  = "$.error_info"
          }
        ]
      }
      ArchiveFiles = {
        Type          = "Task"
        Resource      = var.lambda_archiver_arn
        End           = true
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "NotifyFailure"
            ResultPath  = "$.error_info"
          }
        ]
      }
      NotifyFailure = {
        Type         = "Task"
        Resource     = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn   = var.sns_alert_topic_arn != null ? var.sns_alert_topic_arn : "arn:aws:sns:us-east-1:000000000000:placeholder"
          Message    = "Medallion pipeline failed for execution $$.Execution.Id at state $$.State.Name"
          Subject    = "Pipeline Failure: $$.Execution.Id"
        }
        End = true
      }
    }
  })
}

resource "aws_sfn_state_machine" "medallion_pipeline" {
  name     = "${var.environment}-medallion-pipeline"
  role_arn = var.step_functions_role_arn

  definition = local.definition
  type       = "STANDARD"

  tracing_configuration {
    enabled = true
  }

  tags = merge(local.common_tags, { Name = "${var.environment}-medallion-pipeline" })
}
