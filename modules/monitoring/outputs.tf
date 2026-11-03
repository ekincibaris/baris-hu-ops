output "sns_topic_arn" {
  description = "ARN of the alarm notification topic."
  value       = aws_sns_topic.alarms.arn
}

output "alarm_names" {
  description = "Names of the alarms owned by this module."
  value = [
    aws_cloudwatch_metric_alarm.alb_5xx.alarm_name,
    aws_cloudwatch_metric_alarm.unhealthy_hosts_sustained.alarm_name,
    aws_cloudwatch_metric_alarm.no_healthy_hosts.alarm_name,
    aws_cloudwatch_metric_alarm.high_cpu.alarm_name,
  ]
}

output "dashboard_url" {
  description = "Console URL of the CloudWatch dashboard."
  value       = "https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.this.dashboard_name}"
}
