output "asg_name" {
  description = "Name of the Auto Scaling group."
  value       = aws_autoscaling_group.this.name
}

output "asg_arn" {
  description = "ARN of the Auto Scaling group."
  value       = aws_autoscaling_group.this.arn
}

output "launch_template_id" {
  description = "ID of the launch template."
  value       = aws_launch_template.this.id
}

output "instance_security_group_id" {
  description = "Security group attached to the instances."
  value       = aws_security_group.instance.id
}

output "instance_role_name" {
  description = "Name of the IAM role assumed by the instances."
  value       = aws_iam_role.instance.name
}

output "run_command_log_group_name" {
  description = "Log group that receives Run Command output (patching, remediation, demo commands)."
  value       = aws_cloudwatch_log_group.this["run_command"].name
}

output "session_log_group_name" {
  description = "Log group that receives Session Manager transcripts."
  value       = aws_cloudwatch_log_group.this["session_audit"].name
}

output "log_group_names" {
  description = "All log groups written by the instances."
  value       = { for k, v in aws_cloudwatch_log_group.this : k => v.name }
}

output "cw_agent_parameter_name" {
  description = "SSM parameter holding the CloudWatch agent configuration."
  value       = aws_ssm_parameter.cw_agent_config.name
}

output "remediation_tag_key" {
  description = "Instance tag key whose value equals the ASG name; the remediation role may only run commands on instances carrying it."
  value       = "AutoRemediationGroup"
}
