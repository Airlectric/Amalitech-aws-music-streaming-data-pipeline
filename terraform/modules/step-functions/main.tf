locals {
  definition = jsonencode({
    Comment = "Music Streaming Medallion ETL Pipeline"
    StartAt = "ValidateEvent"
    States = {
      ValidateEvent = {
        Type     = "Task"
        Resource = var.lambda_validator_arn
        Next     = "CheckValidation"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "NotifyFailure"
            ResultPath  = "$.error_info"
          }
        ]
      }
      CheckValidation = {
        Type = "Choice"
        Choices = [
          {
            Variable      = "$.valid"
            BooleanEquals = true
            Next          = "RunSilverETL"
          }
        ]
        Default = "QuarantineFile"
      }
      QuarantineFile = {
        Type       = "Task"
        Resource   = var.lambda_quarantiner_arn
        ResultPath = "$.quarantine_result"
        Next       = "NotifyValidationFailure"
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "NotifyFailure"
            ResultPath  = "$.error_info"
          }
        ]
      }
      NotifyValidationFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = var.sns_alert_topic_arn
          "Message.$" = "States.Format('Data quality validation failed for execution {}. Bucket: {}, Key: {}, RecordCount: {}, Errors: {}', $$.Execution.Id, $.bucket, $.key, $.record_count, $.error_count)"
          "Subject.$" = "States.Format('DQ Failure: {}', $.execution_id)"
        }
        Next = "ValidationFailed"
      }
      RunSilverETL = {
        Type       = "Task"
        Resource   = "arn:aws:states:::glue:startJobRun.sync"
        ResultPath = "$.silver_job"
        Parameters = {
          JobName = var.glue_silver_job_name
          Arguments = {
            "--bronze_bucket.$" = "$.bucket"
            "--stream_key.$"    = "$.key"
            "--silver_path"     = "s3://${var.silver_bucket_id}"
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
        Type       = "Task"
        Resource   = "arn:aws:states:::glue:startJobRun.sync"
        ResultPath = "$.gold_job"
        Parameters = {
          JobName = var.glue_gold_job_name
          Arguments = {
            "--silver_path" = "s3://${var.silver_bucket_id}"
            "--gold_path"   = "s3://${var.gold_bucket_id}"
            "--run_date.$"  = "$.run_date"
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
        Type       = "Task"
        Resource   = "arn:aws:states:::glue:startJobRun.sync"
        ResultPath = "$.ddb_job"
        Parameters = {
          JobName = var.glue_ddb_job_name
          Arguments = {
            "--gold_path"        = "s3://${var.gold_bucket_id}"
            "--table_genre_kpis" = var.genre_kpis_table_name
            "--table_top_songs"  = var.top_songs_table_name
            "--table_top_genres" = var.top_genres_table_name
            "--run_date.$"       = "$.run_date"
          }
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
        Type       = "Task"
        Resource   = var.lambda_archiver_arn
        ResultPath = "$.archive_result"
        Parameters = {
          "execution_id.$" = "$.execution_id"
          "key.$"          = "$.key"
        }
        End = true
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "NotifyFailure"
            ResultPath  = "$.error_info"
          }
        ]
      }
      NotifyFailure = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn    = var.sns_alert_topic_arn
          "Message.$" = "States.Format('Medallion pipeline failed for execution {} at state {}. Bucket: {}, Key: {}', $$.Execution.Id, $$.State.Name, $.bucket, $.key)"
          "Subject.$" = "States.Format('Pipeline Failure: {}', $.execution_id)"
        }
        Next = "PipelineFailed"
      }
      ValidationFailed = {
        Type  = "Fail"
        Error = "DataValidationFailed"
        Cause = "Input file failed validation and was quarantined."
      }
      PipelineFailed = {
        Type  = "Fail"
        Error = "PipelineExecutionFailed"
        Cause = "Pipeline execution failed after notification was sent."
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
