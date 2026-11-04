output "patch_baseline_id" {
  description = "ID of the custom AL2023 patch baseline."
  value       = aws_ssm_patch_baseline.this.id
}

output "patch_group" {
  description = "Patch group name (value of the PatchGroup tag)."
  value       = aws_ssm_patch_group.this.patch_group
}

output "maintenance_window_id" {
  description = "ID of the patching maintenance window."
  value       = aws_ssm_maintenance_window.this.id
}

output "scan_association_id" {
  description = "ID of the daily compliance scan association."
  value       = aws_ssm_association.scan.association_id
}
