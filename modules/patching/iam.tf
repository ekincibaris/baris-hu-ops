################################################################################
# Custom maintenance window role (instead of the broad service-linked role):
# may only send AWS-RunPatchBaseline to instances in this patch group.
################################################################################

data "aws_iam_policy_document" "maintenance_window_assume" {
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
  }
}

resource "aws_iam_role" "maintenance_window" {
  name               = "${var.name}-patch-window"
  description        = "Runs AWS-RunPatchBaseline for the ${var.patch_group} maintenance window"
  assume_role_policy = data.aws_iam_policy_document.maintenance_window_assume.json
}

data "aws_iam_policy_document" "maintenance_window" {
  #checkov:skip=CKV_AWS_356:List/Get command APIs and tag-based target resolution do not support resource-level permissions.
  statement {
    sid       = "SendPatchDocument"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ssm:${local.region}::document/AWS-RunPatchBaseline"]
  }

  statement {
    sid       = "SendToPatchGroupOnly"
    actions   = ["ssm:SendCommand"]
    resources = ["arn:aws:ec2:${local.region}:${local.account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "ssm:resourceTag/PatchGroup"
      values   = [var.patch_group]
    }
  }

  statement {
    sid = "TrackCommands"
    actions = [
      "ssm:CancelCommand",
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
      "ssm:ListCommands",
    ]
    resources = ["*"]
  }

  statement {
    sid = "ResolveTagTargets"
    actions = [
      "resource-groups:ListGroupResources",
      "resource-groups:ListGroups",
      "ssm:DescribeInstanceInformation",
      "tag:GetResources",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "maintenance_window" {
  name   = "run-patch-baseline"
  role   = aws_iam_role.maintenance_window.id
  policy = data.aws_iam_policy_document.maintenance_window.json
}
