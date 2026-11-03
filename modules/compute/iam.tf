################################################################################
# Instance role: only what SSM Agent, the CloudWatch agent and Session Manager
# need. Equivalent to AmazonSSMManagedInstanceCore minus the account-wide
# ssm:GetParameter(s), plus scoped log and metric permissions.
################################################################################

data "aws_iam_policy_document" "instance_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name}-web-instance"
  description        = "Status page instances: SSM managed, CloudWatch agent, no SSH"
  assume_role_policy = data.aws_iam_policy_document.instance_assume.json
}

data "aws_iam_policy_document" "instance" {
  #checkov:skip=CKV_AWS_111:SSM Agent APIs (UpdateInstanceInformation, PutInventory, ssmmessages, ec2messages) are called by the agent for its own instance and are granted on * in AWS's own AmazonSSMManagedInstanceCore policy.
  #checkov:skip=CKV_AWS_356:Same as above: these agent APIs are not usefully scoped by resource for an instance that does not know its ARN in advance.
  statement {
    sid = "SsmAgentCore"
    actions = [
      "ssm:DescribeAssociation",
      "ssm:DescribeDocument",
      "ssm:GetDeployablePatchSnapshotForInstance",
      "ssm:GetDocument",
      "ssm:GetManifest",
      "ssm:ListAssociations",
      "ssm:ListInstanceAssociations",
      "ssm:PutComplianceItems",
      "ssm:PutConfigurePackageResult",
      "ssm:PutInventory",
      "ssm:UpdateAssociationStatus",
      "ssm:UpdateInstanceAssociationStatus",
      "ssm:UpdateInstanceInformation",
    ]
    resources = ["*"]
  }

  statement {
    sid = "SessionManagerChannels"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }

  statement {
    sid = "RunCommandMessages"
    actions = [
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ReadCloudWatchAgentConfig"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.cw_agent_config.arn]
  }

  statement {
    sid = "WriteOwnLogGroups"
    actions = [
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:${local.region}:${local.account_id}:log-group:/${var.name}/ec2/*"]
  }

  statement {
    # Session Manager checks that the target log group is encrypted before streaming.
    sid       = "DescribeLogGroups"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["arn:aws:logs:${local.region}:${local.account_id}:log-group:*"]
  }

  statement {
    sid       = "PublishAgentMetrics"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"] # PutMetricData has no resource type; scoped by namespace instead

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["CWAgent"]
    }
  }

  statement {
    sid       = "DecryptSessionManagerData"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "instance" {
  name   = "status-page-instance"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.instance.json
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-web-instance"
  role = aws_iam_role.instance.name
}
