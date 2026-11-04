output "state_bucket_name" {
  description = "Name of the state bucket."
  value       = aws_s3_bucket.state.id
}

output "backend_config" {
  description = "Paste into envs/prod/backend.hcl."
  value       = "bucket = \"${aws_s3_bucket.state.id}\""
}

output "github_plan_role_arn" {
  description = "Role ARN for the GitHub Actions plan job (store as repository variable AWS_PLAN_ROLE_ARN)."
  value       = var.create_github_oidc_role ? aws_iam_role.github_plan[0].arn : null
}
