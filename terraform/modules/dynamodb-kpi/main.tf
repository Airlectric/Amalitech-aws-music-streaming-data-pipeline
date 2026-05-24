resource "aws_dynamodb_table" "this" {
  for_each = local.tables

  name         = "${var.environment}-${each.key}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = each.value.pk
  range_key    = each.value.sk

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  attribute {
    name = each.value.pk
    type = "S"
  }

  attribute {
    name = each.value.sk
    type = "S"
  }

  dynamic "ttl" {
    for_each = each.value.ttl_days != null ? [1] : []
    content {
      attribute_name = "expires_at"
      enabled        = true
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.environment}-${each.key}"
  })
}
