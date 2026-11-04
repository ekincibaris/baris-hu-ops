data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  region     = data.aws_region.current.region
  account_id = data.aws_caller_identity.current.account_id

  document_name = "${var.name}-RestartUnhealthyService"
}

################################################################################
# Trigger: fast app-health alarm (1 minute) on the target group
################################################################################

resource "aws_cloudwatch_metric_alarm" "app_unhealthy" {
  alarm_name          = "${var.name}-app-unhealthy"
  alarm_description   = "At least one target failed ALB health checks. EventBridge starts ${local.document_name} automatically. Runbook: README.md#alarm-app-unhealthy"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }
}

################################################################################
# Runbook
################################################################################

resource "aws_ssm_document" "restart" {
  name            = local.document_name
  document_type   = "Automation"
  document_format = "YAML"
  content         = file("${path.module}/documents/restart-unhealthy-service.yaml")
}

################################################################################
# EventBridge: alarm state change -> SSM Automation (+ audit log of the event)
################################################################################

resource "aws_cloudwatch_event_rule" "app_unhealthy" {
  name        = "${var.name}-app-unhealthy-remediate"
  description = "Start ${local.document_name} when ${aws_cloudwatch_metric_alarm.app_unhealthy.alarm_name} goes to ALARM"

  event_pattern = jsonencode({
    source        = ["aws.cloudwatch"]
    "detail-type" = ["CloudWatch Alarm State Change"]
    resources     = [aws_cloudwatch_metric_alarm.app_unhealthy.arn]
    detail = {
      state = {
        value = ["ALARM"]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "start_automation" {
  rule      = aws_cloudwatch_event_rule.app_unhealthy.name
  target_id = "start-restart-runbook"
  arn       = "arn:aws:ssm:${local.region}:${local.account_id}:automation-definition/${aws_ssm_document.restart.name}:$DEFAULT"
  role_arn  = aws_iam_role.events.arn

  input = jsonencode({
    AutomationAssumeRole = [aws_iam_role.automation.arn]
    TargetGroupArn       = [var.target_group_arn]
    AutoScalingGroupName = [var.asg_name]
    ServiceName          = [var.service_name]
    RunCommandLogGroup   = [var.run_command_log_group_name]
    NotificationTopicArn = [var.sns_topic_arn]
    EscalateToReplace    = [tostring(var.escalate_to_replace)]
    VerifyTimeoutSeconds = [tostring(var.verify_timeout_seconds)]
  })

  retry_policy {
    maximum_event_age_in_seconds = 300
    maximum_retry_attempts       = 3
  }
}

resource "aws_cloudwatch_log_group" "events" {
  # EventBridge can only deliver to log groups under /aws/events/.
  name              = "/aws/events/${var.name}/remediation-triggers"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

data "aws_iam_policy_document" "events_to_logs" {
  statement {
    sid       = "EventBridgeWriteTriggerLog"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.events.arn}:*"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "delivery.logs.amazonaws.com"]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "events" {
  policy_name     = "${var.name}-remediation-triggers"
  policy_document = data.aws_iam_policy_document.events_to_logs.json
}

resource "aws_cloudwatch_event_target" "audit_log" {
  rule      = aws_cloudwatch_event_rule.app_unhealthy.name
  target_id = "audit-log"
  arn       = aws_cloudwatch_log_group.events.arn

  depends_on = [aws_cloudwatch_log_resource_policy.events]
}

################################################################################
# Automation script logs: aws:executeScript output goes to CloudWatch Logs.
# These are account/region-wide SSM service settings (reset on destroy).
################################################################################

resource "aws_cloudwatch_log_group" "automation" {
  name              = "/${var.name}/ssm/automation"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_ssm_service_setting" "automation_log_destination" {
  count = var.manage_automation_log_settings ? 1 : 0

  setting_id    = "arn:aws:ssm:${local.region}:${local.account_id}:servicesetting/ssm/automation/customer-script-log-destination"
  setting_value = "CloudWatch"
}

resource "aws_ssm_service_setting" "automation_log_group" {
  count = var.manage_automation_log_settings ? 1 : 0

  setting_id    = "arn:aws:ssm:${local.region}:${local.account_id}:servicesetting/ssm/automation/customer-script-log-group-name"
  setting_value = aws_cloudwatch_log_group.automation.name
}
