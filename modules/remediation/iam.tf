################################################################################
# Automation role: what the runbook itself may do.
################################################################################

data "aws_iam_policy_document" "automation_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:ssm:${local.region}:${local.account_id}:automation-execution/*"]
    }
  }
}

resource "aws_iam_role" "automation" {
  name               = "${var.name}-remediation-automation"
  description        = "Runs ${local.document_name}: read target health, restart via Run Command, escalate to Auto Scaling"
  assume_role_policy = data.aws_iam_policy_document.automation_assume.json
}

data "aws_iam_policy_document" "automation" {
  statement {
    sid = "ReadState"
    actions = [
      "autoscaling:DescribeAutoScalingInstances",
      "elasticloadbalancing:DescribeTargetHealth",
      "ssm:DescribeInstanceInformation",
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
      "ssm:ListCommands",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "SendShellScriptDocument"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ssm:${local.region}::document/AWS-RunShellScript"]
  }

  statement {
    sid       = "SendOnlyToThisGroupsInstances"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ec2:${local.region}:${local.account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/${var.remediation_tag_key}"
      values   = [var.asg_name]
    }
  }

  statement {
    sid       = "CancelOwnCommands"
    actions   = ["ssm:CancelCommand"]
    resources = ["*"]
  }

  statement {
    sid       = "EscalateToAutoScaling"
    actions   = ["autoscaling:SetInstanceHealth"]
    resources = [var.asg_arn]
  }

  statement {
    sid = "WriteScriptLogs"
    actions = [
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.automation.arn}:*"]
  }

  statement {
    sid       = "FindLogGroup"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["arn:aws:logs:${local.region}:${local.account_id}:log-group:*"]
  }

  statement {
    sid       = "NotifyResult"
    actions   = ["sns:Publish"]
    resources = [var.sns_topic_arn]
  }

  statement {
    sid       = "UseEncryptedTopic"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["sns.${local.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "automation" {
  name   = "restart-unhealthy-service"
  role   = aws_iam_role.automation.id
  policy = data.aws_iam_policy_document.automation.json
}

################################################################################
# EventBridge role: may start exactly this runbook and pass exactly this role.
################################################################################

data "aws_iam_policy_document" "events_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "events" {
  name               = "${var.name}-remediation-events"
  description        = "Lets EventBridge start ${local.document_name}"
  assume_role_policy = data.aws_iam_policy_document.events_assume.json
}

data "aws_iam_policy_document" "events" {
  statement {
    sid       = "StartRunbook"
    actions   = ["ssm:StartAutomationExecution"]
    resources = ["arn:aws:ssm:${local.region}:${local.account_id}:automation-definition/${aws_ssm_document.restart.name}:*"]
  }

  statement {
    sid       = "PassAutomationRole"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.automation.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ssm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "events" {
  name   = "start-restart-runbook"
  role   = aws_iam_role.events.id
  policy = data.aws_iam_policy_document.events.json
}
