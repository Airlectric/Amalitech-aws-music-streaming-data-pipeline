terraform {
  backend "s3" {
    bucket         = "music-streaming-tfstate-108782069549"
    key            = "terraform/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
