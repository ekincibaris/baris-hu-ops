variable "allowed_account_ids" {
  description = "AWS account IDs this configuration may be applied to."
  type        = list(string)

  validation {
    condition     = length(var.allowed_account_ids) > 0 && alltrue([for id in var.allowed_account_ids : can(regex("^[0-9]{12}$", id))])
    error_message = "Provide at least one 12-digit AWS account ID."
  }
}

variable "region" {
  description = "Region of the state bucket (must match the backend region in envs/*)."
  type        = string
  default     = "eu-central-1"
}

variable "state_bucket_name" {
  description = "Globally unique name of the state bucket, e.g. ops-baris-hu-tfstate-<account id>."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket_name))
    error_message = "state_bucket_name must be a valid S3 bucket name."
  }
}

variable "noncurrent_version_retention_days" {
  description = "Days to keep old state versions (your undo button for a broken state)."
  type        = number
  default     = 90
}

variable "create_github_oidc_role" {
  description = "Create the read-only IAM role GitHub Actions assumes for terraform plan (see docs/GITHUB-OIDC.md)."
  type        = bool
  default     = false
}

variable "create_github_oidc_provider" {
  description = "Create the GitHub OIDC identity provider. Set false if the account already has token.actions.githubusercontent.com."
  type        = bool
  default     = true
}

variable "github_repository" {
  description = "owner/repo allowed to assume the plan role."
  type        = string
  default     = "ekincibaris/baris-hu-ops"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be in owner/repo form."
  }
}
