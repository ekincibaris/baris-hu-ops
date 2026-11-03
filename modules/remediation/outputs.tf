output "alarm_name" {
  description = "Name of the app-health alarm that triggers remediation."
  value       = aws_cloudwatch_metric_alarm.app_unhealthy.alarm_name
}

output "alarm_arn" {
  description = "ARN of the app-health alarm that triggers remediation."
  value       = aws_cloudwatch_metric_alarm.app_unhealthy.arn
}

output "document_name" {
  description = "Name of the SSM Automation runbook."
  value       = aws_ssm_document.restart.name
}

output "automation_role_arn" {
  description = "Role the runbook runs as (pass it when starting the runbook by hand)."
  value       = aws_iam_role.automation.arn
}

output "event_rule_name" {
  description = "EventBridge rule that starts the runbook."
  value       = aws_cloudwatch_event_rule.app_unhealthy.name
}

output "automation_log_group_name" {
  description = "Log group with the runbook's step-by-step script output."
  value       = aws_cloudwatch_log_group.automation.name
}

output "trigger_log_group_name" {
  description = "Log group with every alarm event that triggered the runbook."
  value       = aws_cloudwatch_log_group.events.name
}
