################################################################################
# Optional: read-only role for the (commented-out) terraform plan job in
# .github/workflows/terraform.yml. Off by default. See docs/GITHUB-OIDC.md.
################################################################################

locals {
  github_oidc_url = "token.actions.githubusercontent.com"
  github_oidc_provider_arn = var.create_github_oidc_role ? (
    var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
  ) : null
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_role && var.create_github_oidc_provider ? 1 : 0

  url            = "https://${local.github_oidc_url}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_role && !var.create_github_oidc_provider ? 1 : 0

  url = "https://${local.github_oidc_url}"
}

data "aws_iam_policy_document" "github_plan_assume" {
  count = var.create_github_oidc_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Only pull_request workflows of this repository; not forks, not other branches' pushes.
    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_url}:sub"
      values   = ["repo:${var.github_repository}:pull_request"]
    }
  }
}

resource "aws_iam_role" "github_plan" {
  count = var.create_github_oidc_role ? 1 : 0

  name                 = "ops-baris-github-terraform-plan"
  description          = "Assumed by GitHub Actions (OIDC) to run terraform plan on pull requests. Read-only."
  assume_role_policy   = data.aws_iam_policy_document.github_plan_assume[0].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "github_plan_readonly" {
  count = var.create_github_oidc_role ? 1 : 0

  role       = aws_iam_role.github_plan[0].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "github_plan_state" {
  count = var.create_github_oidc_role ? 1 : 0

  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid       = "ReadState"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }

  # plan takes the S3 lock: it creates and deletes <key>.tflock next to the state.
  statement {
    sid       = "ManageLockFile"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*.tflock"]
  }
}

resource "aws_iam_role_policy" "github_plan_state" {
  count = var.create_github_oidc_role ? 1 : 0

  name   = "terraform-state-access"
  role   = aws_iam_role.github_plan[0].id
  policy = data.aws_iam_policy_document.github_plan_state[0].json
}
