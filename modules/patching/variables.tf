variable "name" {
  description = "Name prefix for every resource in this module, e.g. ops-baris-prod."
  type        = string
}

variable "patch_group" {
  description = "Patch group name; instances opt in with the tag PatchGroup=<patch_group>."
  type        = string
}

variable "maintenance_window_schedule" {
  description = "When patches are installed (cron or rate expression, evaluated in maintenance_window_timezone)."
  type        = string
  default     = "cron(0 3 ? * SUN *)"

  validation {
    condition     = can(regex("^(cron|rate)\\(.+\\)$", var.maintenance_window_schedule))
    error_message = "Use an SSM schedule expression such as cron(0 3 ? * SUN *)."
  }
}

variable "maintenance_window_timezone" {
  description = "IANA time zone of the maintenance window schedule."
  type        = string
  default     = "Europe/Budapest"
}

variable "maintenance_window_duration_hours" {
  description = "Length of the maintenance window in hours."
  type        = number
  default     = 2

  validation {
    condition     = var.maintenance_window_duration_hours >= 1 && var.maintenance_window_duration_hours <= 24
    error_message = "maintenance_window_duration_hours must be between 1 and 24."
  }
}

variable "approve_after_days" {
  description = "Days after release before a patch is auto-approved (lets bad updates surface elsewhere first)."
  type        = number
  default     = 7

  validation {
    condition     = var.approve_after_days >= 0 && var.approve_after_days <= 360
    error_message = "approve_after_days must be between 0 and 360."
  }
}

variable "reboot_option" {
  description = "RebootIfNeeded or NoReboot for the Install operation."
  type        = string
  default     = "RebootIfNeeded"

  validation {
    condition     = contains(["RebootIfNeeded", "NoReboot"], var.reboot_option)
    error_message = "reboot_option must be RebootIfNeeded or NoReboot."
  }
}

variable "scan_schedule" {
  description = "How often a compliance scan (no install) runs on every instance in the patch group."
  type        = string
  default     = "rate(1 day)"
}

variable "run_command_log_group_name" {
  description = "CloudWatch log group that receives the patch command output."
  type        = string
}
