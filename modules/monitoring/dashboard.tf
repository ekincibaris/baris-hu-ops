################################################################################
# One dashboard for the demo and for on-call: traffic, health, scaling, hosts.
################################################################################

locals {
  region = data.aws_region.current.region

  dashboard_widgets = [
    {
      type = "metric", x = 0, y = 0, width = 12, height = 6
      properties = {
        title  = "Requests and 5xx (per minute)"
        region = local.region
        stat   = "Sum"
        period = 60
        metrics = [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
          [".", "HTTPCode_ELB_5XX_Count", ".", "."],
          [".", "HTTPCode_Target_5XX_Count", ".", "."],
        ]
      }
    },
    {
      type = "metric", x = 12, y = 0, width = 12, height = 6
      properties = {
        title  = "Target health"
        region = local.region
        period = 60
        metrics = [
          ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", var.target_group_arn_suffix, "LoadBalancer", var.alb_arn_suffix, { stat = "Minimum" }],
          [".", "UnHealthyHostCount", ".", ".", ".", ".", { stat = "Maximum" }],
        ]
      }
    },
    {
      type = "metric", x = 0, y = 6, width = 12, height = 6
      properties = {
        title  = "CPU vs instances in service"
        region = local.region
        period = 60
        metrics = [
          ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.asg_name, { stat = "Average" }],
          ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", var.asg_name, { stat = "Maximum", yAxis = "right" }],
          [".", "GroupDesiredCapacity", ".", ".", { stat = "Maximum", yAxis = "right" }],
        ]
      }
    },
    {
      type = "metric", x = 12, y = 6, width = 12, height = 6
      properties = {
        title  = "Memory and root disk used (%) - CloudWatch agent"
        region = local.region
        period = 60
        stat   = "Average"
        metrics = [
          ["CWAgent", "mem_used_percent", "AutoScalingGroupName", var.asg_name],
          [".", "disk_used_percent", ".", "."],
        ]
      }
    },
    {
      type = "metric", x = 0, y = 12, width = 12, height = 6
      properties = {
        title  = "Target response time (p95, seconds)"
        region = local.region
        period = 60
        metrics = [
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p95" }],
        ]
      }
    },
    {
      type = "alarm", x = 12, y = 12, width = 12, height = 6
      properties = {
        title = "Alarms"
        alarms = concat(var.additional_alarm_arns, [
          aws_cloudwatch_metric_alarm.alb_5xx.arn,
          aws_cloudwatch_metric_alarm.unhealthy_hosts_sustained.arn,
          aws_cloudwatch_metric_alarm.no_healthy_hosts.arn,
          aws_cloudwatch_metric_alarm.high_cpu.arn,
        ])
      }
    },
  ]
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = var.name
  dashboard_body = jsonencode({ widgets = local.dashboard_widgets })
}
