locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Domain      = "networking"
  }

  vpc_endpoint_services = {
    glue          = { service = "glue" }
    states        = { service = "states" }
    kms           = { service = "kms" }
    logs          = { service = "logs" }
    monitoring    = { service = "monitoring" }
    sqs           = { service = "sqs" }
    sns           = { service = "sns" }
    secretsmanager = { service = "secretsmanager" }
    sts           = { service = "sts" }
    ecr_api       = { service = "ecr.api" }
    ecr_dkr       = { service = "ecr.dkr" }
    athena        = { service = "athena" }
  }

  gateway_endpoint_services = {
    s3        = { service = "s3" }
    dynamodb  = { service = "dynamodb" }
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, { Name = "${var.environment}-main" })
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, { Name = "${var.environment}-private-${var.availability_zone}" })
}

resource "aws_security_group" "endpoints" {
  name        = "${var.environment}-vpc-endpoints"
  description = "Security group for VPC interface endpoints"
  vpc_id      = aws_vpc.main.id

  tags = local.common_tags
}

resource "aws_security_group" "glue" {
  name        = "${var.environment}-glue"
  description = "Security group for AWS Glue jobs"
  vpc_id      = aws_vpc.main.id

  tags = local.common_tags
}

resource "aws_security_group" "lambda" {
  name        = "${var.environment}-lambda"
  description = "Security group for Lambda functions"
  vpc_id      = aws_vpc.main.id

  tags = local.common_tags
}

resource "aws_security_group_rule" "endpoints_ingress_glue" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.glue.id
  security_group_id        = aws_security_group.endpoints.id
  description              = "HTTPS from Glue security group"
}

resource "aws_security_group_rule" "endpoints_ingress_lambda" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.lambda.id
  security_group_id        = aws_security_group.endpoints.id
  description              = "HTTPS from Lambda security group"
}

resource "aws_security_group_rule" "glue_egress_endpoints" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.endpoints.id
  security_group_id        = aws_security_group.glue.id
  description              = "HTTPS to VPC endpoints"
}

resource "aws_security_group_rule" "lambda_egress_endpoints" {
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.endpoints.id
  security_group_id        = aws_security_group.lambda.id
  description              = "HTTPS to VPC endpoints"
}

resource "aws_vpc_endpoint" "gateway" {
  for_each = local.gateway_endpoint_services

  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.${each.value.service}"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [aws_route_table.private.id]

  tags = merge(local.common_tags, { Name = "${var.environment}-gw-${each.key}" })
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.vpc_endpoint_services

  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.${each.value.service}"
  vpc_endpoint_type = "Interface"

  subnet_ids        = [aws_subnet.private.id]
  security_group_ids = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, { Name = "${var.environment}-vpce-${each.key}" })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, { Name = "${var.environment}-private" })
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

data "aws_region" "current" {}

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/flowlogs/${var.environment}-main"
  retention_in_days = var.retention_days
  kms_key_id        = var.kms_key_arn

  tags = local.common_tags
}

resource "aws_flow_log" "main" {
  count = var.enable_flow_logs ? 1 : 0

  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id

  tags = local.common_tags
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.environment}-vpc-flow-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.environment}-vpc-flow-logs"
  role = aws_iam_role.flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_default_network_acl" "main" {
  default_network_acl_id = aws_vpc.main.default_network_acl_id

  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = local.common_tags
}

resource "aws_default_security_group" "main" {
  vpc_id = aws_vpc.main.id

  ingress {
    protocol  = "-1"
    self      = true
    from_port = 0
    to_port   = 0
  }

  egress {
    protocol  = "-1"
    self      = true
    from_port = 0
    to_port   = 0
  }

  tags = local.common_tags
}
