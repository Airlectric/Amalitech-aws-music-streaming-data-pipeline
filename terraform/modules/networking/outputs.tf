output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = aws_subnet.private.id
}

output "private_subnet_cidr" {
  description = "CIDR block of the private subnet"
  value       = aws_subnet.private.cidr_block
}

output "availability_zone" {
  description = "Availability zone of the private subnet"
  value       = aws_subnet.private.availability_zone
}

output "security_group_glue_id" {
  description = "ID of the Glue security group"
  value       = aws_security_group.glue.id
}

output "security_group_lambda_id" {
  description = "ID of the Lambda security group"
  value       = aws_security_group.lambda.id
}

output "security_group_endpoints_id" {
  description = "ID of the VPC endpoints security group"
  value       = aws_security_group.endpoints.id
}

output "route_table_private_id" {
  description = "ID of the private route table"
  value       = aws_route_table.private.id
}

output "flow_log_group_name" {
  description = "CloudWatch log group name for VPC flow logs"
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.flow_logs[0].name : null
}

output "endpoint_interface_ids" {
  description = "Map of interface endpoint IDs by service name"
  value = {
    for k, e in aws_vpc_endpoint.interface : k => e.id
  }
}

output "endpoint_gateway_ids" {
  description = "Map of gateway endpoint IDs by service name"
  value = {
    for k, e in aws_vpc_endpoint.gateway : k => e.id
  }
}
