output "url" {
  description = "Public URL of the status page."
  value       = module.alb.url
}

output "alb_dns_name" {
  description = "DNS name of the ALB (useful before DNS propagates)."
  value       = module.alb.alb_dns_name
}

output "asg_name" {
  description = "Auto Scaling group name (used by scripts/demo.sh)."
  value       = module.compute.asg_name
}

output "target_group_arn" {
  description = "Target group ARN (used by scripts/demo.sh)."
  value       = module.alb.target_group_arn
}

output "dashboard_url" {
  description = "CloudWatch dashboard for the stack."
  value       = module.monitoring.dashboard_url
}

output "sns_topic_arn" {
  description = "Alarm topic ARN."
  value       = module.monitoring.sns_topic_arn
}

output "remediation_runbook" {
  description = "SSM Automation runbook that restarts unhealthy targets."
  value       = module.remediation.document_name
}

output "remediation_automation_role_arn" {
  description = "Role to pass when starting the runbook by hand."
  value       = module.remediation.automation_role_arn
}

output "patch_group" {
  description = "Patch group (PatchGroup tag value)."
  value       = module.patching.patch_group
}

output "maintenance_window_id" {
  description = "Patching maintenance window ID."
  value       = module.patching.maintenance_window_id
}

output "log_groups" {
  description = "Where to look when something happens."
  value = merge(module.compute.log_group_names, {
    vpc_flow_logs        = module.network.flow_log_group_name
    automation_scripts   = module.remediation.automation_log_group_name
    remediation_triggers = module.remediation.trigger_log_group_name
  })
}

output "session_manager_hint" {
  description = "How to open a shell on an instance without SSH."
  value       = "aws ssm start-session --region ${var.region} --target $(aws autoscaling describe-auto-scaling-groups --region ${var.region} --auto-scaling-group-names ${module.compute.asg_name} --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text)"
}

output "alb_access_log_bucket" {
  description = "S3 bucket with ALB access logs (prefix alb/)."
  value       = module.alb.access_log_bucket
}
