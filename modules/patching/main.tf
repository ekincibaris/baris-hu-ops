data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  region     = data.aws_region.current.region
  account_id = data.aws_caller_identity.current.account_id
}

################################################################################
# Patch baseline: security and bug-fix updates, auto-approved after a delay.
################################################################################

resource "aws_ssm_patch_baseline" "this" {
  name             = "${var.name}-al2023"
  description      = "Amazon Linux 2023: Critical/Important security and all bug-fix updates after ${var.approve_after_days} days"
  operating_system = "AMAZON_LINUX_2023"

  approved_patches_compliance_level = "HIGH"

  approval_rule {
    approve_after_days = var.approve_after_days
    compliance_level   = "CRITICAL"

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security"]
    }

    patch_filter {
      key    = "SEVERITY"
      values = ["Critical", "Important"]
    }
  }

  approval_rule {
    approve_after_days = var.approve_after_days
    compliance_level   = "MEDIUM"

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Bugfix"]
    }
  }
}

resource "aws_ssm_patch_group" "this" {
  baseline_id = aws_ssm_patch_baseline.this.id
  patch_group = var.patch_group
}

################################################################################
# Daily compliance scan (no changes) so drift shows up in Patch Manager
# between maintenance windows. Runs at creation too, so new instances report
# immediately.
################################################################################

resource "aws_ssm_association" "scan" {
  name                = "AWS-RunPatchBaseline"
  association_name    = "${var.name}-patch-scan"
  schedule_expression = var.scan_schedule
  compliance_severity = "HIGH"
  max_concurrency     = "50%"
  max_errors          = "100%"

  parameters = {
    Operation = "Scan"
  }

  targets {
    key    = "tag:PatchGroup"
    values = [var.patch_group]
  }
}

################################################################################
# Maintenance window: install approved patches one instance at a time.
################################################################################

resource "aws_ssm_maintenance_window" "this" {
  name                       = "${var.name}-patching"
  description                = "Weekly patch install for ${var.patch_group}"
  schedule                   = var.maintenance_window_schedule
  schedule_timezone          = var.maintenance_window_timezone
  duration                   = var.maintenance_window_duration_hours
  cutoff                     = 1
  allow_unassociated_targets = false
}

resource "aws_ssm_maintenance_window_target" "this" {
  window_id     = aws_ssm_maintenance_window.this.id
  name          = "${var.name}-patch-group"
  description   = "Instances tagged PatchGroup=${var.patch_group}"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:PatchGroup"
    values = [var.patch_group]
  }
}

resource "aws_ssm_maintenance_window_task" "install" {
  window_id        = aws_ssm_maintenance_window.this.id
  name             = "install-patches"
  description      = "AWS-RunPatchBaseline Install with ${var.reboot_option}"
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  priority         = 1
  service_role_arn = aws_iam_role.maintenance_window.arn
  max_concurrency  = "1" # never patch (and reboot) more than one instance at a time
  max_errors       = "1"
  cutoff_behavior  = "CANCEL_TASK"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.this.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      comment          = "Weekly patching for ${var.patch_group}"
      timeout_seconds  = 600
      document_version = "$DEFAULT"

      cloudwatch_config {
        cloudwatch_log_group_name = var.run_command_log_group_name
        cloudwatch_output_enabled = true
      }

      parameter {
        name   = "Operation"
        values = ["Install"]
      }

      parameter {
        name   = "RebootOption"
        values = [var.reboot_option]
      }
    }
  }
}
