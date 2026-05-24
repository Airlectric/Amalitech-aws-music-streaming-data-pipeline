variable "environment" {
  description = "Environment name"
  type        = string
}

variable "bronze_bucket_id" {
  description = "ID of the Bronze S3 bucket"
  type        = string
}

variable "silver_bucket_id" {
  description = "ID of the Silver S3 bucket"
  type        = string
}

variable "gold_bucket_id" {
  description = "ID of the Gold S3 bucket"
  type        = string
}
