provider "aws" {
  region = var.region

  # Refuses to run against any other account: protects against a wrong AWS_PROFILE.
  allowed_account_ids = var.allowed_account_ids

  default_tags {
    tags = local.common_tags
  }
}
