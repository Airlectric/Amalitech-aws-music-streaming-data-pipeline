locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "glue-jobs"
  }

  script_key = "scripts/${var.environment}"
}
