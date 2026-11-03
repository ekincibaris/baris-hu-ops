variable "name" {
  description = "Name prefix for every resource in this module, e.g. ops-baris-prod."
  type        = string
}

variable "target_group_arn" {
  description = "Target group whose unhealthy targets are remediated."
  type        = string
}

variable "target_group_arn_suffix" {
  description = "ARN suffix of the target group (TargetGroup dimension)."
  type        = string
}

variable "alb_arn_suffix" {
  description = "ARN suffix of the ALB (LoadBalancer dimension)."
  type        = string
}

variable "asg_name" {
  description = "Auto Scaling group that owns the instances."
  type        = string
}

variable "asg_arn" {
  description = "ARN of the Auto Scaling group (scopes autoscaling:SetInstanceHealth)."
  type        = string
}

variable "remediation_tag_key" {
  description = "Instance tag whose value must equal asg_name for Run Command to be allowed."
  type        = string
  default     = "AutoRemediationGroup"
}

variable "service_name" {
  description = "systemd unit the runbook restarts."
  type        = string
  default     = "nginx"

  validation {
    condition     = can(regex("^[A-Za-z0-9@._-]{1,64}$", var.service_name))
    error_message = "service_name must be a plain systemd unit name."
  }
}

variable "escalate_to_replace" {
  description = "If the restart does not bring the target back, mark the instance Unhealthy so Auto Scaling replaces it."
  type        = bool
  default     = true
}

variable "verify_timeout_seconds" {
  description = "How long the runbook waits for a restarted target to pass ALB health checks."
  type        = number
  default     = 120

  validation {
    condition     = var.verify_timeout_seconds >= 30 && var.verify_timeout_seconds <= 300
    error_message = "verify_timeout_seconds must be between 30 and 300."
  }
}

variable "sns_topic_arn" {
  description = "Alarm topic: receives the trigger alarm and the runbook's result summary."
  type        = string
}

variable "run_command_log_group_name" {
  description = "Log group that receives Run Command output from the restart step."
  type        = string
}

variable "kms_key_arn" {
  description = "Customer managed KMS key (log groups, SNS topic)."
  type        = string
}

variable "log_retention_days" {
  description = "Retention in days for the remediation log groups."
  type        = number
  default     = 365
}

variable "manage_automation_log_settings" {
  description = "Point the account/region-wide SSM Automation script log setting at this module's log group. Disable if another stack owns it."
  type        = bool
  default     = true
}
