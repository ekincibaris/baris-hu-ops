data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

################################################################################
# SNS topic for alarm notifications (KMS encrypted)
################################################################################

resource "aws_sns_topic" "alarms" {
  name              = "${var.name}-alarms"
  display_name      = "ops.baris.hu alarms"
  kms_master_key_id = var.kms_key_arn
}

data "aws_iam_policy_document" "alarms_topic" {
  statement {
    sid = "AccountOwnerManage"
    actions = [
      "SNS:GetTopicAttributes",
      "SNS:SetTopicAttributes",
      "SNS:Subscribe",
      "SNS:ListSubscriptionsByTopic",
      "SNS:Publish",
    ]
    resources = [aws_sns_topic.alarms.arn]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid       = "CloudWatchAlarmsPublish"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alarms.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "alarms" {
  arn    = aws_sns_topic.alarms.arn
  policy = data.aws_iam_policy_document.alarms_topic.json
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

################################################################################
# Alarms
################################################################################

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.name}-alb-5xx"
  alarm_description   = "5xx responses from the ALB or the targets. Runbook: README.md#alarm-alb-5xx"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.alb_5xx_threshold
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  metric_query {
    id          = "total"
    expression  = "FILL(elb, 0) + FILL(target, 0)"
    label       = "5xx responses per minute"
    return_data = true
  }

  metric_query {
    id = "elb"

    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_ELB_5XX_Count"
      period      = 60
      stat        = "Sum"
      dimensions = {
        LoadBalancer = var.alb_arn_suffix
      }
    }
  }

  metric_query {
    id = "target"

    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      period      = 60
      stat        = "Sum"
      dimensions = {
        LoadBalancer = var.alb_arn_suffix
      }
    }
  }
}

# The fast (1-minute) unhealthy alarm lives in the remediation module and
# triggers the restart runbook. This one is the human escalation: it only fires
# if a target is still unhealthy after remediation had time to work.
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts_sustained" {
  alarm_name          = "${var.name}-unhealthy-hosts-sustained"
  alarm_description   = "A target has been unhealthy for ${var.unhealthy_sustained_minutes} minutes: auto-remediation did not fix it. Runbook: README.md#alarm-unhealthy-hosts-sustained"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = var.unhealthy_sustained_minutes
  datapoints_to_alarm = var.unhealthy_sustained_minutes
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "no_healthy_hosts" {
  alarm_name          = "${var.name}-no-healthy-hosts"
  alarm_description   = "No healthy targets behind the ALB: the site is down. Runbook: README.md#alarm-no-healthy-hosts"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.name}-high-cpu"
  alarm_description   = "Group CPU above ${var.cpu_alarm_threshold}% for 10 minutes even though target tracking should have scaled out. Runbook: README.md#alarm-high-cpu"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 10
  datapoints_to_alarm = 8
  threshold           = var.cpu_alarm_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    AutoScalingGroupName = var.asg_name
  }
}
