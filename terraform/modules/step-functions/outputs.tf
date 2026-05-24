output "state_machine_arn" {
  description = "ARN of the medallion pipeline state machine"
  value       = aws_sfn_state_machine.medallion_pipeline.arn
}

output "state_machine_name" {
  description = "Name of the medallion pipeline state machine"
  value       = aws_sfn_state_machine.medallion_pipeline.name
}
